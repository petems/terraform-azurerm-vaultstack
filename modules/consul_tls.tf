# servers private key
resource "tls_private_key" "consul_servers" {
  count       = "${var.consul_servers}"
  algorithm   = "ECDSA"
  ecdsa_curve = "P521"
}

# servers signing request
resource "tls_cert_request" "consul_servers" {
  count           = "${var.consul_servers}"
  key_algorithm   = "${element(tls_private_key.consul_servers.*.algorithm, count.index)}"
  private_key_pem = "${element(tls_private_key.consul_servers.*.private_key_pem, count.index)}"

  subject {
    common_name  = "${var.hostname}-servers-${count.index}.node.consul"
    organization = "Vaultstack Consul Servers"
  }

  dns_names = [
    # Consul
    "*.cloudapp.azure.com",

    "${var.hostname}-servers-${count.index}.node.consul",
    "consul.service.consul",
    "servers.dc1.consul",
  ]

}

# servers certificate
resource "tls_locally_signed_cert" "consul_servers" {
  count              = "${var.consul_servers}"
  cert_request_pem   = "${element(tls_cert_request.consul_servers.*.cert_request_pem, count.index)}"
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

# Consul gossip encryption key
resource "random_id" "consul_gossip_key" {
  byte_length = 16
}

# Consul master token
resource "random_id" "consul_master_token" {
  byte_length = 16
}

# Consul join key
resource "random_id" "consul_join_tag_value" {
  byte_length = 16
}
