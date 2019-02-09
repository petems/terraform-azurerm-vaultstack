#!/usr/bin/env bash
set -e

echo "==> Vault (server)"
# Vault expects the key to be concatenated with the CA
sudo mkdir -p /etc/vault.d/tls/
sudo tee /etc/vault.d/tls/vault.crt > /dev/null <<EOF
$(cat /etc/ssl/certs/me.crt)
$(cat /usr/local/share/ca-certificates/01-me.crt)
EOF

echo "--> Fetching"
install_from_url "vault" "${vault_url}"

echo "--> Creating Vault user and group"
groupadd vault
useradd -r -g vault -d /usr/local/vault -m -s /sbin/nologin -c "Vault user" vault

echo "Giving Vault permission to use the mlock syscall"
sudo setcap cap_ipc_lock=+ep $(readlink -f $(which vault))

echo "--> Writing configuration"
sudo mkdir -p /etc/vault.d
sudo tee /etc/vault.d/config.hcl > /dev/null <<EOF

cluster_name = "${hostname}-vaultstack"

storage "consul" {
  path = "vault/"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/etc/vault.d/tls/vault.crt"
  tls_key_file  = "/etc/ssl/certs/me.key"
}


seal "azurekeyvault" {
  tenant_id      = "${tenant_id}"
  client_id      = "${client_id}"
  client_secret  = "${client_secret}"
  vault_name     = "${kmsvaultname}"
  key_name       = "${kmskeyname}"
  enviroment     = "AzurePublicCloud"
}

api_addr = "https://${public_ip}:8200"

ui = true
EOF

echo "--> Writing profile"
sudo tee /etc/profile.d/vault.sh > /dev/null <<"EOF"
alias vualt="vault"
export VAULT_ADDR="https://active.vault.service.consul:8200"
EOF
source /etc/profile.d/vault.sh

echo "--> Generating systemd configuration"
sudo tee /etc/systemd/system/vault.service > /dev/null <<"EOF"
[Unit]
Description="HashiCorp Vault - A tool for managing secrets"
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/config.hcl

[Service]
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/config.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitBurst=3
LimitMEMLOCK=infinity
StartLimitInterval=60
EOF

sudo systemctl enable vault
sudo systemctl start vault


echo "==> Vault is done!"
