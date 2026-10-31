# ---------------------------------------------------------------------------
# 01 - Base makineden AMI alir
#
# Base makinede aes-workshop-setup.ps1 calismis ve elle yapilacaklar
# tamamlanmis olmali. Koi base makinede KURULU OLMAMALI.
# Not: AMI alinirken base makine yeniden baslatilir.
# ---------------------------------------------------------------------------
. "$PSScriptRoot\common.ps1"
Assert-Configured @("BaseInstanceId", "AmiName")

Write-Host "Base makine: $BaseInstanceId" -ForegroundColor Cyan
Write-Host "  - aes-workshop-setup.ps1 calisti ve tum kontroller [OK] mi?"
Write-Host "  - Claude Desktop, Cursor ve Chrome extension'lari kuruldu mu?"
Write-Host "  - Koi bu makinede KURULU DEGIL mi?"
$answer = Read-Host "Hepsi tamamsa 'evet' yazin"
if ($answer -ne "evet") { Write-Host "Iptal edildi."; exit 1 }

$name = "{0}-{1}" -f $AmiName, (Get-Date -Format "yyyyMMdd-HHmm")
$tags = @(
    @{ ResourceType = "image";    Tags = @(@{ Key = "Name"; Value = $name }, @{ Key = "Workshop"; Value = $WorkshopTag }) },
    @{ ResourceType = "snapshot"; Tags = @(@{ Key = "Name"; Value = $name }, @{ Key = "Workshop"; Value = $WorkshopTag }) }
)
$tagFile = New-JsonArgFile $tags

Write-Host "==> AMI olusturuluyor: $name (base makine yeniden baslatilacak)" -ForegroundColor Cyan
$res = Invoke-Aws @("ec2", "create-image",
    "--instance-id", $BaseInstanceId,
    "--name", $name,
    "--description", "Koi workshop base image",
    "--tag-specifications", $tagFile)
$amiId = $res.ImageId
Write-Host "    AMI: $amiId"

$deadline = (Get-Date).AddMinutes(90)
while ($true) {
    $img   = (Invoke-Aws @("ec2", "describe-images", "--image-ids", $amiId)).Images[0]
    $state = $img.State
    if ($state -eq "available") { break }
    if ($state -eq "failed")    { throw "AMI olusturulamadi: $($img.StateReason.Message)" }
    if ((Get-Date) -gt $deadline) { throw "AMI 90 dakikada hazir olmadi. AWS konsolundan kontrol edin." }
    Write-Host "  ... AMI durumu: $state"
    Start-Sleep -Seconds 30
}

Write-Host ""
Write-Host "AMI hazir: $amiId ($name)" -ForegroundColor Green
Write-Host "Siradaki adim: 02-launch-instances.ps1"
