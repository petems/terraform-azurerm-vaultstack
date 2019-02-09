# servers private key
resource "tls_private_key" "vault_servers" {
  count       = "${var.vault_servers}"
  algorithm   = "ECDSA"
  ecdsa_curve = "P521"
}

# servers signing request
resource "tls_cert_request" "vault_servers" {
  count           = "${var.vault_servers}"
  key_algorithm   = "${element(tls_private_key.vault_servers.*.algorithm, count.index)}"
  private_key_pem = "${element(tls_private_key.vault_servers.*.private_key_pem, count.index)}"

  subject {
    common_name  = "${var.hostname}-servers-${count.index}.node.consul"
    organization = "Vaultstack Vault Servers"
  }

  dns_names = [
    # Consul
    "*.cloudapp.azure.com",

    "vault.service.consul",
    "active.vault.service.consul",
    "standby.vault.service.consul",
  ]

}

# servers certificate
resource "tls_locally_signed_cert" "vault_servers" {
  count              = "${var.vault_servers}"
  cert_request_pem   = "${element(tls_cert_request.vault_servers.*.cert_request_pem, count.index)}"
  ca_key_algorithm   = "${var.ca_key_algorithm}"
  ca_private_key_pem = "${var.ca_private_key_pem}"
  ca_cert_pem        = "${var.ca_cert_pem}"

  validity_period_hours = 720 # 30 days

  allowed_uses = [
    "client_auth",
    "digital_signature",
    "key_agreement",
    "key_encipherment",
    "server_auth",
  ]
}
