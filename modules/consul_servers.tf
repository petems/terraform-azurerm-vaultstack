
data "template_file" "consul_servers_script" {
  depends_on = ["azurerm_public_ip.consul-servers-pip", "azurerm_key_vault.vaultstack"]
  count      = "${var.consul_servers}"

  template = "${join("\n", list(
    file("${path.module}/templates/shared/base.sh"),
    file("${path.module}/templates/server/consul.sh"),
    file("${path.module}/templates/shared/cleanup.sh"),
  ))}"

  vars {
    hostname      = "${var.hostname}-consul-servers-${count.index}"
    private_ip    = "${element(azurerm_network_interface.consul-servers-nic.*.private_ip_address, count.index)}"
    public_ip     = "${element(azurerm_public_ip.consul-servers-pip.*.ip_address, count.index)}"

    kmsvaultname  = "${azurerm_key_vault.vaultstack.name}"
    kmskeyname    = "${azurerm_key_vault_key.vaultstack.name}"

    subscription_id = "${var.subscription}"

    tenant_id     = "${var.tenant}"
    client_id     = "${var.client_id}"
    client_secret = "${var.client_secret}"
    object_id     = "${azurerm_user_assigned_identity.vaultstack.principal_id}"
    fqdn          = "${element(azurerm_public_ip.consul-servers-pip.*.fqdn, count.index)}"
    node_name     = "${var.hostname}-consul-servers-${count.index}"
    me_ca         = "${var.ca_cert_pem}"
    me_cert       = "${element(tls_locally_signed_cert.consul_servers.*.cert_pem, count.index)}"
    me_key        = "${element(tls_private_key.consul_servers.*.private_key_pem, count.index)}"

    # Consul
    consul_url            = "${var.consul_url}"
    consul_gossip_key     = "${base64encode(random_id.consul_gossip_key.hex)}"
    consul_join_tag_key   = "ConsulJoin"
    consul_join_tag_name  = "vaultstack"
    consul_join_tag_value = "${local.consul_join_tag_value}"
    consul_master_token   = "${random_id.consul_master_token.hex}"
    consul_servers        = "${var.consul_servers}"
  }
}

# Gzip cloud-init config
data "template_cloudinit_config" "consul_servers_cloudinit" {
  count = "${var.consul_servers}"

  gzip          = true
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content      = "${element(data.template_file.consul_servers_script.*.rendered, count.index)}"
  }
}

# Every Azure Virtual Machine comes with a private IP address. You can also
# optionally add a public IP address for Internet-facing applications and
# demo environments like this one.
resource "azurerm_public_ip" "consul-servers-pip" {
  count               = "${var.consul_servers}"
  name                = "${var.stack_prefix}-consul-servers-ip-${count.index}"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.vaultstack.name}"
  allocation_method   = "Static"
  domain_name_label   = "${var.hostname}-consul-servers-${count.index}"
  sku                 = "Standard"

  tags {
    name      = "Peter Souter"
    ttl       = "13"
    owner     = "psouter@hashicorp.com"
    vaultstack = "${local.consul_join_tag_value}"
  }
}

resource "azurerm_network_interface" "consul-servers-nic" {
  count                     = "${var.consul_servers}"
  name                      = "${var.stack_prefix}-consul-servers-nic-${count.index}"
  location                  = "${var.location}"
  resource_group_name       = "${azurerm_resource_group.vaultstack.name}"
  network_security_group_id = "${azurerm_network_security_group.vaultstack-sg.id}"

  ip_configuration {
    name                          = "${var.stack_prefix}-${count.index}-ipconfig"
    subnet_id                     = "${azurerm_subnet.subnet.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${element(azurerm_public_ip.consul-servers-pip.*.id, count.index)}"
  }

  tags {
    name      = "Peter Souter"
    ttl       = "13"
    owner     = "psouter@hashicorp.com"
    vaultstack = "${local.consul_join_tag_value}"
  }
}

# And finally we build our vaultstack servers. This is a standard Ubuntu instance.
resource "azurerm_virtual_machine" "consul_servers" {
  count               = "${var.consul_servers}"
  name                = "${var.hostname}-consul-servers-${count.index}"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.vaultstack.name}"
  vm_size             = "${var.vm_size}"
  availability_set_id = "${azurerm_availability_set.consul_avail_set.id}"

  network_interface_ids         = ["${element(azurerm_network_interface.consul-servers-nic.*.id, count.index)}"]
  delete_os_disk_on_termination = "true"

  storage_image_reference {
    publisher = "${var.image_publisher}"
    offer     = "${var.image_offer}"
    sku       = "${var.image_sku}"
    version   = "${var.image_version}"
  }

  storage_os_disk {
    name              = "${var.hostname}-sever-osdisk-${count.index}"
    managed_disk_type = "Standard_LRS"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    disk_size_gb      = "${var.storage_disk_size}"
  }

  os_profile {
    computer_name  = "${var.hostname}-consul-servers-${count.index}"
    admin_username = "${var.admin_username}"
    admin_password = "${var.admin_password}"
    custom_data    = "${element(data.template_cloudinit_config.consul_servers_cloudinit.*.rendered, count.index)}"
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
