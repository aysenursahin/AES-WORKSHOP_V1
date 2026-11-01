<#
.SYNOPSIS
    Koi Agentic Endpoint Security Workshop - Lab makinesi kurulum script'i

.DESCRIPTION
    Workshop VM'ini (AWS EC2 Windows) Koi envanterini dolduracak uygulamalar,
    eklentiler, paketler, AI ajanlari ve MCP yapilandirmalariyla hazirlar.

    NASIL CALISTIRILIR:
      Repo README'sindeki tek satirlik komutu kullanin. Script, ayni klasordeki
      komutlar.txt dosyasini masaustune kopyalar; bu yuzden repoyu zip olarak
      indirip klasorden calistirin, script'i tek basina indirmeyin.

      Elle calistirmak icin (repo klasorunde, yonetici PowerShell):
           Set-ExecutionPolicy Bypass -Scope Process -Force
           .\aes-workshop-setup.ps1 `
               -KoiConsoleUrl  "https://<konsol-adresi>" `
               -NpmGatewayUrl  "https://koi-npmjs-<customer_subdomain>.gateway.koi.security" `
               -PypiGatewayUrl "https://koi-pypi-<customer_subdomain>.gateway.koi.security"

    Kullaniciya ozel dosyalar (VS Code eklentileri, MCP config, skill) script'i
    calistiran kullanicinin profiline yazilir. Bu yuzden katilimcilarin
    kullanacagi hesapla calistirin, SYSTEM / EC2 user data ile degil.

    KOI BU SCRIPT ILE KURULMAZ. Koi her instance'a ayri kurulmalidir
    (klonlanan makineler ayni cihaz kimligini tasimasin diye).

.NOTES
    Log: C:\WorkshopSetup\setup.log
#>

[CmdletBinding()]
param(
    # Koi konsol adresi (masaustu kisayolu icin)
    [string]$KoiConsoleUrl = "https://KOI-KONSOL-ADRESINIZ",

    # Provada secilecek "az bilinen yayinci" AI eklentisinin ID'si (or. publisher.extension).
    # Bos birakilirsa atlanir.
    [string]$UnknownPublisherExtensionId = "",

    # Windows Update otomatik kurulumunu kapat (workshop sirasinda yeniden baslatma olmasin)
    [bool]$DisableWindowsUpdate = $true,

    # Koi npm gateway adresi (deployment portal'da yazar).
    # Or: https://koi-npmjs-<customer_subdomain>.gateway.koi.security
    # Bos birakilirsa npm yonlendirmesi atlanir.
    [string]$NpmGatewayUrl = "",

    # Koi PyPI gateway adresi, /simple OLMADAN (deployment portal'da yazar).
    # Or: https://koi-pypi-<customer_subdomain>.gateway.koi.security
    # Bos birakilirsa pip yonlendirmesi atlanir.
    [string]$PypiGatewayUrl = "",

    # Koi Root CA dosyasinin yolu (.pem). Deployment portal > Network Integration >
    # Establish Network Trust > Download CA. Chrome Web Store / VS Code Marketplace
    # trafigi Koi proxy'sinden gecerken makinenin bu baglantiya guvenmesi icin gerekir.
    # Bos birakilirsa repodaki certs\ klasorundeki .pem/.cer/.crt dosyasi kullanilir;
    # orada da yoksa bu adim atlanir.
    [string]$KoiRootCaFile = "",

    # Koi PAC dosyasi URL'i (deployment portal > Network Integration).
    # Koi konsolunda "Deploy with KOI" seciliyse PAC'i Koi'nin script paketi kurar;
    # o durumda bos birakin.
    [string]$PacUrl = ""
)

# ---------------------------------------------------------------------------
# Hazirlik
# ---------------------------------------------------------------------------
$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Bu script yonetici olarak calistirilmalidir."
    exit 1
}

$SetupDir    = "C:\WorkshopSetup"
$ProjectRoot = "C:\Projeler"
$WebProject  = Join-Path $ProjectRoot "bogazici-web"
$ApiProject  = Join-Path $ProjectRoot "bogazici-api"
$Desktop     = [Environment]::GetFolderPath("Desktop")
$Utf8NoBom   = New-Object System.Text.UTF8Encoding($false)

New-Item -ItemType Directory -Force -Path $SetupDir | Out-Null
Start-Transcript -Path (Join-Path $SetupDir "setup.log") -Append | Out-Null

$Results = New-Object System.Collections.Generic.List[object]

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action)
    Write-Host "`n==> $Name" -ForegroundColor Cyan
    try {
        & $Action
        $Results.Add([pscustomobject]@{ Adim = $Name; Durum = "OK"; Not = "" })
        Write-Host "    OK" -ForegroundColor Green
    } catch {
        $Results.Add([pscustomobject]@{ Adim = $Name; Durum = "HATA"; Not = $_.Exception.Message })
        Write-Host "    HATA: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
}

