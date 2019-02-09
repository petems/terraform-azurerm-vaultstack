data "template_file" "vault_servers_script" {
  depends_on = ["azurerm_public_ip.vault-servers-pip", "azurerm_key_vault.vaultstack"]
  count      = "${var.vault_servers}"

  template = "${join("\n", list(
    file("${path.module}/templates/shared/base.sh"),
    file("${path.module}/templates/server/consul_client.sh"),
    file("${path.module}/templates/server/vault.sh"),
    file("${path.module}/templates/shared/cleanup.sh"),
  ))}"

  vars {
    hostname      = "${var.hostname}-vault-servers-${count.index}"
    private_ip    = "${element(azurerm_network_interface.vault-servers-nic.*.private_ip_address, count.index)}"
    public_ip     = "${element(azurerm_public_ip.vault-servers-pip.*.ip_address, count.index)}"

    kmsvaultname  = "${azurerm_key_vault.vaultstack.name}"
    kmskeyname    = "${azurerm_key_vault_key.vaultstack.name}"

    subscription_id = "${var.subscription}"

    tenant_id     = "${var.tenant}"
    client_id     = "${var.client_id}"
    client_secret = "${var.client_secret}"
    object_id     = "${azurerm_user_assigned_identity.vaultstack.principal_id}"
    fqdn          = "${element(azurerm_public_ip.vault-servers-pip.*.fqdn, count.index)}"
    node_name     = "${var.hostname}-vault-servers-${count.index}"
    me_ca         = "${var.ca_cert_pem}"
    me_cert       = "${element(tls_locally_signed_cert.vault_servers.*.cert_pem, count.index)}"
    me_key        = "${element(tls_private_key.vault_servers.*.private_key_pem, count.index)}"

    # Consul
    consul_url            = "${var.consul_url}"
    consul_gossip_key     = "${base64encode(random_id.consul_gossip_key.hex)}"
    consul_join_tag_key   = "ConsulJoin"
    consul_join_tag_name  = "vaultstack"
    consul_join_tag_value = "${local.consul_join_tag_value}"
    consul_master_token   = "${random_id.consul_master_token.hex}"

    # Vault
    vault_url        = "${var.vault_url}"
    vault_servers    = "${var.vault_servers}"
  }
}

# Gzip cloud-init config
data "template_cloudinit_config" "vault_servers_cloudinit" {
  count = "${var.vault_servers}"

  gzip          = true
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content      = "${element(data.template_file.vault_servers_script.*.rendered, count.index)}"
  }
}

# Every Azure Virtual Machine comes with a private IP address. You can also
# optionally add a public IP address for Internet-facing applications and
# demo environments like this one.
resource "azurerm_public_ip" "vault-servers-pip" {
  count               = "${var.consul_servers}"
  name                = "${var.stack_prefix}-vault-servers-ip-${count.index}"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.vaultstack.name}"
  allocation_method   = "Static"
  domain_name_label   = "${var.hostname}-vault-servers-${count.index}"
  sku                 = "Standard"

  tags {
    name      = "Peter Souter"
    ttl       = "13"
    owner     = "psouter@hashicorp.com"
    vaultstack = "${local.consul_join_tag_value}"
  }
}

resource "azurerm_network_interface" "vault-servers-nic" {
  count                     = "${var.consul_servers}"
  name                      = "${var.stack_prefix}-vault-servers-nic-${count.index}"
  location                  = "${var.location}"
  resource_group_name       = "${azurerm_resource_group.vaultstack.name}"
  network_security_group_id = "${azurerm_network_security_group.vaultstack-sg.id}"

  ip_configuration {
    name                          = "${var.stack_prefix}-${count.index}-ipconfig"
    subnet_id                     = "${azurerm_subnet.subnet.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${element(azurerm_public_ip.vault-servers-pip.*.id, count.index)}"
  }

  tags {
    name      = "Peter Souter"
    ttl       = "13"
    owner     = "psouter@hashicorp.com"
    vaultstack = "${local.consul_join_tag_value}"
  }
}

