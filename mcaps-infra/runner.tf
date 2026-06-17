resource "azurerm_network_security_group" "runner" {
  count               = var.enable_self_hosted_runner ? 1 : 0
  name                = "nsg-runner-${local.spoke_prefix}"
  location            = var.spoke_region
  resource_group_name = azurerm_resource_group.spoke.name
  tags                = local.common_tags
}

resource "azurerm_network_security_rule" "runner_deny_all_inbound" {
  count                       = var.enable_self_hosted_runner ? 1 : 0
  name                        = "Deny-All-Inbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.spoke.name
  network_security_group_name = azurerm_network_security_group.runner[0].name
}

resource "azurerm_network_security_rule" "runner_allow_vnet_outbound" {
  count                       = var.enable_self_hosted_runner ? 1 : 0
  name                        = "Allow-VNet-Outbound"
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = azurerm_resource_group.spoke.name
  network_security_group_name = azurerm_network_security_group.runner[0].name
}

resource "azurerm_network_security_rule" "runner_allow_https_outbound" {
  count                       = var.enable_self_hosted_runner ? 1 : 0
  name                        = "Allow-HTTPS-Outbound"
  priority                    = 110
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "*"
  destination_address_prefix  = "Internet"
  resource_group_name         = azurerm_resource_group.spoke.name
  network_security_group_name = azurerm_network_security_group.runner[0].name
}

resource "azurerm_network_security_rule" "runner_allow_http_outbound" {
  count                       = var.enable_self_hosted_runner ? 1 : 0
  name                        = "Allow-HTTP-Outbound"
  priority                    = 120
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "*"
  destination_address_prefix  = "Internet"
  resource_group_name         = azurerm_resource_group.spoke.name
  network_security_group_name = azurerm_network_security_group.runner[0].name
}

resource "azurerm_network_security_rule" "runner_deny_all_outbound" {
  count                       = var.enable_self_hosted_runner ? 1 : 0
  name                        = "Deny-All-Outbound"
  priority                    = 4096
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.spoke.name
  network_security_group_name = azurerm_network_security_group.runner[0].name
}

resource "azurerm_network_interface" "runner" {
  count               = var.enable_self_hosted_runner ? 1 : 0
  name                = "nic-runner-${local.spoke_prefix}"
  location            = var.spoke_region
  resource_group_name = azurerm_resource_group.spoke.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "ipconfig1"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azapi_resource.subnet_workload.id
    primary                       = true
  }

  depends_on = [azapi_resource.subnet_workload]
}

resource "azurerm_network_interface_security_group_association" "runner" {
  count                     = var.enable_self_hosted_runner ? 1 : 0
  network_interface_id      = azurerm_network_interface.runner[0].id
  network_security_group_id = azurerm_network_security_group.runner[0].id
}

resource "azurerm_route_table" "runner" {
  count               = var.enable_self_hosted_runner ? 1 : 0
  name                = "rt-runner-${local.spoke_prefix}"
  location            = var.spoke_region
  resource_group_name = azurerm_resource_group.spoke.name
  tags                = local.common_tags
}

resource "azurerm_route" "runner_default_internet" {
  count               = var.enable_self_hosted_runner ? 1 : 0
  name                = "default-internet"
  resource_group_name = azurerm_resource_group.spoke.name
  route_table_name    = azurerm_route_table.runner[0].name
  address_prefix      = "0.0.0.0/0"
  next_hop_type       = "Internet"
}

resource "azurerm_subnet_route_table_association" "runner" {
  count          = var.enable_self_hosted_runner ? 1 : 0
  subnet_id      = azapi_resource.subnet_workload.id
  route_table_id = azurerm_route_table.runner[0].id
}

resource "azurerm_public_ip" "runner_nat" {
  count               = var.enable_self_hosted_runner ? 1 : 0
  name                = "pip-nat-runner-${local.spoke_prefix}"
  location            = var.spoke_region
  resource_group_name = azurerm_resource_group.spoke.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_nat_gateway" "runner" {
  count                   = var.enable_self_hosted_runner ? 1 : 0
  name                    = "nat-runner-${local.spoke_prefix}"
  location                = var.spoke_region
  resource_group_name     = azurerm_resource_group.spoke.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = local.common_tags
}

resource "azurerm_nat_gateway_public_ip_association" "runner" {
  count                = var.enable_self_hosted_runner ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.runner[0].id
  public_ip_address_id = azurerm_public_ip.runner_nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "runner" {
  count          = var.enable_self_hosted_runner ? 1 : 0
  subnet_id      = azapi_resource.subnet_workload.id
  nat_gateway_id = azurerm_nat_gateway.runner[0].id
}