function Write-TextFile {
    # BOM'suz UTF-8 yazar (JSON dosyalari BOM ile bozulabilir)
    param([string]$Path, [string]$Content)
    $dir = Split-Path $Path -Parent
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Invoke-Native {
    # Harici komutlarin cikis kodunu kontrol eder
    # 3010 = basarili, yeniden baslatma gerekiyor (choco/MSI)
    param([string]$File, [string[]]$Arguments, [int[]]$OkCodes = @(0, 3010))
    & $File @Arguments
    if ($OkCodes -notcontains $LASTEXITCODE) { throw "$File $($Arguments -join ' ') cikis kodu: $LASTEXITCODE" }
}

# ---------------------------------------------------------------------------
# A. Isletim sistemi ayarlari
# ---------------------------------------------------------------------------
if ($DisableWindowsUpdate) {
    Invoke-Step "Windows Update otomatik kurulumunu kapat" {
        $au = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        New-Item -Path $au -Force | Out-Null
        Set-ItemProperty -Path $au -Name "NoAutoUpdate" -Value 1 -Type DWord
    }
}

# Katilimcilarin yeni PowerShell pencerelerinde npm/codex gibi komutlari
# calistirabilmesi icin (aksi halde "running scripts is disabled" hatasi)
Invoke-Step "PowerShell execution policy: RemoteSigned" {
    Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
}

# ---------------------------------------------------------------------------
# B. Gelistirici araclari (Chocolatey)
# ---------------------------------------------------------------------------
Invoke-Step "Chocolatey kurulumu" {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString("https://community.chocolatey.org/install.ps1"))
    }
    Update-SessionPath
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) { throw "choco bulunamadi" }
}

$chocoPackages = @("googlechrome", "vscode", "nodejs-lts", "python", "git")
foreach ($pkg in $chocoPackages) {
    Invoke-Step "Kurulum: $pkg" {
        $chocoArgs = @("install", $pkg, "-y", "--no-progress")
        # Chrome: Google MSI'i her surumde degistirdigi icin choco paketindeki
        # checksum sik sik eskiyor. Dosya dogrudan dl.google.com'dan iniyor.
        if ($pkg -eq "googlechrome") { $chocoArgs += "--ignore-checksums" }
        Invoke-Native "choco" $chocoArgs
        Update-SessionPath
    }
}

# Komutlarin yollarini netlestir
$CodeCmd = "C:\Program Files\Microsoft VS Code\bin\code.cmd"
Update-SessionPath

# ---------------------------------------------------------------------------
# C1. VS Code eklentileri
# ---------------------------------------------------------------------------
$vscodeExtensions = @(
    "ms-python.python",
    "dbaeumer.vscode-eslint",
    "esbenp.prettier-vscode",
    "eamodio.gitlens",
    # GitHub Copilot Chat guncel VS Code ile yerlesik geliyor; ayrica kurulamiyor.
    "Continue.continue"
)
if ($UnknownPublisherExtensionId) { $vscodeExtensions += $UnknownPublisherExtensionId }

foreach ($ext in $vscodeExtensions) {
    Invoke-Step "VS Code eklentisi: $ext" {
        if (-not (Test-Path $CodeCmd)) { throw "code.cmd bulunamadi: $CodeCmd" }
        Invoke-Native $CodeCmd @("--install-extension", $ext, "--force")
    }
}

# ---------------------------------------------------------------------------
# C2. AI CLI ajanlari (npm global)
# ---------------------------------------------------------------------------
$npmGlobal = @("@anthropic-ai/claude-code", "@openai/codex", "@modelcontextprotocol/server-filesystem")
foreach ($p in $npmGlobal) {
    Invoke-Step "npm global: $p" {
        # Yeni npm surumleri paketlerin kurulum script'lerini varsayilan olarak
        # calistirmiyor; Claude Code'un postinstall adimina izin ver.
        Invoke-Native "npm.cmd" @("install", "-g", $p, "--allow-scripts=$p")
    }
}

