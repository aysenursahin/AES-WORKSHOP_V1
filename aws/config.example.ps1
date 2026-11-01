# ---------------------------------------------------------------------------
# Koi Workshop - AWS ayarlari
#
# Bu dosyayi ayni klasore config.ps1 adiyla kopyalayip doldurun:
#     Copy-Item config.example.ps1 config.ps1
# config.ps1 .gitignore'da; GitHub'a yuklenmez.
# ---------------------------------------------------------------------------

# AWS bolgesi ve AWS CLI profili
$Region     = "eu-north-1"
$AwsProfile = ""   # CloudShell'de bos birakin; kendi PC'nizde profil adi (or. "default")

# Workshop kaynaklarini isaretleyen tag. Script'ler sadece bu tag'li
# instance'lara ve AMI'lere dokunur.
$WorkshopTag = "aes-workshop"

# Katilimci makineleri: WS-USER01, WS-USER02, ...
# (Windows hostname'i en fazla 15 karakter olabilir.)
$NamePrefix       = "WS-USER"
$ParticipantCount = 20
$SpareCount       = 2

# Instance ayarlari
$InstanceType    = "t3.large"
$SubnetId        = "subnet-xxxxxxxx"   # Internete cikisi olan public subnet
$SecurityGroupId = "sg-xxxxxxxx"       # RDP (3389) sadece workshop salonunun IP'sinden
$VolumeSizeGiB   = 60                  # Disk boyutu (GiB). AMI'deki diskten buyukse klonlarda buyutulur
$KeyName         = ""                  # Opsiyonel; wsuser AMI'den geldigi icin sart degil

# Base makine ve AMI
$BaseInstanceId = "i-xxxxxxxx"         # Kurulum script'inin calistigi base makine
$AmiName        = "aes-workshop-base"  # Sonuna tarih eklenir
$AmiId          = ""                   # Bos birakilirsa en yeni workshop AMI'si kullanilir

# SSM icin IAM rolu (00-create-ssm-role.ps1 olusturur)
$RoleName        = "KoiWorkshopSSMRole"
$InstanceProfile = "KoiWorkshopSSMProfile"

# Katilimcilarin RDP ile baglandigi Windows kullanicisi
$WorkshopUser = "wsuser"

# Koi servisinin Windows'taki goruntu adi (Get-Service DisplayName).
# Ilk makinede Koi'yi kurduktan sonra kontrol edip gerekirse duzeltin.
$KoiServicePattern = "*Koi*"

# Koi.msi'nin yuklenecegi private S3 bucket. Bos birakilirsa
# aes-workshop-<hesap-no>-<bolge> adiyla otomatik olusturulur.
$KoiMsiBucket = ""

# Repo'nun raw adresi (06-update-komutlar.ps1 buradan ceker)
$RepoRawBase = "https://raw.githubusercontent.com/aysenursahin/AES-WORKSHOP_V1/main"
