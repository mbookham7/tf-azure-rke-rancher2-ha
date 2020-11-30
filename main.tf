####################################
# resources                        #
####################################

# Create a resource group

resource "azurerm_resource_group" "resource_group" {
  name     = var.resource_group_name
  location = var.location
          } 

# Create a vnet using a module

module "vnet-main" {
  source  = "Azure/vnet/azurerm"
  version = "2.3.0"
  resource_group_name = azurerm_resource_group.resource_group.name
  vnet_name           = var.resource_group_name
  address_space       = var.vnet_cidr_range
  subnet_prefixes     = var.subnet_prefixes
  subnet_names        = var.subnet_names
  nsg_ids             = {}

  tags = {
    engineer = "mbookham"

  }
}

# Provisioning a Load balancer

resource "azurerm_public_ip" "load_balancer_public_ip" {
  name                = var.load_balancer_public_ip_name
  location            = var.location
  resource_group_name = azurerm_resource_group.resource_group.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_lb" "rancher_load_balancer" {
  name                = var.load_balancer_name
  location            = var.location
  resource_group_name = azurerm_resource_group.resource_group.name
  sku                 = "Standard"


  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.load_balancer_public_ip.id
  }
}

# Backend pool address
resource "azurerm_lb_backend_address_pool" "rancher-backendpool" {
 resource_group_name = azurerm_resource_group.resource_group.name
 loadbalancer_id     = azurerm_lb.rancher_load_balancer.id
 name                = "BackEndAddressPool"
}

# Load Balancing Rule

resource "azurerm_lb_rule" "lb-rule-80" {
  resource_group_name            = azurerm_resource_group.resource_group.name
  loadbalancer_id                = azurerm_lb.rancher_load_balancer.id
  name                           = "LBRule-80"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_id        = azurerm_lb_backend_address_pool.rancher-backendpool.id
  probe_id                       = azurerm_lb_probe.port-80-probe.id
}

resource "azurerm_lb_rule" "lb-rule-443" {
  resource_group_name            = azurerm_resource_group.resource_group.name
  loadbalancer_id                = azurerm_lb.rancher_load_balancer.id
  name                           = "LBRule-433"
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 443
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_id        = azurerm_lb_backend_address_pool.rancher-backendpool.id
  probe_id                       = azurerm_lb_probe.port-443-probe.id
}

# Health Probes

resource "azurerm_lb_probe" "port-80-probe" {
  resource_group_name = azurerm_resource_group.resource_group.name
  loadbalancer_id     = azurerm_lb.rancher_load_balancer.id
  name                = "http-running-probe"
  port                = 80
  protocol            = "Http"
  request_path        = "/healthz"
}

resource "azurerm_lb_probe" "port-443-probe" {
  resource_group_name = azurerm_resource_group.resource_group.name
  loadbalancer_id     = azurerm_lb.rancher_load_balancer.id
  name                = "https-running-probe"
  port                = 443
  protocol            = "https"
  request_path        = "/healthz"
}

# Create an availibility set

resource "azurerm_availability_set" "avset" {
  name                         = var.avset_name
  location                     = var.location
  resource_group_name          = azurerm_resource_group.resource_group.name
  platform_fault_domain_count  = 3
  platform_update_domain_count = 3
  managed                      = true
}

# Create an SSH key

resource "tls_private_key" "bootstrap_private_key" {
  algorithm = "RSA"
  rsa_bits = 4096
}


# Create three virtual machines

# node master

resource "azurerm_public_ip" "master_public_ip" {
  count               = var.node_master_count
  name                = "${var.prefix}-public-ip-master-${count.index}"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "network_interfaces_node_master" {
 count               = var.node_master_count
 name                = "${var.prefix}-nic-master-${count.index}"
 location            = var.location
 resource_group_name = azurerm_resource_group.resource_group.name

 ip_configuration {
   name                          = "nicConfiguration"
   subnet_id                     = module.vnet-main.vnet_subnets[0]
   private_ip_address_allocation = "dynamic"
   public_ip_address_id          = element(azurerm_public_ip.master_public_ip.*.id, count.index)
 }
}

resource "azurerm_network_interface_backend_address_pool_association" "backendpool_association_node_master" {
  count                   = var.node_master_count
  network_interface_id    = element(azurerm_network_interface.network_interfaces_node_master.*.id, count.index)
  ip_configuration_name   = "nicConfiguration"
  backend_address_pool_id = azurerm_lb_backend_address_pool.rancher-backendpool.id
}

resource "azurerm_virtual_machine" "rancher_nodes_master" {
 count                 = var.node_master_count
 name                  = "${var.prefix}-node-master-${count.index}"
 location              = var.location
 availability_set_id   = azurerm_availability_set.avset.id
 resource_group_name   = azurerm_resource_group.resource_group.name
 network_interface_ids = [element(azurerm_network_interface.network_interfaces_node_master.*.id, count.index)]
 vm_size               = "Standard_DS1_v2"

 # Uncomment this line to delete the OS disk automatically when deleting the VM
 delete_os_disk_on_termination = true

 storage_image_reference {
   publisher = "Canonical"
   offer     = "UbuntuServer"
   sku       = "18.04-LTS"
   version   = "latest"
 }

 storage_os_disk {
   name              = "masterosdisk${count.index}"
   caching           = "ReadWrite"
   create_option     = "FromImage"
   managed_disk_type = "Standard_LRS"
 }

os_profile {
        admin_username = "azureuser"
        computer_name  = "hostname"
    }

os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
            path     = "/home/azureuser/.ssh/authorized_keys"
            key_data = chomp(tls_private_key.bootstrap_private_key.public_key_openssh)
        }
}
}

