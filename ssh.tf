# Create an SSH key

resource "tls_private_key" "bootstrap_private_key" {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "local_file" "bootstrap_private_key" {
  content         = tls_private_key.bootstrap_private_key.private_key_pem
  filename        = "bootstrap_private_key.pem"
  file_permission = "0600"
}
