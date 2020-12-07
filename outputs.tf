# Outputs

output "rancher_nodes" {
  value = [
  	for instance in flatten([[azurerm_linux_virtual_machine.rancher_nodes_master], [azurerm_linux_virtual_machine.rancher_nodes_worker], [azurerm_linux_virtual_machine.rancher_nodes_all]]): {
      public_ip  = instance.public_ip_address
      private_ip = instance.private_ip_address
      name       = instance.name
      roles      = split(",", instance.tags.K8sRoles)
      user       = var.node_username
      roles      = split(",", instance.tags.K8sRoles)

    }
  ]
  sensitive = true
}

output "tls_private_key" { value = tls_private_key.bootstrap_private_key.private_key_pem }

# ssh_key    = file(var.private_ssh_key)