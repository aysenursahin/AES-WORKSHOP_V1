# ---------------------------------------------------------------------------
# 05 - Tum makinelerin workshop'a hazir olup olmadigini kontrol eder
#
# Her makine icin: hostname, Koi servisi, npm ve pip'in Koi gateway'ine
# yonlenmesi, masaustunde komutlar.txt ve buttoncontent'in KURULU OLMAMASI.
# Workshop sabahi da calistirin.
# ---------------------------------------------------------------------------
param([string[]]$Only)
. "$PSScriptRoot\common.ps1"

$instances = @(Get-WorkshopInstances -Only $Only | Where-Object { $_.State -eq "running" })
if ($instances.Count -eq 0) { throw "Calisan workshop instance'i bulunamadi." }

Wait-SsmOnline $instances

$script = @"
`$u = '$WorkshopUser'
`$svc = Get-Service | Where-Object { `$_.DisplayName -like '$KoiServicePattern' }
`$koi = if (`$svc) { "`$(`$svc.Status)" } else { 'YOK' }

`$npmOk = `$false
foreach (`$f in @("C:\Users\`$u\AppData\Roaming\npm\etc\npmrc", "C:\Users\`$u\.npmrc")) {
    if ((Test-Path `$f) -and ((Get-Content `$f -Raw) -like '*gateway.koi.security*')) { `$npmOk = `$true }
}
`$pipIni = Join-Path `$env:ProgramData 'pip\pip.ini'
`$pipOk = (Test-Path `$pipIni) -and ((Get-Content `$pipIni -Raw) -like '*gateway.koi.security*')
`$komutlar = Test-Path "C:\Users\`$u\Desktop\komutlar.txt"
`$blocked = Test-Path 'C:\Projeler\bogazici-web\node_modules\buttoncontent'

Write-Output ("Koi={0} | npm->Koi={1} | pip->Koi={2} | komutlar.txt={3} | buttoncontent kurulu={4}" -f `$koi, `$npmOk, `$pipOk, `$komutlar, `$blocked)
`$ok = (`$koi -eq 'Running') -and `$npmOk -and `$pipOk -and `$komutlar -and (-not `$blocked) -and (`$env:COMPUTERNAME -like '$NamePrefix*')
if (-not `$ok) { Write-Output "Hostname=`$env:COMPUTERNAME"; exit 1 }
"@

Write-Host "==> Kontrol ediliyor: $($instances.Count) makine" -ForegroundColor Cyan
$sent = Send-SsmScript -InstanceIds @($instances | ForEach-Object { $_.InstanceId }) -Script $script -Comment "workshop check" -ExecutionTimeoutSeconds 300
$results = @(Wait-SsmCommands -Sent $sent -Instances $instances -TimeoutMinutes 10)

$failed = @($results | Where-Object { $_.Status -ne "Success" })
if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "Sorunlu makineler: $(($failed | ForEach-Object { $_.Name }) -join ', ')" -ForegroundColor Red
} else {
    Write-Host "Tum makineler hazir." -ForegroundColor Green
}
