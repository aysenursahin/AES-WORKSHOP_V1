# ---------------------------------------------------------------------------
# 03 - Her makinenin hostname'ini Name tag'ine gore degistirir (WS-USER01, ...)
#
# AMI'den acilan tum makineler base makinenin adini tasir. Bu script her
# birini kendi adina cevirir ve yeniden baslatir. Zaten dogru adda olanlara
# dokunmaz.
#
# Kullanim:
#   .\03-rename-hosts.ps1                      # tum makineler
#   .\03-rename-hosts.ps1 -Only WS-USER01      # tek makine
# ---------------------------------------------------------------------------
param([string[]]$Only)
. "$PSScriptRoot\common.ps1"

$instances = @(Get-WorkshopInstances -Only $Only | Where-Object { $_.State -eq "running" })
if ($instances.Count -eq 0) { throw "Calisan workshop instance'i bulunamadi." }

Wait-SsmOnline $instances

$sent = @()
foreach ($inst in $instances) {
    # exit 3010: SSM makineyi yeniden baslatir ve script'i tekrar calistirir.
    # Ikinci calismada hostname dogru oldugu icin exit 0 ile biter.
    $script = @"
`$new = '$($inst.Name)'
if (`$env:COMPUTERNAME -eq `$new) { Write-Output "Hostname: `$new"; exit 0 }
Rename-Computer -NewName `$new -Force
Write-Output "Hostname `$new olarak degistirildi, yeniden baslatiliyor"
exit 3010
"@
    $sent += Send-SsmScript -InstanceIds @($inst.InstanceId) -Script $script -Comment "rename $($inst.Name)"
}

Write-Host "==> Hostname degisiklikleri bekleniyor (yeniden baslatma dahil)..." -ForegroundColor Cyan
Wait-SsmCommands -Sent $sent -Instances $instances | Out-Null
Write-Host "Siradaki adim: 04-install-koi.ps1"
