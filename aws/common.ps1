# ---------------------------------------------------------------------------
# Ortak yardimci fonksiyonlar. Diger script'ler bu dosyayi yukler.
# ---------------------------------------------------------------------------
$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

$ConfigPath = Join-Path $PSScriptRoot "config.ps1"
if (-not (Test-Path $ConfigPath)) {
    throw "config.ps1 bulunamadi. aws\config.example.ps1 dosyasini aws\config.ps1 olarak kopyalayip doldurun."
}
. $ConfigPath

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    throw "AWS CLI bulunamadi. AWS CLI v2'yi kurup 'aws configure' ile yapilandirin."
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Assert-Configured {
    # Doldurulmamis ayar kalmasin
    param([string[]]$Names)
    foreach ($n in $Names) {
        $v = Get-Variable -Name $n -ValueOnly -ErrorAction SilentlyContinue
        if (-not $v -or "$v" -like "*xxxxxxxx*" -or "$v" -like "*<kullanici>*") {
            throw "config.ps1 icinde `$$n doldurulmamis."
        }
    }
}

function Invoke-Aws {
    # AWS CLI'yi calistirir, JSON ciktisini nesneye cevirir, hata olursa durur
    param([Parameter(Mandatory = $true)][string[]]$ArgList)
    $full = @($ArgList) + @("--region", $Region, "--output", "json")
    if ($AwsProfile) { $full += @("--profile", $AwsProfile) }

    $errFile = [IO.Path]::GetTempFileName()
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"   # PS 5.1'de stderr'in script'i kesmemesi icin
    try {
        $out  = & aws @full 2> $errFile
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }
    $err = Get-Content $errFile -Raw -ErrorAction SilentlyContinue
    Remove-Item $errFile -ErrorAction SilentlyContinue

    if ($code -ne 0) { throw "aws $($ArgList[0..1] -join ' ') basarisiz (kod $code): $err" }
    $text = ($out | Out-String).Trim()
    if ($text) { return ($text | ConvertFrom-Json) }
}

function New-JsonArgFile {
    # PowerShell 5.1'in JSON tirnak sorunlarindan kacinmak icin JSON'u dosyaya yazar
    param([Parameter(Mandatory = $true)]$Object)
    $path = Join-Path ([IO.Path]::GetTempPath()) ("koi-ws-" + [guid]::NewGuid().ToString("N") + ".json")
    $json = ConvertTo-Json -InputObject $Object -Depth 10
    [IO.File]::WriteAllText($path, $json, $Utf8NoBom)
    return "file://$path"
}

function Get-WorkshopInstances {
    # Workshop tag'li katilimci instance'larini listeler
    param([string[]]$Only)
    $filters = @(
        "Name=tag:Workshop,Values=$WorkshopTag",
        "Name=tag:Role,Values=participant",
        "Name=instance-state-name,Values=pending,running,stopping,stopped"
    )
    $res = Invoke-Aws (@("ec2", "describe-instances", "--filters") + $filters)
    $list = foreach ($r in $res.Reservations) {
        foreach ($i in $r.Instances) {
            [pscustomobject]@{
                Name       = ($i.Tags | Where-Object { $_.Key -eq "Name" }).Value
                InstanceId = $i.InstanceId
                State      = $i.State.Name
                PublicIp   = $i.PublicIpAddress
                PrivateIp  = $i.PrivateIpAddress
                Spare      = ($i.Tags | Where-Object { $_.Key -eq "Spare" }).Value
            }
        }
    }
    $list = @($list | Sort-Object Name)
    if ($Only) { $list = @($list | Where-Object { $Only -contains $_.Name }) }
    return $list
}

function Wait-SsmOnline {
    # Instance'lar SSM'e kaydolana kadar bekler
    param([Parameter(Mandatory = $true)]$Instances, [int]$TimeoutMinutes = 20)
    $ids = @($Instances | ForEach-Object { $_.InstanceId })
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ($true) {
        $info = Invoke-Aws @("ssm", "describe-instance-information", "--filters", "Key=InstanceIds,Values=$($ids -join ',')")
        $online  = @($info.InstanceInformationList | Where-Object { $_.PingStatus -eq "Online" } | ForEach-Object { $_.InstanceId })
        $missing = @($ids | Where-Object { $online -notcontains $_ })
        if ($missing.Count -eq 0) {
            Write-Host "Tum instance'lar SSM'de Online." -ForegroundColor Green
            return
        }
        if ((Get-Date) -gt $deadline) {
            $names = @($Instances | Where-Object { $missing -contains $_.InstanceId } | ForEach-Object { $_.Name })
            throw "SSM'de Online olmayan instance'lar: $($names -join ', '). IAM rolunu ve internet erisimini kontrol edin."
        }
        Write-Host "  SSM bekleniyor: $($missing.Count) instance henuz Online degil..."
        Start-Sleep -Seconds 20
    }
}

