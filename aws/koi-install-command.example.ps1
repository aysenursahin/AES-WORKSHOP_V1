# ---------------------------------------------------------------------------
# Koi kurulum komutu
#
# 1. Bu dosyayi ayni klasore koi-install-command.ps1 adiyla kopyalayin.
# 2. Koi konsolunda Deployment Portal > Endpoints deployment ekraninda
#    Manual > Windows > Installed > Script Package secin.
# 3. Portalin verdigi kurulum komutunu asagiya yapistirin.
#
# Komut "msiexec /i Koi.msi ..." seklindeyse Koi.msi'yi de bu klasore (aws/)
# koyun. 04-install-koi.ps1 MSI'yi private bir S3 bucket uzerinden dagitir
# ve /qn /norestart parametrelerini kendisi ekler.
#
# koi-install-command.ps1 customer ID icerdigi icin .gitignore'da;
# GitHub'a yuklenmez. 04-install-koi.ps1 bu dosyayi okur.
# ---------------------------------------------------------------------------

# <Deployment Portal'daki komutu buraya yapistirin>
