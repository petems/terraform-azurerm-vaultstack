data "http" "current_ip" {
  url = "http://ipv4.icanhazip.com"
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "vaultstack" {
  name     = "${var.resource_group}"
  location = "${var.location}"

  tags {
    name      = "${var.owner}"
    ttl       = "13"
    owner     = "psouter@hashicorp.com"
    vaultstack = "${local.consul_join_tag_value}"
  }
}

resource "azurerm_availability_set" "consul_avail_set" {
  name                         = "${var.stack_prefix}-consul-aval-set"
  location                     = "${var.location}"
  resource_group_name          = "${azurerm_resource_group.vaultstack.name}"
  platform_fault_domain_count  = 3
  platform_update_domain_count = 3
  managed                      = true

  tags {
    name      = "${var.owner}"
    ttl       = "13"
    owner     = "psouter@hashicorp.com"
    vaultstack = "${local.consul_join_tag_value}"
  }
}

resource "azurerm_availability_set" "vault_avail_set" {
  name                         = "${var.stack_prefix}-vault-aval-set"
  location                     = "${var.location}"
  resource_group_name          = "${azurerm_resource_group.vaultstack.name}"
  platform_fault_domain_count  = 3
  platform_update_domain_count = 3
  managed                      = true

  tags {
    name      = "${var.owner}"
    ttl       = "13"
    owner     = "psouter@hashicorp.com"
    vaultstack = "${local.consul_join_tag_value}"
  }
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.virtual_network_name}"
  location            = "${azurerm_resource_group.vaultstack.location}"
  address_space       = ["${var.address_space}"]
  resource_group_name = "${azurerm_resource_group.vaultstack.name}"

  tags {
    name      = "${var.owner}"
    ttl       = "13"
    owner     = "psouter@hashicorp.com"
    vaultstack = "${local.consul_join_tag_value}"
  }
}

resource "azurerm_subnet" "subnet" {
  name                 = "${var.stack_prefix}subnet"
  virtual_network_name = "${azurerm_virtual_network.vnet.name}"
  resource_group_name  = "${azurerm_resource_group.vaultstack.name}"
  address_prefix       = "${var.subnet_prefix}"
}

resource "azurerm_network_security_group" "vaultstack-sg" {
  name                = "${var.stack_prefix}-sg"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.vaultstack.name}"

  tags {
    name      = "${var.owner}"
    ttl       = "13"
    owner     = "psouter@hashicorp.com"
    vaultstack = "${local.consul_join_tag_value}"
  }

  security_rule {
    name                       = "vaultstack-443"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "${chomp(data.http.current_ip.body)}/32"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "vaultstack-8800"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8800"
    source_address_prefix      = "${chomp(data.http.current_ip.body)}/32"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "vaultstack-ssh"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "${chomp(data.http.current_ip.body)}/32"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "vaultstack-http"
    priority                   = 103
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "${chomp(data.http.current_ip.body)}/32"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "vaultstack-run"
    priority                   = 104
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8000-8800"
    source_address_prefix      = "${chomp(data.http.current_ip.body)}/32"
    destination_address_prefix = "*"
  }

}