# ---------------------------------------------------------------------------
# C3. Ornek projeler (npm ve pip paketleri)
# ---------------------------------------------------------------------------
Invoke-Step "Ornek proje: bogazici-web (npm)" {
    New-Item -ItemType Directory -Force -Path $WebProject | Out-Null
    $packageJson = @'
{
  "name": "bogazici-web",
  "version": "1.0.0",
  "description": "Bogazici Teknoloji - workshop ornek web projesi",
  "main": "index.js",
  "private": true
}
'@
    Write-TextFile (Join-Path $WebProject "package.json") $packageJson
    Write-TextFile (Join-Path $WebProject "index.js") "console.log('Bogazici web projesi');`n"
    Push-Location $WebProject
    try { Invoke-Native "npm.cmd" @("install", "express", "axios", "lodash", "dotenv") }
    finally { Pop-Location }
}

Invoke-Step "Ornek proje: bogazici-api (pip, venv)" {
    New-Item -ItemType Directory -Force -Path $ApiProject | Out-Null
    Write-TextFile (Join-Path $ApiProject "requirements.txt") "requests`nflask`npython-dotenv`n"
    Write-TextFile (Join-Path $ApiProject "app.py") "print('Bogazici API projesi')`n"
    Push-Location $ApiProject
    try {
        Invoke-Native "python" @("-m", "venv", ".venv")
        Invoke-Native (Join-Path $ApiProject ".venv\Scripts\python.exe") @("-m", "pip", "install", "-r", "requirements.txt")
    } finally { Pop-Location }
}

# Bolum 8 (egitmen demosu) icin SAHTE .env dosyasi - gercek sir icermez
Invoke-Step "Sahte .env dosyasi (runtime demosu icin)" {
    $envContent = @'
# WORKSHOP ORNEGIDIR - GERCEK DEGER DEGILDIR
DEMO_DB_PASSWORD=ornek-sifre-gercek-degil
DEMO_API_KEY=ornek-anahtar-gercek-degil
'@
    Write-TextFile (Join-Path $WebProject ".env") $envContent
}

# ---------------------------------------------------------------------------
# C4. MCP yapilandirmalari ve skill
# ---------------------------------------------------------------------------
$mcpJson = @'
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "C:\\Projeler"]
    }
  }
}
'@

Invoke-Step "Claude Desktop MCP config" {
    Write-TextFile (Join-Path $env:APPDATA "Claude\claude_desktop_config.json") $mcpJson
}

Invoke-Step "Cursor proje MCP config (.cursor\mcp.json)" {
    Write-TextFile (Join-Path $WebProject ".cursor\mcp.json") $mcpJson
}

Invoke-Step "Claude Code proje MCP config (.mcp.json)" {
    Write-TextFile (Join-Path $WebProject ".mcp.json") $mcpJson
}

Invoke-Step "Claude Code skill (zararsiz ornek)" {
    $skill = @'
---
name: proje-ozeti
description: Projedeki dosyalari listeleyip kisa bir ozet cikarir. Workshop ornegidir.
---

# Proje Ozeti

Kullanici proje ozeti istediginde, proje klasorundeki dosyalari listele ve
her dosyanin ne ise yaradigini tek cumleyle ozetle.
'@
    Write-TextFile (Join-Path $env:USERPROFILE ".claude\skills\proje-ozeti\SKILL.md") $skill
}

# ---------------------------------------------------------------------------
# C5. Koi gateway yonlendirmesi (npm / pip)
# Ornek projeler kurulduktan SONRA yapilir; boylece hazirlik kurulumlari
# guardrail'lere takilmaz. Bundan sonraki her npm/pip kurulumu Koi'den gecer.
# ---------------------------------------------------------------------------
if ($NpmGatewayUrl) {
    Invoke-Step "npm registry -> Koi gateway" {
        $url = $NpmGatewayUrl.TrimEnd("/")
        Invoke-Native "npm.cmd" @("config", "set", "registry", $url, "--global")
        Invoke-Native "npm.cmd" @("config", "set", "replace-registry-host", "always", "--global")
    }
} else {
    Write-Host "`n==> npm gateway adresi verilmedi, npm yonlendirmesi atlandi." -ForegroundColor Yellow
}

