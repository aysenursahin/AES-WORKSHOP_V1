# AES Workshop Lab

Agentic Endpoint Security (AES) hands-on workshop'u için lab makinelerini hazırlayan script'ler.

Akış kısaca şöyle: tek bir **base makine** kurulur, ondan **AMI** alınır, AMI'den katılımcı sayısı kadar makine açılır ve Koi bu makinelere **SSM Run Command** ile tek seferde kurulur. Hiçbir katılımcı makinesine tek tek RDP yapmanız gerekmez.

## Repo içeriği

| Dosya | Ne yapar | Nerede çalışır |
| --- | --- | --- |
| `aes-workshop-setup.ps1` | Uygulamaları, extension'ları, örnek projeleri, MCP config'lerini kurar; npm/pip'i Koi gateway'ine yönlendirir | Base makine |
| `komutlar.txt` | Katılımcıların masaüstündeki hazır komutlar | Base makine (setup kopyalar) |
| `aws/00-create-ssm-role.ps1` | SSM için IAM rolü ve instance profile | CloudShell veya eğitmen bilgisayarı |
| `aws/01-create-ami.ps1` | Base makineden AMI alır | CloudShell veya eğitmen bilgisayarı |
| `aws/02-launch-instances.ps1` | AMI'den `WS-USER01`, `WS-USER02`… makinelerini açar | CloudShell veya eğitmen bilgisayarı |
| `aws/03-rename-hosts.ps1` | Her makinenin hostname'ini kendi adına çevirir | CloudShell veya eğitmen bilgisayarı |
| `aws/04-install-koi.ps1` | Koi'yi tüm makinelere kurar | CloudShell veya eğitmen bilgisayarı |
| `aws/05-check.ps1` | Tüm makinelerin hazır olduğunu kontrol eder | CloudShell veya eğitmen bilgisayarı |
| `aws/06-update-komutlar.ps1` | Güncel `komutlar.txt`'yi tüm masaüstlerine dağıtır | CloudShell veya eğitmen bilgisayarı |
| `aws/07-list-instances.ps1` | Katılımcı listesini (`participants.csv`) çıkarır | CloudShell veya eğitmen bilgisayarı |
| `aws/08-power.ps1` | Makineleri başlatır / durdurur | CloudShell veya eğitmen bilgisayarı |
| `aws/99-cleanup.ps1` | Workshop sonrası makineleri (ve istenirse AMI'yi) siler | CloudShell veya eğitmen bilgisayarı |

## Lab rehberi

Katılımcılara dağıtılan rehber iki biçimde:
- **Word:** [`docs/AES Workshop Lab Rehberi v1.docx`](docs/AES%20Workshop%20Lab%20Rehberi%20v1.docx)
- **Web:** [`site/`](site/) klasörü. Yan menü, kopyalanabilir komutlar ve bölüm ilerleme takibi içerir; telefonda da çalışır.

**Web sürümünü Render'da yayınlamak:** [Render](https://render.com) → **New → Blueprint** → bu repoyu bağlayın → **Apply**. Repodaki [`render.yaml`](render.yaml) statik siteyi `site/` klasöründen yayınlar; adres `https://aes-workshop.onrender.com` biçiminde olur (ad doluysa Render bir ek getirir). `main` dalına her gönderimde site otomatik güncellenir.

## Gereksinimler

**AWS**
- Bir AWS hesabı ve konsola giriş. Hesabı e-postanızla açtıysanız giriş ekranında **Sign in using root user email** seçin; **IAM user** ekranı Account ID ve kullanıcı adı ister.
- Tüm kaynaklar aynı bölgede, örnek: **Europe (Stockholm) eu-north-1**

**AES (Koi) tenant'ı**
- Code package prevention açık olmalı (Koi irtibat kişisi açar)
- npm global block list'te `buttoncontent` paketi (lab rehberi Bölüm 3); eklendikten sonra yayılması 60 dakikaya kadar sürebilir
- Deployment Portal'dan:
  - Windows kurulum komutu: **Manual → Windows → Installed → Script Package**
  - npm ve PyPI gateway adresleri: `https://koi-npmjs-<customer_subdomain>.gateway.koi.security`, `https://koi-pypi-<customer_subdomain>.gateway.koi.security`
  - PAC dosyası URL'i: **Network Integration**
  - Koi Root CA: **Network Integration → Establish Network Trust → Download CA**. Bu repoda [`certs/`](certs/) altında hazır.

---

## 1. Base makineyi oluştur (AWS konsolu)

EC2 → **Launch instance**:

| Ayar | Değer |
| --- | --- |
| Name | `aes-base` |
| Application and OS Images | **Windows** → **Microsoft Windows Server 2022 Base** |
| Instance type | `t3.large` (2 vCPU, 8 GB RAM) |
| Key pair | **Create new key pair** → `aes-workshop-key`, RSA, `.pem`. Dosyayı saklayın; Administrator şifresini çözmek için gerekir. |
| Network settings → Edit | Default VPC, **Auto-assign public IP: Enable**, **Create security group** `aes-workshop-sg`, RDP kuralının **Source type: My IP** |
| Configure storage | **60 GiB gp3** |

**Launch instance** → makine **Running** ve **2/2 checks passed** olana kadar bekleyin (5–10 dakika).

**Bağlanmak için:** makineyi seçin → **Connect → RDP client** → **Get password** (`.pem` dosyasını yükleyin) → **Download remote desktop file**. Kullanıcı adı `Administrator`.
- **Windows:** `.rdp` dosyasını açın (Remote Desktop Connection).
- **Mac:** App Store'dan **Windows App**'i kurun, `.rdp` dosyasına çift tıklayın. Türkçe klavyede `@`, `\` gibi karakterler yanlış tuşa denk gelebilir; komutları yazmak yerine yapıştırın.

**Katılımcı hesabını oluşturun** (yönetici PowerShell'de). Şifre en az 8 karakter olmalı; büyük harf, küçük harf, rakam ve özel karakter içermeli:

```powershell
$pw = Read-Host "wsuser sifresi" -AsSecureString
New-LocalUser -Name wsuser -Password $pw -PasswordNeverExpires
Add-LocalGroupMember -Group Administrators -Member wsuser
```

Administrator oturumunu kapatın ve **`wsuser` ile** tekrar bağlanın (Windows App'te makine kartı → **Edit → Credentials**).

## 2. Base makineyi hazırla (`wsuser` ile)

**Yönetici olarak açılmış PowerShell'de** (`<...>` alanlarını doldurun):

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Set-ExecutionPolicy Bypass -Scope Process -Force
$zip = "$env:TEMP\aes-workshop.zip"
irm https://github.com/aysenursahin/AES-WORKSHOP_V1/archive/refs/heads/main.zip -OutFile $zip
Expand-Archive $zip -DestinationPath "$env:TEMP\aes-workshop" -Force
& "$env:TEMP\aes-workshop\AES-WORKSHOP_V1-main\aes-workshop-setup.ps1" `
    -KoiConsoleUrl  "https://<konsol-adresi>" `
    -NpmGatewayUrl  "https://koi-npmjs-<customer_subdomain>.gateway.koi.security" `
    -PypiGatewayUrl "https://koi-pypi-<customer_subdomain>.gateway.koi.security" `
    -PacUrl         "<PAC dosyasi URL'i>"
```

Kurulum 15–20 dakika sürer. Script:
- Chrome, VS Code, Node.js, Python, Git, VS Code extension'ları, Claude Code ve Codex CLI'ı kurar
- Örnek projeleri, MCP config'lerini, örnek skill'i ve sahte `.env` dosyasını oluşturur
- npm ve pip'i Koi gateway'ine yönlendirir
- [`certs/`](certs/) klasöründeki **Koi Root CA**'yı makinenin Trusted Root deposuna ekler (başka bir dosya için `-KoiRootCaFile "<yol>"`)
- **PAC dosyasını** `wsuser`'ın proxy ayarlarına yazar
- Masaüstüne `komutlar.txt`, **AES Konsol** ve **Proje Terminali** kısayollarını koyar

> **PAC dosyası:** `-PacUrl` vermek yerine AES konsolunda **Settings → Advanced Settings → Network integration (Proxy) → Deploy with KOI** seçerseniz PAC'i Koi'nin script paketi kurar. Ancak o zaman PAC, AES kurulana kadar (5. adım) devreye girmez ve aşağıdaki `/koi` kontrolünü base makinede yapamazsınız.

Sondaki kontrol listesinde her satır `[OK]` olmalı; özellikle **Koi Root CA guvenilir**, **PAC dosyasi ayarli**, **npm registry = Koi gateway** ve **pip.ini = Koi gateway**. Script güvenle tekrar çalıştırılabilir.

**Ardından elle:**

1. **Claude Desktop** ve **Cursor**'u kurun: [claude.ai/download](https://claude.ai/download), [cursor.com/download](https://cursor.com/download). Cursor için **User Setup, x64** sürümü. İkisini de `wsuser` ile kurun.
2. Uygulamaları (Chrome, VS Code, Cursor, Claude Desktop) bir kez açıp ilk açılış ekranlarını kapatın. Giriş ekranı çıkarsa **giriş yapmayın** (aşağıdaki uyarıya bakın).
3. **Koi proxy'sini doğrulayın:** Chrome'u kapatıp açın ve `https://marketplace.visualstudio.com/koi` adresine gidin.
   - Koi'nin zeplin görselli sayfası → doğru.
   - Sertifika hatası → Koi Root CA kurulmamış.
   - Normal marketplace sayfası → PAC uygulanmamış.
4. **Chrome'a 3–4 popüler extension kurun.** PAC devrede olduğu için bu kurulumlar Koi'den geçer; bu, lab rehberi Bölüm 1'in provasıdır. **Request Approval** çıkan extension'ı kurmayın; adını Bölüm 2 için not edin.
5. Makineyi yeniden başlatın.

> **Base makineye bunları KOYMAYIN.** Base makinede ne varsa AMI ile tüm katılımcı makinelerine kopyalanır:
> - **AES/Koi:** Klonlar aynı cihaz kimliğini taşıyabilir ve konsolda tek makine gibi görünür. AES 5. adımda her makineye ayrı kurulur.
> - **Kişisel hesaplar:** Cursor, Claude Desktop, Chrome veya GitHub'da giriş yapmayın; oturumunuz tüm katılımcılara kopyalanır.
> - **AWS anahtarları:** `aws/` script'lerini base makinede çalıştırmayın (3. adım).

## 3. AWS ayarlarını yap (base makinede DEĞİL)

`aws/` script'leri AWS anahtarı gerektirir ve `01` base makineyi yeniden başlatır. Bu yüzden base makine dışında bir yerde çalıştırın.

**Seçenek A: AWS CloudShell (önerilen).** AWS konsolunda sağ üstteki **`>_`** simgesi. AWS CLI ve PowerShell hazır gelir, hesabınızla oturum açıktır; access key gerekmez. Bölgenin doğru olduğundan emin olun.

```bash
git clone https://github.com/aysenursahin/AES-WORKSHOP_V1.git
cd aes-workshop_v1/aws
cp config.example.ps1 config.ps1
cp koi-install-command.example.ps1 koi-install-command.ps1
nano config.ps1                     # kaydet: Ctrl+O, Enter; çık: Ctrl+X
nano koi-install-command.ps1
pwsh
```

**Seçenek B: Kendi bilgisayarınız.**
- **Windows:** [AWS CLI v2](https://awscli.amazonaws.com/AWSCLIV2.msi) kurun. Repoyu `git clone` ile ya da zip olarak indirin. Script'lerden önce `Set-ExecutionPolicy Bypass -Scope Process -Force`.
- **Mac:** `brew install awscli` ve `brew install --cask powershell`, sonra `pwsh`. `Set-ExecutionPolicy` gerekmez; yollarda `/` kullanın.
- Her ikisinde de: IAM → Users → kullanıcınız → **Security credentials → Create access key**, ardından `aws configure` (bölge: `eu-north-1`, çıktı: `json`).

**`config.ps1`** (değerler EC2'de base makinenin detaylarında):

| Ayar | Nereden |
| --- | --- |
| `$Region` | Base makinenin bölgesi, örn. `eu-north-1` |
| `$BaseInstanceId` | **Instance ID** (`i-...`) |
| `$SubnetId` | **Networking** sekmesi → **Subnet ID** (`subnet-...`) |
| `$SecurityGroupId` | **Security** sekmesi → `aes-workshop-sg` ID'si (`sg-...`) |
| `$ParticipantCount` / `$SpareCount` | **İlk denemede `1` ve `0`.** Pilot makine sorunsuzsa artırın (5. adım). |

**`koi-install-command.ps1`:** Deployment Portal'daki Windows kurulum komutunu yapıştırın.

Bu iki dosya `.gitignore`'da; GitHub'a yüklenmez. Sonra bir kere:

```powershell
./00-create-ssm-role.ps1
```

IAM değişikliklerinin yayılması için 1–2 dakika bekleyin.

## 4. AMI al

```powershell
./01-create-ami.ps1
```

Script önce kontrol soruları sorar. Base makine bu sırada yeniden başlar ve RDP bağlantısı kopar. AMI'nin hazır olması 15–30 dakika sürer.

## 5. Katılımcı makinelerini aç ve AES'i kur

**Önce tek makineyle pilot** (`config.ps1`'de `$ParticipantCount = 1`, `$SpareCount = 0`):

```powershell
./02-launch-instances.ps1          # WS-USER01
./03-rename-hosts.ps1              # hostname'i değiştirir, makineyi yeniden başlatır
./04-install-koi.ps1               # AES'i kurar
```

İlk makinede AES servisinin Windows'taki adını kontrol edin (`Get-Service`). `*Koi*` ile eşleşmiyorsa `config.ps1` içindeki `$KoiServicePattern`'i düzeltin.

Inventory'nin konsolda dolması için birkaç saat bekleyin; extension'lar, paketler, MCP server'lar ve AI agent'lar görünmeli. Lab rehberini WS-USER01'de baştan sona bir kez uygulamak en iyi provadır.

**Pilot sorunsuzsa çoğaltın:** `config.ps1`'de sayıları artırın (örn. `20` ve `2`) ve 02, 03, 04'ü tekrar çalıştırın. Script'ler var olan makineleri atlar.

## 6. Kontrol et ve katılımcı listesini çıkar

```powershell
./05-check.ps1             # AES servisi, npm/pip yönlendirmesi, komutlar.txt
./07-list-instances.ps1    # participants.csv: makine, RDP adresi, kullanıcı
```

`participants.csv` dosyasında şifre sütununu doldurup katılımcılara dağıtabilirsiniz. Workshop günü salonun IP'sini `aes-workshop-sg` security group'una RDP için ekleyin. `05-check.ps1`'i workshop sabahı da çalıştırın.

## Workshop'a kadar

```powershell
./08-power.ps1 -Action Stop    # hazırlık bittikten sonra
./08-power.ps1 -Action Start   # workshop sabahı
./07-list-instances.ps1        # IP'ler değiştiği için listeyi yenileyin
```

`komutlar.txt`'yi güncellerseniz AMI'yi yeniden almanıza gerek yok:

```powershell
./06-update-komutlar.ps1
```

## Workshop sonrası

```powershell
./99-cleanup.ps1               # katılımcı makinelerini siler
./99-cleanup.ps1 -DeleteAmi    # AMI ve snapshot'ları da siler
```

Base makineye dokunulmaz; ayrıca silmeniz gerekir.

---

## Sık karşılaşılan sorunlar

| Belirti | Çözüm |
| --- | --- |
| `running scripts is disabled on this system` | Aynı pencerede `Set-ExecutionPolicy Bypass -Scope Process -Force` çalıştırın |
| `npm install` engellenmesi gereken paketi kuruyor | `npm config get registry` Koi gateway'ini göstermeli; gösteriyorsa paketin npm global block list'te olduğunu ve tenant'ta code package prevention'ın açık olduğunu kontrol edin |
| SSM'de makine `Online` olmuyor | Instance'ın IAM profile'ı (`00-create-ssm-role.ps1`) ve internete çıkışı olmalı |
| `04-install-koi.ps1` "servis bulunamadı" diyor | `config.ps1` içindeki `$KoiServicePattern`'i gerçek servis adına göre düzeltin |
| `net localgroup ... ` → `The user name could not be found` (2221) | Kullanıcı oluşmamış; büyük ihtimalle şifre kurallara uymadı. 1. adımdaki `New-LocalUser` komutlarını kullanın. |
| AWS girişinde **IAM user sign in** ekranı | Hesabı e-postayla açtıysanız **Sign in using root user email**'e tıklayın |
| Kurulumda `PowerShell execution policy` adımı `Security error` | Eski script sürümünde yanlış alarmdı; ayar uygulanır. `Get-ExecutionPolicy -List`'te `LocalMachine` = `RemoteSigned` olmalı. |
| `/koi` sayfasında sertifika hatası | Koi Root CA kurulmamış: `Get-ChildItem Cert:\LocalMachine\Root \| Where-Object Subject -like "*Koi Root CA*"` |
| `/koi` yerine normal marketplace sayfası | PAC uygulanmamış ya da tarayıcı yeniden başlatılmamış. Windows Ayarlar → Network & Internet → Proxy → **Use setup script** açık olmalı. |
| Cursor / Claude Desktop giriş istiyor | Base makinede giriş yapmayın; pencereyi kapatın. Inventory için kurulu olmaları yeterli. |
| Chrome kurulumu checksum hatası veriyor | Script Chrome için checksum kontrolünü atlıyor; güncel script'i kullandığınızdan emin olun |

## Bu repoda olmayanlar

Repo public'tir ve gizli bilgi içermez. Tenant adresleri ve gateway URL'leri script'e parametre olarak verilir. `aws/config.ps1`, `aws/koi-install-command.ps1` ve `aws/participants.csv` yerel dosyalardır ve `.gitignore` ile dışarıda tutulur.
