# terraform-azurerm-vaultstack

**What is this?**

This is a Terraform repo to help create Vault cluster deployed according to HashiCorp's recomended architecture, within Azure.

Image here:

![Architecture Image](https://learn.hashicorp.com/assets/images/vault-ref-arch-2.png)

> Taken from [https://learn.hashicorp.com/vault/operations/ops-deployment-guide](https://learn.hashicorp.com/vault/operations/ops-deployment-guide)

We have 5 Consul servers because Consul is the backend to Vault, so we want to match the fault tolerance between Consul and Vault.

A vault cluster of 3 has a 2 server tolerance. A consul server of 3 only has a 1 fault tolerance. So we need 5 Consul servers to match Vault's 2 server tolerance.

More detail here: [https://www.consul.io/docs/internals/consensus.html#deployment-table](https://www.consul.io/docs/internals/consensus.html#deployment-table)

In summary this code does the following:

* 3 Vault Servers with Consul clients
  * Deployed within a dedicated avaliablity set for Vault
  * A load balancer set to probe which is the active Vault and return that as a dedicated loadbalancer entry
  * Azure Cloud autounseal pre-setup
* 5 Consul Servers
  * Deployed within a dedicated Consul avaliablity set
  * Discovery done by cloud tagging

Communication between Vault and Consul configured with self-signed certificates generated by Terraform.

## Preparation

* Set up `AZURE_` environmental variables
* Generate TLS self-signed certificates by running `terraform apply` in the `tls_certificates` folder
* Let Terraform run
* At the end, wait a few minutes as the cloud-init scripts sometimes dont complete before Terraform finishes
* Initialize the Vault instances either on the command-line or in the Vault web GUI

## Work in Progress

* It is not 100% 1-to-1 with our documentation currently, and is still being actively worked on.
* Currently, the main things it is missing:
  * Vault needs an ACL setup created for Consul

Because of this WIP nature, fFor intial deployment, the security groups are setup to only allow access from the IP of the instance that Terraform is running from:

```hcl
data "http" "current_ip" {
  url = "http://ipv4.icanhazip.com"
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
```

This is so the deployment and architecture can be checked before a full deployment occurs.