# node worker

resource "azurerm_public_ip" "worker_public_ip" {
  count               = var.node_worker_count
  name                = "${var.prefix}-public-ip-worker-${count.index}"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "network_interfaces_node_worker" {
 count               = var.node_worker_count
 name                = "${var.prefix}-nic-worker-${count.index}"
 location            = var.location
 resource_group_name = azurerm_resource_group.resource_group.name

 ip_configuration {
   name                          = "nicConfiguration"
   subnet_id                     = module.vnet-main.vnet_subnets[0]
   private_ip_address_allocation = "dynamic"
   public_ip_address_id          = element(azurerm_public_ip.worker_public_ip.*.id, count.index)
 }
}

resource "azurerm_network_interface_backend_address_pool_association" "backendpool_association_node_worker" {
  count                   = var.node_worker_count
  network_interface_id    = element(azurerm_network_interface.network_interfaces_node_worker.*.id, count.index)
  ip_configuration_name   = "nicConfiguration"
  backend_address_pool_id = azurerm_lb_backend_address_pool.rancher-backendpool.id
}

resource "azurerm_virtual_machine" "rancher_nodes_worker" {
 count                 = var.node_worker_count
 name                  = "${var.prefix}-node-worker-${count.index}"
 location              = var.location
 availability_set_id   = azurerm_availability_set.avset.id
 resource_group_name   = azurerm_resource_group.resource_group.name
 network_interface_ids = [element(azurerm_network_interface.network_interfaces_node_worker.*.id, count.index)]
 vm_size               = "Standard_DS1_v2"

 # Uncomment this line to delete the OS disk automatically when deleting the VM
 delete_os_disk_on_termination = true

 storage_image_reference {
   publisher = "Canonical"
   offer     = "UbuntuServer"
   sku       = "18.04-LTS"
   version   = "latest"
 }

 storage_os_disk {
   name              = "workerosdisk${count.index}"
   caching           = "ReadWrite"
   create_option     = "FromImage"
   managed_disk_type = "Standard_LRS"
 }

os_profile {
        admin_username = "azureuser"
        computer_name  = "hostname"
    }

os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
            path     = "/home/azureuser/.ssh/authorized_keys"
            key_data = chomp(tls_private_key.bootstrap_private_key.public_key_openssh)
        }
}
}

# node all

resource "azurerm_public_ip" "all_public_ip" {
  count               = var.node_all_count
  name                = "${var.prefix}-public-ip-all-${count.index}"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "network_interfaces_node_all" {
 count               = var.node_all_count
 name                = "${var.prefix}-nic-all-${count.index}"
 location            = var.location
 resource_group_name = azurerm_resource_group.resource_group.name

 ip_configuration {
   name                          = "nicConfiguration"
   subnet_id                     = module.vnet-main.vnet_subnets[0]
   private_ip_address_allocation = "dynamic"
   public_ip_address_id          = element(azurerm_public_ip.all_public_ip.*.id, count.index)
 }
}

resource "azurerm_network_interface_backend_address_pool_association" "backendpool_association_node_all" {
  count                   = var.node_all_count
  network_interface_id    = element(azurerm_network_interface.network_interfaces_node_all.*.id, count.index)
  ip_configuration_name   = "nicConfiguration"
  backend_address_pool_id = azurerm_lb_backend_address_pool.rancher-backendpool.id
}

resource "azurerm_virtual_machine" "rancher_nodes_all" {
 count                 = var.node_all_count
 name                  = "${var.prefix}-node-all-${count.index}"
 location              = var.location
 availability_set_id   = azurerm_availability_set.avset.id
 resource_group_name   = azurerm_resource_group.resource_group.name
 network_interface_ids = [element(azurerm_network_interface.network_interfaces_node_all.*.id, count.index)]
 vm_size               = "Standard_DS1_v2"

 # Uncomment this line to delete the OS disk automatically when deleting the VM
 delete_os_disk_on_termination = true

 storage_image_reference {
   publisher = "Canonical"
   offer     = "UbuntuServer"
   sku       = "18.04-LTS"
   version   = "latest"
 }

 storage_os_disk {
   name              = "allosdisk${count.index}"
   caching           = "ReadWrite"
   create_option     = "FromImage"
   managed_disk_type = "Standard_LRS"
 }

os_profile {
        admin_username = "azureuser"
        computer_name  = "hostname"
    }

os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
            path     = "/home/azureuser/.ssh/authorized_keys"
            key_data = chomp(tls_private_key.bootstrap_private_key.public_key_openssh)
        }
}
}