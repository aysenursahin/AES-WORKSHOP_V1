# ---------------------------------------------------------------------------
# 04 - Koi'yi tum katilimci makinelerine kurar
#
# Kurulum komutu aws\koi-install-command.ps1 dosyasindan okunur. Bu dosyayi
# koi-install-command.example.ps1'den olusturun ve Deployment Portal'daki
# komutu yapistirin. Dosya customer ID icerdigi icin GitHub'a yuklenmez.
#
# Komut SSM uzerinden SYSTEM olarak calisir. Once tek makinede deneyin:
#   .\04-install-koi.ps1 -Only WS-USER01
# Sonra hepsine:
#   .\04-install-koi.ps1
# Koi zaten kurulu olan makineler atlanir.
# ---------------------------------------------------------------------------
param([string[]]$Only)
. "$PSScriptRoot\common.ps1"

$cmdFile = Join-Path $PSScriptRoot "koi-install-command.ps1"
if (-not (Test-Path $cmdFile)) {
    throw "koi-install-command.ps1 bulunamadi. koi-install-command.example.ps1'den olusturup Deployment Portal'daki komutu yapistirin."
}
$installCmd = Get-Content $cmdFile -Raw
$hasCommand = @($installCmd -split "`r?`n" | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith("#") }).Count -gt 0
if (-not $hasCommand) { throw "koi-install-command.ps1 icinde calistirilacak bir komut yok." }

$instances = @(Get-WorkshopInstances -Only $Only | Where-Object { $_.State -eq "running" })
if ($instances.Count -eq 0) { throw "Calisan workshop instance'i bulunamadi." }

Wait-SsmOnline $instances

$script = @"
if (`$env:COMPUTERNAME -notlike '$NamePrefix*') {
    Write-Output "HATA: Hostname degismemis (`$env:COMPUTERNAME). Once 03-rename-hosts.ps1 calistirin."
    exit 1
}
`$svc = Get-Service | Where-Object { `$_.DisplayName -like '$KoiServicePattern' }
if (`$svc) { Write-Output "Koi zaten kurulu: `$(`$svc.DisplayName) [`$(`$svc.Status)]"; exit 0 }

# ----- Deployment Portal'daki Koi kurulum komutu -----
$installCmd
# ----- Kurulum komutu sonu -----

Start-Sleep -Seconds 20
`$svc = Get-Service | Where-Object { `$_.DisplayName -like '$KoiServicePattern' }
if (`$svc) { Write-Output "Koi kuruldu: `$(`$svc.DisplayName) [`$(`$svc.Status)]"; exit 0 }
Write-Output "UYARI: Kurulum komutu calisti ama '$KoiServicePattern' adli servis bulunamadi."
Write-Output "Servis adini Get-Service ile kontrol edip config.ps1'deki KoiServicePattern'i duzeltin."
exit 1
"@

Write-Host "==> Koi kuruluyor: $($instances.Count) makine" -ForegroundColor Cyan
$sent = Send-SsmScript -InstanceIds @($instances | ForEach-Object { $_.InstanceId }) -Script $script -Comment "koi install"
Wait-SsmCommands -Sent $sent -Instances $instances | Out-Null
Write-Host "Siradaki adim: 05-check.ps1 (envanterin dolmasi icin birkac saat bekleyin)"
