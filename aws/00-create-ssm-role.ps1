# ---------------------------------------------------------------------------
# 00 - SSM icin IAM rolu ve instance profile olusturur (bir kere calistirilir)
#
# Katilimci makineleri bu rolle acilir; boylece Koi kurulumu, hostname
# degisikligi ve kontroller RDP yapmadan, SSM Run Command ile yapilabilir.
# ---------------------------------------------------------------------------
. "$PSScriptRoot\common.ps1"

function Invoke-AwsIgnore {
    param([string[]]$ArgList, [string[]]$IgnoreErrors)
    try { Invoke-Aws $ArgList | Out-Null; return $true }
    catch {
        foreach ($e in $IgnoreErrors) {
            if ($_.Exception.Message -like "*$e*") { return $false }
        }
        throw
    }
}

$trust = @{
    Version   = "2012-10-17"
    Statement = @(@{
        Effect    = "Allow"
        Principal = @{ Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
    })
}
$trustFile = New-JsonArgFile $trust

Write-Host "==> IAM rolu: $RoleName" -ForegroundColor Cyan
if (Invoke-AwsIgnore @("iam", "create-role", "--role-name", $RoleName, "--assume-role-policy-document", $trustFile) @("EntityAlreadyExists")) {
    Write-Host "    olusturuldu"
} else { Write-Host "    zaten var" }

Write-Host "==> AmazonSSMManagedInstanceCore policy'si baglaniyor" -ForegroundColor Cyan
Invoke-Aws @("iam", "attach-role-policy", "--role-name", $RoleName, "--policy-arn", "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore") | Out-Null
Write-Host "    tamam"

Write-Host "==> Instance profile: $InstanceProfile" -ForegroundColor Cyan
if (Invoke-AwsIgnore @("iam", "create-instance-profile", "--instance-profile-name", $InstanceProfile) @("EntityAlreadyExists")) {
    Write-Host "    olusturuldu"
} else { Write-Host "    zaten var" }

Write-Host "==> Rol instance profile'a ekleniyor" -ForegroundColor Cyan
if (Invoke-AwsIgnore @("iam", "add-role-to-instance-profile", "--instance-profile-name", $InstanceProfile, "--role-name", $RoleName) @("LimitExceeded")) {
    Write-Host "    eklendi"
} else { Write-Host "    zaten ekli" }

Write-Host ""
Write-Host "Hazir. IAM degisikliklerinin yayilmasi icin 1-2 dakika bekleyip devam edin." -ForegroundColor Green
