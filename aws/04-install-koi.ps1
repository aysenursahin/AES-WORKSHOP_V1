# ---------------------------------------------------------------------------
# 04 - Koi'yi tum katilimci makinelerine kurar
#
# Kurulum komutu aws\koi-install-command.ps1 dosyasindan okunur. Bu dosyayi
# koi-install-command.example.ps1'den olusturun ve Deployment Portal'daki
# komutu yapistirin. Dosya customer ID icerdigi icin GitHub'a yuklenmez.
#
# Deployment Portal "msiexec /i Koi.msi ..." komutu veriyorsa Koi.msi'yi bu
# klasore (aws/) koyun. Script MSI'yi hesabinizdaki private bir S3 bucket'a
# yukler, makineler gecici (2 saatlik) bir linkle indirir ve sessiz kurar.
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

# ----- msiexec komutu: Koi.msi'yi S3 uzerinden dagit, sessiz kur -----
$installBlock = $installCmd
$cmdLine = @($installCmd -split "`r?`n" | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith("#") }) -join " "
if ($cmdLine -match '^\s*msiexec(\.exe)?\s+(.+)$') {
    $msiArgs = $Matches[2].Trim()
    $msiLocal = Join-Path $PSScriptRoot "Koi.msi"
    if (-not (Test-Path $msiLocal)) {
        throw "Kurulum komutu msiexec kullaniyor ama aws/Koi.msi bulunamadi. Koi.msi'yi CloudShell'e yukleyip bu klasore tasiyin."
    }

    $acct   = (Invoke-Aws @("sts", "get-caller-identity")).Account
    $bucket = if ($KoiMsiBucket) { $KoiMsiBucket } else { "aes-workshop-$acct-$Region" }
    $exists = $true
    try { Invoke-Aws @("s3api", "head-bucket", "--bucket", $bucket) | Out-Null } catch { $exists = $false }
    if (-not $exists) {
        Write-Host "==> S3 bucket olusturuluyor: $bucket" -ForegroundColor Cyan
        $cb = @("s3api", "create-bucket", "--bucket", $bucket)
        if ($Region -ne "us-east-1") { $cb += @("--create-bucket-configuration", "LocationConstraint=$Region") }
        Invoke-Aws $cb | Out-Null
        Invoke-Aws @("s3api", "put-public-access-block", "--bucket", $bucket, "--public-access-block-configuration",
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true") | Out-Null
    }
    Write-Host "==> Koi.msi yukleniyor: s3://$bucket/Koi.msi" -ForegroundColor Cyan
    Invoke-Aws @("s3api", "put-object", "--bucket", $bucket, "--key", "Koi.msi", "--body", $msiLocal) | Out-Null

    $presignArgs = @("s3", "presign", "s3://$bucket/Koi.msi", "--expires-in", "7200", "--region", $Region)
    if ($AwsProfile) { $presignArgs += @("--profile", $AwsProfile) }
    $url = (& aws @presignArgs | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $url.StartsWith("https://")) { throw "Koi.msi icin indirme linki olusturulamadi." }

    # /i <dosya> kismini indirilen MSI'nin tam yoluna cevir, sessiz kurulum parametrelerini ekle
    $msiArgs = $msiArgs -replace '(?i)/i\s+("[^"]+"|\S+)', '/i "C:\WorkshopSetup\Koi.msi"'
    if ($msiArgs -notmatch '(?i)/q') { $msiArgs += ' /qn' }
    if ($msiArgs -notmatch '(?i)/norestart') { $msiArgs += ' /norestart' }
    if ($msiArgs -notmatch '(?i)/l') { $msiArgs += ' /l*v "C:\WorkshopSetup\koi-install.log"' }
    Write-Host "msiexec $msiArgs" -ForegroundColor DarkGray

    $installBlock = @'
New-Item -ItemType Directory -Force -Path 'C:\WorkshopSetup' | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri '__URL__' -OutFile 'C:\WorkshopSetup\Koi.msi' -UseBasicParsing
$p = Start-Process -FilePath msiexec.exe -ArgumentList '__ARGS__' -Wait -PassThru
Write-Output "msiexec cikis kodu: $($p.ExitCode)"
if (@(0, 3010) -notcontains $p.ExitCode) {
    if (Test-Path 'C:\WorkshopSetup\koi-install.log') { Get-Content 'C:\WorkshopSetup\koi-install.log' -Tail 25 }
    exit 1
}
'@
    $installBlock = $installBlock.Replace('__URL__', $url).Replace('__ARGS__', $msiArgs.Replace("'", "''"))
}

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
$installBlock
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
