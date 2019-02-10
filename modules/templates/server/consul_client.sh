#!/usr/bin/env bash
set -e
echo "==> Disable UFW"
sudo systemctl stop ufw
sudo systemctl disable ufw

echo "--> Fetching"
install_from_url "consul" "${consul_url}"

echo "--> Writing configuration"
sudo mkdir -p /mnt/consul
sudo mkdir -p /etc/consul.d
sudo tee /etc/consul.d/config.json > /dev/null <<EOF
{
  "acl_datacenter": "dc1",
  "acl_master_token": "${consul_master_token}",
  "acl_token": "${consul_master_token}",
  "acl_default_policy": "allow",
  "advertise_addr": "${private_ip}",
  "advertise_addr_wan": "${public_ip}",
  "bind_addr": "$(private_ip)",
  "node_name": "${node_name}",
  "data_dir": "/mnt/consul",
  "disable_update_check": true,
  "encrypt": "${consul_gossip_key}",
  "leave_on_terminate": true,
  "raft_protocol": 3,
  "retry_join": ["provider=azure tag_name=${consul_join_tag_name}  tag_value=${consul_join_tag_value} tenant_id=${tenant_id} client_id=${client_id} subscription_id=${subscription_id} secret_access_key=${client_secret} "],

  "server": false,
  "ports": {
    "http": 8500,
    "https": 8533
  },
  "key_file": "/etc/ssl/certs/me.key",
  "cert_file": "/etc/ssl/certs/me.crt",
  "ca_file": "/usr/local/share/ca-certificates/01-me.crt",
  "verify_incoming": false,
  "verify_outgoing": false,
  "verify_server_hostname": false,
  "ui": true
}
EOF

echo "--> Writing profile"
sudo tee /etc/profile.d/consul.sh > /dev/null <<"EOF"
alias conslu="consul"
alias ocnsul="consul"
EOF
source /etc/profile.d/consul.sh

echo "--> Generating systemd configuration"
sudo tee /etc/systemd/system/consul.service > /dev/null <<"EOF"
[Unit]
Description=Consul
Documentation=https://www.consul.io/docs/
Requires=network-online.target
After=network-online.target

[Service]
Restart=on-failure
ExecStart=/usr/local/bin/consul agent -config-dir="/etc/consul.d"
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable consul
sudo systemctl restart consul

echo "--> Installing dnsmasq"
ssh-apt install dnsmasq
sudo tee /etc/dnsmasq.d/10-consul > /dev/null <<"EOF"
server=/consul/127.0.0.1#8600
no-poll
server=8.8.8.8
server=8.8.4.4
cache-size=0
EOF
sudo systemctl enable dnsmasq
sudo systemctl restart dnsmasq

echo "==> Consul Client install is done!"
