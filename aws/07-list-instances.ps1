# ---------------------------------------------------------------------------
# 07 - Katilimci makinelerini listeler ve participants.csv olusturur
#
# CSV'de her katilimcinin RDP adresi ve kullanici adi bulunur. Sifre
# sutununu doldurup katilimcilara dagitabilirsiniz.
# participants.csv .gitignore'da; GitHub'a yuklenmez.
# Not: Durdurulup yeniden baslatilan makinelerin public IP'si degisir;
# makineleri actiktan sonra bu script'i tekrar calistirin.
# ---------------------------------------------------------------------------
. "$PSScriptRoot\common.ps1"

$instances = @(Get-WorkshopInstances)
if ($instances.Count -eq 0) { throw "Workshop instance'i bulunamadi." }

$rows = foreach ($i in $instances) {
    [pscustomobject]@{
        Makine     = $i.Name
        RdpAdresi  = $i.PublicIp
        Kullanici  = $WorkshopUser
        Sifre      = ""
        Durum      = $i.State
        Yedek      = $(if ($i.Spare -eq "true") { "evet" } else { "" })
        InstanceId = $i.InstanceId
    }
}

$rows | Format-Table -AutoSize
$csv = Join-Path $PSScriptRoot "participants.csv"
$rows | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
Write-Host "Kaydedildi: $csv" -ForegroundColor Green
