# Koi Root CA

Bu klasöre Koi Root CA dosyasını (`.pem`) koyun. Deployment Portal → **Network Integration → Establish Network Trust → Download CA**.

`aes-workshop-setup.ps1`, `-KoiRootCaFile` parametresi verilmezse bu klasördeki ilk `.pem`, `.cer` ya da `.crt` dosyasını makinenin **Trusted Root Certification Authorities** deposuna ekler.

Dosya sertifikanın yalnızca açık (public) kısmıdır; özel anahtar içermez.
