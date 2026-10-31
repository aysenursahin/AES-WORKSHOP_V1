# ---------------------------------------------------------------------------
# 99 - Workshop sonrasi temizlik
#
# Workshop tag'li tum katilimci makinelerini SILER (terminate). Geri alinamaz.
#   .\99-cleanup.ps1
# AMI'yi ve snapshot'larini da silmek icin:
#   .\99-cleanup.ps1 -DeleteAmi
# Base makineye dokunmaz.
# ---------------------------------------------------------------------------
param([switch]$DeleteAmi)
. "$PSScriptRoot\common.ps1"

$instances = @(Get-WorkshopInstances)
if ($instances.Count -gt 0) {
    $instances | Format-Table Name, InstanceId, State -AutoSize
    Write-Host "Bu $($instances.Count) makine kalici olarak silinecek." -ForegroundColor Red
    $answer = Read-Host "Onaylamak icin SIL yazin"
    if ($answer -ne "SIL") { Write-Host "Iptal edildi."; exit 1 }

    $ids = @($instances | ForEach-Object { $_.InstanceId })
    Invoke-Aws (@("ec2", "terminate-instances", "--instance-ids") + $ids) | Out-Null
    Write-Host "==> Makineler siliniyor..." -ForegroundColor Cyan
    Invoke-Aws (@("ec2", "wait", "instance-terminated", "--instance-ids") + $ids) | Out-Null
    Write-Host "Makineler silindi." -ForegroundColor Green
} else {
    Write-Host "Silinecek katilimci makinesi yok."
}

if ($DeleteAmi) {
    $imgs = @((Invoke-Aws @("ec2", "describe-images", "--owners", "self",
        "--filters", "Name=tag:Workshop,Values=$WorkshopTag")).Images)
    if ($imgs.Count -eq 0) { Write-Host "Silinecek AMI yok."; exit 0 }

    $imgs | Format-Table ImageId, Name, CreationDate -AutoSize
    $answer = Read-Host "Bu AMI'ler ve snapshot'lari silinecek. Onaylamak icin SIL yazin"
    if ($answer -ne "SIL") { Write-Host "AMI silme iptal edildi."; exit 1 }

    foreach ($img in $imgs) {
        Invoke-Aws @("ec2", "deregister-image", "--image-id", $img.ImageId) | Out-Null
        foreach ($bdm in $img.BlockDeviceMappings) {
            if ($bdm.Ebs -and $bdm.Ebs.SnapshotId) {
                Invoke-Aws @("ec2", "delete-snapshot", "--snapshot-id", $bdm.Ebs.SnapshotId) | Out-Null
            }
        }
        Write-Host "  Silindi: $($img.ImageId) ($($img.Name))"
    }
}