if ($PypiGatewayUrl) {
    Invoke-Step "pip index -> Koi gateway" {
        $url = $PypiGatewayUrl.TrimEnd("/")
        if ($url -notmatch "/simple$") { $url = "$url/simple" }
        # --global: makine genelinde (C:\ProgramData\pip\pip.ini), venv'ler de okur
        Invoke-Native "python" @("-m", "pip", "config", "--global", "set", "global.index-url", $url)
    }
} else {
    Write-Host "`n==> PyPI gateway adresi verilmedi, pip yonlendirmesi atlandi." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# C6. Marketplace trafigi: Koi Root CA ve PAC dosyasi (Bolum 1-2)
# Kurulumlar bittikten SONRA yapilir; boylece hazirlik sirasindaki extension
# kurulumlari Koi proxy'sinden gecmez.
# ---------------------------------------------------------------------------
# Parametre verilmediyse repodaki certs\ klasorundeki sertifikayi kullan
if (-not $KoiRootCaFile) {
    $repoCa = Get-ChildItem -Path (Join-Path $PSScriptRoot "certs") -File -ErrorAction SilentlyContinue |
        Where-Object { @(".pem", ".cer", ".crt") -contains $_.Extension.ToLower() } | Select-Object -First 1
    if ($repoCa) {
        $KoiRootCaFile = $repoCa.FullName
        Write-Host "`n==> Repodaki sertifika kullaniliyor: certs\$($repoCa.Name)" -ForegroundColor Cyan
    }
}

if ($KoiRootCaFile) {
    Invoke-Step "Koi Root CA -> Trusted Root Certification Authorities" {
        if (-not (Test-Path $KoiRootCaFile)) { throw "CA dosyasi bulunamadi: $KoiRootCaFile" }
        Invoke-Native "certutil.exe" @("-addstore", "-f", "Root", $KoiRootCaFile)
    }
} else {
    Write-Host "`n==> Koi Root CA verilmedi, atlandi (Bolum 1-2 icin gerekli)." -ForegroundColor Yellow
}

if ($PacUrl) {
    Invoke-Step "PAC dosyasi (otomatik proxy yapilandirmasi)" {
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
        Set-ItemProperty -Path $key -Name "AutoConfigURL" -Value $PacUrl
    }
}

# ---------------------------------------------------------------------------
# D. Bolum 3 hazirligi ve masaustu
# ---------------------------------------------------------------------------
Invoke-Step "Masaustu: komutlar.txt" {
    # Tek kaynak repodaki komutlar.txt; script ile ayni klasorde olmali
    $src = Join-Path $PSScriptRoot "komutlar.txt"
    if (-not (Test-Path $src)) {
        throw "komutlar.txt bulunamadi: $src (repoyu zip olarak indirip klasorden calistirin)"
    }
    Copy-Item -Path $src -Destination (Join-Path $Desktop "komutlar.txt") -Force
}

Invoke-Step "Masaustu: AES konsol kisayolu" {
    Write-TextFile (Join-Path $Desktop "AES Konsol.url") "[InternetShortcut]`r`nURL=$KoiConsoleUrl`r`n"
}

Invoke-Step "Masaustu: proje terminali kisayolu" {
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut((Join-Path $Desktop "Proje Terminali.lnk"))
    $lnk.TargetPath       = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $lnk.Arguments        = "-NoExit -Command `"Set-Location '$WebProject'`""
    $lnk.WorkingDirectory = $WebProject
    $lnk.Save()
}

# ---------------------------------------------------------------------------
# Dogrulama
# ---------------------------------------------------------------------------
Write-Host "`n==> Dogrulama" -ForegroundColor Cyan
Update-SessionPath
# Dogrulama sirasinda harici komutlarin stderr ciktisi script'i durdurmasin
$ErrorActionPreference = "Continue"

$checks = [ordered]@{
    "Chrome"                    = (Test-Path "C:\Program Files\Google\Chrome\Application\chrome.exe")
    "VS Code"                   = (Test-Path $CodeCmd)
    "Node / npm"                = [bool](Get-Command npm.cmd -ErrorAction SilentlyContinue)
    "Python"                    = [bool](Get-Command python -ErrorAction SilentlyContinue)
    "Git"                       = [bool](Get-Command git -ErrorAction SilentlyContinue)
    "Claude Code CLI"           = [bool](Get-Command claude -ErrorAction SilentlyContinue)
    "Codex CLI"                 = [bool](Get-Command codex -ErrorAction SilentlyContinue)
    "bogazici-web node_modules" = (Test-Path (Join-Path $WebProject "node_modules\express"))
    "bogazici-api venv"         = (Test-Path (Join-Path $ApiProject ".venv\Scripts\python.exe"))
    "Claude Desktop MCP config" = (Test-Path (Join-Path $env:APPDATA "Claude\claude_desktop_config.json"))
    "Cursor MCP config"         = (Test-Path (Join-Path $WebProject ".cursor\mcp.json"))
    "Skill dosyasi"             = (Test-Path (Join-Path $env:USERPROFILE ".claude\skills\proje-ozeti\SKILL.md"))
    "buttoncontent KURULU DEGIL" = -not (Test-Path (Join-Path $WebProject "node_modules\buttoncontent"))
}
if ($NpmGatewayUrl) {
    $npmReg = (& npm.cmd config get registry 2>$null | Out-String).Trim()
    $checks["npm registry = Koi gateway"] = ($npmReg -like "*gateway.koi.security*")
}
if ($PypiGatewayUrl) {
    # Makine geneli pip.ini'yi dogrudan oku; venv'in de bu ayari gordugunu kontrol et
    $pipIni = Join-Path $env:ProgramData "pip\pip.ini"
    $pipIniOk = (Test-Path $pipIni) -and ((Get-Content $pipIni -Raw) -like "*gateway.koi.security*")
    $checks["pip.ini = Koi gateway"] = $pipIniOk
    $venvPy = Join-Path $ApiProject ".venv\Scripts\python.exe"
    if (Test-Path $venvPy) {
        $venvCfg = (& $venvPy -m pip config list 2>&1 | Out-String)
        $checks["venv pip = Koi gateway"] = ($venvCfg -like "*gateway.koi.security*")
    }
}
if ($KoiRootCaFile -and (Test-Path $KoiRootCaFile)) {
    $caThumb = (New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($KoiRootCaFile)).Thumbprint
    $checks["Koi Root CA guvenilir"] = [bool](Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Thumbprint -eq $caThumb })
}
if ($PacUrl) {
    $pac = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue).AutoConfigURL
    $checks["PAC dosyasi ayarli"] = ($pac -eq $PacUrl)
}
foreach ($k in $checks.Keys) {
    $color = if ($checks[$k]) { "Green" } else { "Red" }
    $mark  = if ($checks[$k]) { "[OK]  " } else { "[YOK] " }
    Write-Host "  $mark$k" -ForegroundColor $color
}

