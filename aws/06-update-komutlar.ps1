# ---------------------------------------------------------------------------
# 06 - Masaustu dosyalarini tum makinelerde gunceller:
#   - komutlar.txt (GitHub'dan)
#   - "AES Lab Rehberi" kisayolu (LabGuideUrl)
#
# AMI'yi yeniden almadan tum makinelere dagitmak icin kullanin.
# Not: GitHub raw icerigi birkac dakika onbellekte kalabilir.
# ---------------------------------------------------------------------------
param([string[]]$Only)
. "$PSScriptRoot\common.ps1"
Assert-Configured @("RepoRawBase", "WorkshopUser")

$instances = @(Get-WorkshopInstances -Only $Only | Where-Object { $_.State -eq "running" })
if ($instances.Count -eq 0) { throw "Calisan workshop instance'i bulunamadi." }

Wait-SsmOnline $instances

$script = @"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
`$dest = 'C:\Users\$WorkshopUser\Desktop\komutlar.txt'
Invoke-WebRequest -UseBasicParsing -Uri '$RepoRawBase/komutlar.txt' -OutFile `$dest
Write-Output "Guncellendi: `$dest (`$((Get-Item `$dest).Length) byte)"
`$guide = '$(if ($LabGuideUrl) { $LabGuideUrl } else { "https://aes-workshop.onrender.com" })'
`$lnk = 'C:\Users\$WorkshopUser\Desktop\AES Lab Rehberi.url'
[IO.File]::WriteAllText(`$lnk, "[InternetShortcut]``r``nURL=`$guide``r``n")
Write-Output "Kisayol: `$lnk -> `$guide"
"@

Write-Host "==> Masaustu dosyalari guncelleniyor: $($instances.Count) makine" -ForegroundColor Cyan
$sent = Send-SsmScript -InstanceIds @($instances | ForEach-Object { $_.InstanceId }) -Script $script -Comment "update desktop" -ExecutionTimeoutSeconds 300
Wait-SsmCommands -Sent $sent -Instances $instances -TimeoutMinutes 10 | Out-Null
