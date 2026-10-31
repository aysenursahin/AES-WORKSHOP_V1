# ---------------------------------------------------------------------------
# 08 - Katilimci makinelerini baslatir veya durdurur
#
# Hazirlik ile workshop gunu arasinda makineleri durdurup maliyeti dusurun.
#   .\08-power.ps1 -Action Stop
#   .\08-power.ps1 -Action Start
# Baslattiktan sonra public IP'ler degisir: 07-list-instances.ps1 calistirin.
# ---------------------------------------------------------------------------
param(
    [Parameter(Mandatory = $true)][ValidateSet("Start", "Stop")][string]$Action,
    [string[]]$Only
)
. "$PSScriptRoot\common.ps1"

$instances = @(Get-WorkshopInstances -Only $Only)
if ($instances.Count -eq 0) { throw "Workshop instance'i bulunamadi." }
$ids = @($instances | ForEach-Object { $_.InstanceId })

if ($Action -eq "Stop") {
    Write-Host "==> $($ids.Count) makine durduruluyor..." -ForegroundColor Cyan
    Invoke-Aws (@("ec2", "stop-instances", "--instance-ids") + $ids) | Out-Null
    Invoke-Aws (@("ec2", "wait", "instance-stopped", "--instance-ids") + $ids) | Out-Null
} else {
    Write-Host "==> $($ids.Count) makine baslatiliyor..." -ForegroundColor Cyan
    Invoke-Aws (@("ec2", "start-instances", "--instance-ids") + $ids) | Out-Null
    Invoke-Aws (@("ec2", "wait", "instance-running", "--instance-ids") + $ids) | Out-Null
    Write-Host "Yeni IP'ler icin 07-list-instances.ps1 calistirin."
}

Get-WorkshopInstances -Only $Only | Format-Table Name, State, PublicIp -AutoSize
