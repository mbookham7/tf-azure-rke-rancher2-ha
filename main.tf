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

resource "azurerm_network_security_group" "rke_nsg" {
  name                = var.nsg_name
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  security_rule {
    name                       = "allow_all"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
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

resource "azurerm_network_interface_security_group_association" "nisga-master" {
  count                     = var.node_master_count
  network_interface_id      = azurerm_network_interface.network_interfaces_node_master[count.index].id
  network_security_group_id = var.security_group_id
}

resource "azurerm_linux_virtual_machine" "rancher_nodes_master" {
  count                 = var.node_master_count
  name                  = "${var.prefix}-node-master-${count.index}"
  admin_username        = var.node_username
  computer_name         = "${var.prefix}-node-master-${count.index}"
  location              = var.location
  availability_set_id   = azurerm_availability_set.avset.id
  resource_group_name   = azurerm_resource_group.resource_group.name
  network_interface_ids = [element(azurerm_network_interface.network_interfaces_node_master.*.id, count.index)]
  size                  = var.size

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  os_disk {
    name                 = "master-osdisk-${count.index}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.node_username
    public_key = tls_private_key.bootstrap_private_key.public_key_openssh
  }

  tags = {
    Name     = "${var.prefix}-node-master-${count.index}"
    K8sRoles = "controlplane,etcd"
  }
  

  provisioner "remote-exec" {
    inline = [
      "curl -sL https://releases.rancher.com/install-docker/${var.docker_version}.sh | sudo sh",
      "sudo usermod -aG docker ${var.node_username}"
    ]
    connection {
      host        = self.public_ip_address
      type        = "ssh"
      user        = var.node_username
      private_key = tls_private_key.bootstrap_private_key.private_key_pem
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

resource "azurerm_network_interface_security_group_association" "nisga-worker" {
  count                     = var.node_master_count
  network_interface_id      = azurerm_network_interface.network_interfaces_node_worker[count.index].id
  network_security_group_id = var.security_group_id
}

resource "azurerm_linux_virtual_machine" "rancher_nodes_worker" { 
  count                 = var.node_worker_count
  name                  = "${var.prefix}-node--worker${count.index}"
  admin_username        = var.node_username
  computer_name         = "${var.prefix}-node-worker-${count.index}"
  location              = var.location
  availability_set_id   = azurerm_availability_set.avset.id
  resource_group_name   = azurerm_resource_group.resource_group.name
  network_interface_ids = [element(azurerm_network_interface.network_interfaces_node_worker.*.id, count.index)]
  size                  = var.size

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  os_disk {
    name                 = "worker-osdisk-${count.index}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.node_username
    public_key = tls_private_key.bootstrap_private_key.public_key_openssh
  }

  tags = {
    Name     = "${var.prefix}-node-worker-${count.index}"
    K8sRoles = "worker"
  }
  

  provisioner "remote-exec" {
    inline = [
      "curl -sL https://releases.rancher.com/install-docker/${var.docker_version}.sh | sudo sh",
      "sudo usermod -aG docker ${var.node_username}"
    ]
    connection {
      host        = self.public_ip_address
      type        = "ssh"
      user        = var.node_username
      private_key = tls_private_key.bootstrap_private_key.private_key_pem
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

resource "azurerm_network_interface_security_group_association" "nisga-all" {
  count                     = var.node_master_count
  network_interface_id      = azurerm_network_interface.network_interfaces_node_all[count.index].id
  network_security_group_id = var.security_group_id
}

resource "azurerm_linux_virtual_machine" "rancher_nodes_all" {
  count                 = var.node_all_count
  name                  = "${var.prefix}-node-all-${count.index}"
  admin_username        = var.node_username
  computer_name         = "${var.prefix}-node-all-${count.index}"
  location              = var.location
  availability_set_id   = azurerm_availability_set.avset.id
  resource_group_name   = azurerm_resource_group.resource_group.name
  network_interface_ids = [element(azurerm_network_interface.network_interfaces_node_all.*.id, count.index)]
  size                  = var.size  

   source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  os_disk {
    name                 = "all-osdisk-${count.index}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.node_username
    public_key = tls_private_key.bootstrap_private_key.public_key_openssh
  }

  tags = {
    Name     = "${var.prefix}-node-all-${count.index}"
    K8sRoles = "controlplane,etcd,worker"
  }
  

  provisioner "remote-exec" {
    inline = [
      "curl -sL https://releases.rancher.com/install-docker/${var.docker_version}.sh | sudo sh",
      "sudo usermod -aG docker ${var.node_username}"
    ]
    connection {
      host        = self.public_ip_address
      type        = "ssh"
      user        = var.node_username
      private_key = tls_private_key.bootstrap_private_key.private_key_pem
    }
  }
}