function Send-SsmScript {
    # PowerShell script'ini SSM Run Command ile instance'lara gonderir
    param(
        [Parameter(Mandatory = $true)][string[]]$InstanceIds,
        [Parameter(Mandatory = $true)][string]$Script,
        [string]$Comment = "aes-workshop",
        [int]$ExecutionTimeoutSeconds = 3600
    )
    $params = @{
        commands         = @($Script -split "`r?`n")
        executionTimeout = @("$ExecutionTimeoutSeconds")
    }
    $paramFile = New-JsonArgFile $params
    $sent = @()
    for ($i = 0; $i -lt $InstanceIds.Count; $i += 50) {
        $chunk = @($InstanceIds[$i..([Math]::Min($i + 49, $InstanceIds.Count - 1))])
        $res = Invoke-Aws (@("ssm", "send-command",
                "--document-name", "AWS-RunPowerShellScript",
                "--comment", $Comment,
                "--parameters", $paramFile,
                "--instance-ids") + $chunk)
        $sent += [pscustomobject]@{ CommandId = $res.Command.CommandId; InstanceIds = $chunk }
    }
    return $sent
}

function Wait-SsmCommands {
    # Gonderilen komutlarin bitmesini bekler ve her instance'in sonucunu yazar
    param(
        [Parameter(Mandatory = $true)]$Sent,
        [Parameter(Mandatory = $true)]$Instances,
        [int]$TimeoutMinutes = 60
    )
    $nameOf = @{}
    foreach ($x in $Instances) { $nameOf[$x.InstanceId] = $x.Name }

    $pending = New-Object System.Collections.Generic.List[object]
    foreach ($s in $Sent) {
        foreach ($id in $s.InstanceIds) {
            $pending.Add([pscustomobject]@{ CommandId = $s.CommandId; InstanceId = $id })
        }
    }

    $inFlight = @("Pending", "InProgress", "Delayed", "Cancelling")
    $results  = @()
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)

    while ($pending.Count -gt 0) {
        foreach ($p in $pending.ToArray()) {
            try {
                $inv = Invoke-Aws @("ssm", "get-command-invocation", "--command-id", $p.CommandId, "--instance-id", $p.InstanceId)
            } catch {
                if ($_.Exception.Message -like "*InvocationDoesNotExist*") { continue }
                throw
            }
            if ($inFlight -contains $inv.Status) { continue }

            $r = [pscustomobject]@{
                Name       = $nameOf[$p.InstanceId]
                InstanceId = $p.InstanceId
                Status     = $inv.Status
                Output     = "$($inv.StandardOutputContent)".Trim()
                Error      = "$($inv.StandardErrorContent)".Trim()
            }
            $results += $r
            [void]$pending.Remove($p)

            $color = if ($r.Status -eq "Success") { "Green" } else { "Red" }
            Write-Host ("[{0}] {1}" -f $r.Status, $r.Name) -ForegroundColor $color
            if ($r.Output) { $r.Output -split "`r?`n" | ForEach-Object { Write-Host "    $_" } }
            if ($r.Error)  { $r.Error  -split "`r?`n" | Select-Object -First 5 | ForEach-Object { Write-Host "    ! $_" -ForegroundColor Yellow } }
        }
        if ($pending.Count -eq 0) { break }
        if ((Get-Date) -gt $deadline) {
            Write-Host "Zaman asimi: $($pending.Count) instance'tan sonuc gelmedi." -ForegroundColor Red
            break
        }
        Write-Host "  ... $($pending.Count) instance bekleniyor"
        Start-Sleep -Seconds 15
    }

    $ok = @($results | Where-Object { $_.Status -eq "Success" }).Count
    Write-Host ""
    Write-Host "Sonuc: $ok / $($results.Count + $pending.Count) basarili." -ForegroundColor Cyan
    return $results
}