# Create Public IP Address for the Load Balancer
resource "azurerm_public_ip" "vault-servers-lb-public-ip" {
  count               = 1
  name                = "${var.resource_group}-vault-servers-lb-pubip"
  resource_group_name = "${azurerm_resource_group.vaultstack.name}"
  location            = "${var.location}"
  allocation_method   = "Static"
  domain_name_label   = "${var.hostname}-vault-servers-lb-${count.index}"
  sku                 = "Standard"

  tags {
    name      = "Peter Souter"
    ttl       = "13"
    owner     = "psouter@hashicorp.com"
    vaultstack = "${local.consul_join_tag_value}"
  }
}

# create and configure Azure Load Balancer

resource "azurerm_lb" "vault-lb" {
  name                = "${var.resource_group}-vault-lb"
  resource_group_name = "${azurerm_resource_group.vaultstack.name}"
  location            = "${var.location}"
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "${var.resource_group}-vault-frontendip"
    public_ip_address_id = "${azurerm_public_ip.vault-servers-lb-public-ip.id}"
  }

  tags {
    name      = "Peter Souter"
    ttl       = "13"
    owner     = "psouter@hashicorp.com"
    vaultstack = "${local.consul_join_tag_value}"
  }
}

resource "azurerm_lb_probe" "vault-lb-probe" {
  name                = "${var.resource_group}-vault-probe"
  resource_group_name = "${azurerm_resource_group.vaultstack.name}"
  loadbalancer_id     = "${azurerm_lb.vault-lb.id}"
  protocol            = "https"
  port                = "8200"
  request_path        = "/v1/sys/health"
  number_of_probes    = "1"
}

resource "azurerm_lb_backend_address_pool" "vault-lb-backend-pool" {
  name                = "${var.resource_group}-vault-bck-pool"
  resource_group_name = "${azurerm_resource_group.vaultstack.name}"
  loadbalancer_id     = "${azurerm_lb.vault-lb.id}"
}

resource "azurerm_lb_rule" "vault-lb-rule" {
  name                           = "${var.resource_group}-vault-lb-rule"
  resource_group_name            = "${azurerm_resource_group.vaultstack.name}"
  loadbalancer_id                = "${azurerm_lb.vault-lb.id}"
  protocol                       = "Tcp"
  frontend_port                  = "80"
  backend_port                   = "8200"
  frontend_ip_configuration_name = "${var.resource_group}-vault-frontendip"
  probe_id                       = "${azurerm_lb_probe.vault-lb-probe.id}"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.vault-lb-backend-pool.id}"
  depends_on                     = ["azurerm_lb_probe.vault-lb-probe", "azurerm_lb_backend_address_pool.vault-lb-backend-pool"]
}

# And finally we build our vaultstack servers. This is a standard Ubuntu instance.
resource "azurerm_virtual_machine" "vault_servers" {
  count               = "${var.vault_servers}"
  name                = "${var.hostname}-vault-servers-${count.index}"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.vaultstack.name}"
  vm_size             = "${var.vm_size}"
  availability_set_id = "${azurerm_availability_set.vault_avail_set.id}"

  network_interface_ids         = ["${element(azurerm_network_interface.vault-servers-nic.*.id, count.index)}"]
  delete_os_disk_on_termination = "true"

  storage_image_reference {
    publisher = "${var.image_publisher}"
    offer     = "${var.image_offer}"
    sku       = "${var.image_sku}"
    version   = "${var.image_version}"
  }

  storage_os_disk {
    name              = "${var.hostname}-vault-server-osdisk-${count.index}"
    managed_disk_type = "Standard_LRS"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    disk_size_gb      = "${var.storage_disk_size}"
  }

  os_profile {
    computer_name  = "${var.hostname}-vault-servers-${count.index}"
    admin_username = "${var.admin_username}"
    admin_password = "${var.admin_password}"
    custom_data    = "${element(data.template_cloudinit_config.vault_servers_cloudinit.*.rendered, count.index)}"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  tags {
    name      = "Peter Souter"
    ttl       = "13"
    owner     = "psouter@hashicorp.com"
    vaultstack = "${local.consul_join_tag_value}"
  }
}
