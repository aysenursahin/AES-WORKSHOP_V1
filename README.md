# AES Workshop Lab

Agentic Endpoint Security (AES) hands-on workshop'u için lab makinelerini hazırlayan script'ler.

Akış kısaca şöyle: tek bir **base makine** kurulur, ondan **AMI** alınır, AMI'den katılımcı sayısı kadar makine açılır ve Koi bu makinelere **SSM Run Command** ile tek seferde kurulur. Hiçbir katılımcı makinesine tek tek RDP yapmanız gerekmez.

## Repo içeriği

| Dosya | Ne yapar | Nerede çalışır |
| --- | --- | --- |
| `aes-workshop-setup.ps1` | Uygulamaları, extension'ları, örnek projeleri, MCP config'lerini kurar; npm/pip'i Koi gateway'ine yönlendirir | Base makine |
| `komutlar.txt` | Katılımcıların masaüstündeki hazır komutlar | Base makine (setup kopyalar) |
| `aws/00-create-ssm-role.ps1` | SSM için IAM rolü ve instance profile | Eğitmen bilgisayarı |
| `aws/01-create-ami.ps1` | Base makineden AMI alır | Eğitmen bilgisayarı |
| `aws/02-launch-instances.ps1` | AMI'den `WS-USER01`, `WS-USER02`… makinelerini açar | Eğitmen bilgisayarı |
| `aws/03-rename-hosts.ps1` | Her makinenin hostname'ini kendi adına çevirir | Eğitmen bilgisayarı |
| `aws/04-install-koi.ps1` | Koi'yi tüm makinelere kurar | Eğitmen bilgisayarı |
| `aws/05-check.ps1` | Tüm makinelerin hazır olduğunu kontrol eder | Eğitmen bilgisayarı |
| `aws/06-update-komutlar.ps1` | Güncel `komutlar.txt`'yi tüm masaüstlerine dağıtır | Eğitmen bilgisayarı |
| `aws/07-list-instances.ps1` | Katılımcı listesini (`participants.csv`) çıkarır | Eğitmen bilgisayarı |
| `aws/08-power.ps1` | Makineleri başlatır / durdurur | Eğitmen bilgisayarı |
| `aws/99-cleanup.ps1` | Workshop sonrası makineleri (ve istenirse AMI'yi) siler | Eğitmen bilgisayarı |

## Lab rehberi

Katılımcılara dağıtılan rehber: [`docs/AES Workshop Lab Rehberi v1.docx`](docs/AES%20Workshop%20Lab%20Rehberi%20v1.docx)

## Gereksinimler

**Eğitmen bilgisayarı**
- Windows PowerShell 5.1 veya üzeri
- [AWS CLI v2](https://aws.amazon.com/cli/), `aws configure` ile yapılandırılmış

**AWS**
- Internete çıkışı olan bir public subnet
- Bir security group: RDP (3389) sadece workshop salonunun IP'sinden, giden 443 açık
- Windows base instance (`t3.large` yeterli)

**Koi**
- Deployment Portal'daki Windows kurulum komutu (Manual → Windows → Installed → Script Package)
- npm ve PyPI gateway adresleri: `https://koi-npmjs-<customer_subdomain>.gateway.koi.security` ve `https://koi-pypi-<customer_subdomain>.gateway.koi.security`
- Tenant'ta code package prevention açılmış olmalı (Koi irtibat kişisi açar)

---

## 1. Base makineyi hazırla

EC2'de Windows instance açın ve `Administrator` ile RDP yapın. Katılımcıların kullanacağı hesabı oluşturun:

```powershell
net user wsuser <sifre> /add
net localgroup administrators wsuser /add
```

Oturumu kapatıp **`wsuser` ile** tekrar RDP yapın. Yönetici olarak açılmış PowerShell'de:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
$zip = "$env:TEMP\aes-workshop.zip"
irm https://github.com/aysenursahin/aes-workshop_v1/archive/refs/heads/main.zip -OutFile $zip
Expand-Archive $zip -DestinationPath "$env:TEMP\aes-workshop" -Force
& "$env:TEMP\aes-workshop\aes-workshop_v1-main\aes-workshop-setup.ps1" `
    -KoiConsoleUrl  "https://<konsol-adresi>" `
    -NpmGatewayUrl  "https://koi-npmjs-<customer_subdomain>.gateway.koi.security" `
    -PypiGatewayUrl "https://koi-pypi-<customer_subdomain>.gateway.koi.security"
```

> Script'i **`wsuser` ile** çalıştırın. VS Code extension'ları, MCP config'leri ve skill dosyası script'i çalıştıran kullanıcının profiline yazılır.

Script bittiğinde sondaki kontrol listesinde her satır `[OK]` olmalı. Ardından elle:

1. [Claude Desktop](https://claude.ai/download) ve [Cursor](https://cursor.com/download) kurun (giriş yapmanıza gerek yok).
2. Chrome'a 3–4 popüler extension kurun. Workshop'ta **Request Approval** gösterilecek extension'ı **kurmayın**.
3. Chrome ve VS Code'u bir kez açıp ilk açılış ekranlarını kapatın.
4. Makineyi yeniden başlatın.

> **Base makineye Koi kurmayın.** Koi kurulu bir makineden AMI alırsanız tüm klonlar aynı cihaz kimliğini taşıyabilir ve konsolda tek makine gibi görünür. Koi, 4. adımda her makineye ayrı kurulur.

## 2. AWS ayarlarını yap

Eğitmen bilgisayarında:

```powershell
git clone https://github.com/aysenursahin/aes-workshop_v1.git
cd aes-workshop_v1\aws
Set-ExecutionPolicy Bypass -Scope Process -Force

Copy-Item config.example.ps1 config.ps1
Copy-Item koi-install-command.example.ps1 koi-install-command.ps1
```

- `config.ps1`: bölge, subnet, security group, base instance ID ve katılımcı sayısını doldurun.
- `koi-install-command.ps1`: Deployment Portal'daki kurulum komutunu yapıştırın.

Bu iki dosya `.gitignore`'da; GitHub'a yüklenmez. Sonra bir kere:

```powershell
.\00-create-ssm-role.ps1
```

## 3. AMI al

```powershell
.\01-create-ami.ps1
```

Base makine bu sırada yeniden başlar. AMI hazır olana kadar 15–30 dakika sürebilir.

## 4. Katılımcı makinelerini aç ve Koi'yi kur

```powershell
.\02-launch-instances.ps1          # WS-USER01 ... (katılımcı + yedek)
.\03-rename-hosts.ps1              # hostname'leri değiştirir, makineleri yeniden başlatır
.\04-install-koi.ps1 -Only WS-USER01   # önce tek makinede deneyin
.\04-install-koi.ps1               # sonra hepsine
```

İlk makinede Koi servisinin Windows'taki adını kontrol edin (`Get-Service`). `*Koi*` ile eşleşmiyorsa `config.ps1` içindeki `$KoiServicePattern`'i düzeltin.

Envanterin konsolda dolması için birkaç saat bekleyin.

## 5. Kontrol et ve katılımcı listesini çıkar

```powershell
.\05-check.ps1             # Koi servisi, npm/pip yönlendirmesi, komutlar.txt
.\07-list-instances.ps1    # participants.csv: makine, RDP adresi, kullanıcı
```

`participants.csv` dosyasında şifre sütununu doldurup katılımcılara dağıtabilirsiniz. `05-check.ps1`'i workshop sabahı da çalıştırın.

## Workshop'a kadar

```powershell
.\08-power.ps1 -Action Stop    # hazırlık bittikten sonra
.\08-power.ps1 -Action Start   # workshop sabahı
.\07-list-instances.ps1        # IP'ler değiştiği için listeyi yenileyin
```

`komutlar.txt`'yi güncellerseniz AMI'yi yeniden almanıza gerek yok:

```powershell
.\06-update-komutlar.ps1
```

## Workshop sonrası

```powershell
.\99-cleanup.ps1               # katılımcı makinelerini siler
.\99-cleanup.ps1 -DeleteAmi    # AMI ve snapshot'ları da siler
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
| Chrome kurulumu checksum hatası veriyor | Script Chrome için checksum kontrolünü atlıyor; güncel script'i kullandığınızdan emin olun |

## Bu repoda olmayanlar

Repo public'tir ve gizli bilgi içermez. Tenant adresleri ve gateway URL'leri script'e parametre olarak verilir. `aws/config.ps1`, `aws/koi-install-command.ps1` ve `aws/participants.csv` yerel dosyalardır ve `.gitignore` ile dışarıda tutulur.
