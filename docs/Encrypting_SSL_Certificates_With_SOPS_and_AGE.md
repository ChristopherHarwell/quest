# Encrypting SSL Certificates with SOPS & AGE

To ensure secure storage of SSL certificates, I implemented [SOPS](https://getsops.io/) (Secrets OPerationS) and [AGE](https://age-encryption.org) (a modern encryption tool) to encrypt sensitive files before committing them to Git.

## Why Use SOPS & AGE?
- Secure Storage → Prevents storing plaintext SSL certificates in Git.
- Lightweight Encryption → Uses modern encryption (AGE) instead of GPG.
- Easier Decryption → Only those with the AGE private key can access the original files.
- Automated Encryption Rules → .sops.yaml ensures all SSL-related files are automatically encrypted.

## Encryption Process
### 1.	Generate an AGE Keypair (only needed once)

```sh
age-keygen -o ~/.age-key.txt
```

Extract and save the public key:

```sh
cat ~/.age-key.txt | grep "public key"
```

### 2.	Encrypt SSL Certificates
```sh
sops --encrypt --age <your-public-key> --in-place ssl_cert/wildcard_certificate.pem && \
sops --encrypt --age <your-public-key> --in-place ssl_cert/wildcard_private_key.pem && \
sops --encrypt --age <your-public-key> --in-place ssl_cert/wildcard_csr.pem
```

### 3.	Automate Encryption with .sops.yaml
```yaml
creation_rules:
  - path_regex: ssl_cert/.*\.pem$
    encrypted_regex: '.*'
    age: ["<your-public-key>"]
```

### 4.	Decrypt When Needed

```sh
sops --decrypt --in-place ssl_cert/wildcard_certificate.pem
```

### Terraform Integration

The encrypted certificate files are used in Terraform by referencing them securely:

```hcl
resource "aws_iam_server_certificate" "quest_ssl_cert" {
  name           = "quest_ssl_cert"
  certificate_body = file("ssl_cert/wildcard_certificate.pem")
  private_key     = file("ssl_cert/wildcard_private_key.pem")
}
```

### Git Commit
Once encrypted, SSL files can be committed safely:

```sh
git add ssl_cert/wildcard_certificate.pem ssl_cert/wildcard_private_key.pem ssl_cert/wildcard_csr.pem
git commit -m "chore(security): encrypt SSL certificates using SOPS & AGE"
```