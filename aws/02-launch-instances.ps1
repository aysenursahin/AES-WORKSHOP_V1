# ---------------------------------------------------------------------------
# 02 - AMI'den katilimci makinelerini acar (WS-USER01, WS-USER02, ...)
#
# Katilimci sayisi + yedek kadar instance acar. Ayni isimde calisan bir
# instance varsa onu atlar; yani script'i tekrar calistirmak guvenlidir.
# ---------------------------------------------------------------------------
. "$PSScriptRoot\common.ps1"
Assert-Configured @("SubnetId", "SecurityGroupId", "InstanceType", "InstanceProfile")

# AMI: config'te yoksa en yeni workshop AMI'si
if ($AmiId) {
    $latest = (Invoke-Aws @("ec2", "describe-images", "--image-ids", $AmiId)).Images | Select-Object -First 1
} else {
    $imgs = Invoke-Aws @("ec2", "describe-images", "--owners", "self",
        "--filters", "Name=tag:Workshop,Values=$WorkshopTag", "Name=state,Values=available")
    $latest = $imgs.Images | Sort-Object CreationDate -Descending | Select-Object -First 1
}
if (-not $latest) { throw "Workshop AMI'si bulunamadi. Once 01-create-ami.ps1 calistirin." }
$ami = $latest.ImageId
Write-Host "AMI: $ami ($($latest.Name))" -ForegroundColor Cyan

# Disk boyutu: VolumeSizeGiB AMI'deki diskten buyukse kok disk buyutulerek acilir
$blockFile = $null
if ($VolumeSizeGiB) {
    $root    = $latest.RootDeviceName
    $amiSize = ($latest.BlockDeviceMappings | Where-Object { $_.DeviceName -eq $root }).Ebs.VolumeSize
    if ([int]$VolumeSizeGiB -gt [int]$amiSize) {
        $blockFile = New-JsonArgFile @(@{ DeviceName = $root; Ebs = @{ VolumeSize = [int]$VolumeSizeGiB; VolumeType = "gp3"; DeleteOnTermination = $true } })
        Write-Host "Disk: $amiSize GiB -> $VolumeSizeGiB GiB" -ForegroundColor Cyan
    }
}

$existing = @((Get-WorkshopInstances) | ForEach-Object { $_.Name })
$total    = $ParticipantCount + $SpareCount
$newIds   = @()

for ($i = 1; $i -le $total; $i++) {
    $name  = "{0}{1:D2}" -f $NamePrefix, $i
    $spare = if ($i -gt $ParticipantCount) { "true" } else { "false" }
    if ($existing -contains $name) {
        Write-Host "  $name zaten var, atlandi"
        continue
    }

    $tags = @(
        @{ ResourceType = "instance"; Tags = @(
            @{ Key = "Name";     Value = $name },
            @{ Key = "Workshop"; Value = $WorkshopTag },
            @{ Key = "Role";     Value = "participant" },
            @{ Key = "Spare";    Value = $spare }) },
        @{ ResourceType = "volume"; Tags = @(
            @{ Key = "Name";     Value = $name },
            @{ Key = "Workshop"; Value = $WorkshopTag }) }
    )
    $argList = @("ec2", "run-instances",
        "--image-id", $ami,
        "--instance-type", $InstanceType,
        "--count", "1",
        "--subnet-id", $SubnetId,
        "--security-group-ids", $SecurityGroupId,
        "--associate-public-ip-address",
        "--iam-instance-profile", "Name=$InstanceProfile",
        "--metadata-options", "HttpTokens=required,HttpEndpoint=enabled",
        "--tag-specifications", (New-JsonArgFile $tags))
    if ($KeyName)   { $argList += @("--key-name", $KeyName) }
    if ($blockFile) { $argList += @("--block-device-mappings", $blockFile) }

    # Yeni olusturulan IAM profile'in yayilmasi birkac saniye surebilir
    for ($try = 1; $try -le 4; $try++) {
        try { $res = Invoke-Aws $argList; break }
        catch {
            if ($try -lt 4 -and $_.Exception.Message -like "*Invalid IAM Instance Profile*") {
                Write-Host "  IAM profile henuz hazir degil, 15 sn sonra tekrar deneniyor..."
                Start-Sleep -Seconds 15
            } else { throw }
        }
    }
    $id = $res.Instances[0].InstanceId
    $newIds += $id
    Write-Host ("  {0} acildi: {1}{2}" -f $name, $id, $(if ($spare -eq "true") { " (yedek)" } else { "" })) -ForegroundColor Green
}

if ($newIds.Count -gt 0) {
    Write-Host "==> Instance'larin calismasi bekleniyor..." -ForegroundColor Cyan
    Invoke-Aws (@("ec2", "wait", "instance-running", "--instance-ids") + $newIds) | Out-Null
}

Get-WorkshopInstances | Format-Table Name, InstanceId, State, PublicIp, Spare -AutoSize
Write-Host "Windows'un acilip SSM'e kaydolmasi 5-10 dakika surebilir."
Write-Host "Siradaki adim: 03-rename-hosts.ps1"
