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