if (Test-Path $CodeCmd) {
    Write-Host "`n  Kurulu VS Code eklentileri:"
    & $CodeCmd --list-extensions | ForEach-Object { Write-Host "    - $_" }
}

Write-Host "`n==> Adim ozeti" -ForegroundColor Cyan
$Results | Format-Table -AutoSize | Out-String | Write-Host

$failed = @($Results | Where-Object { $_.Durum -eq "HATA" })
if ($failed.Count -gt 0) {
    Write-Host "$($failed.Count) adim hata verdi. Log: $SetupDir\setup.log" -ForegroundColor Yellow
}

Write-Host @"

==> ELLE YAPILACAKLAR
  1. Claude Desktop'i kurun:  https://claude.ai/download
  2. Cursor'u kurun:          https://cursor.com/download
     (Ikisinde de giris yapmaniza gerek yok. MCP config dosyalari hazir.)
  3. Chrome'a eklentileri Chrome Web Store'dan kurun:
     - 3-4 populer, masum eklenti
     - 1-2 genis izin isteyen GenAI eklentisi
     (Bolum 2'de "Request Approval" gosterilecek eklentiyi KURMAYIN.)
  4. Chrome ve VS Code'u bir kez acip ilk calistirma ekranlarini kapatin.
  5. Makineyi yeniden baslatin.
  6. KOI'YI KURMADAN AMI alin: aws\01-create-ami.ps1
"@ -ForegroundColor Yellow

Stop-Transcript | Out-Null
