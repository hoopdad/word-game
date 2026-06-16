resource "random_password" "runner_admin" {
  count   = var.enable_self_hosted_runner ? 1 : 0
  length  = 20
  special = true
}

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

resource "azurerm_linux_virtual_machine" "runner" {
  count                           = var.enable_self_hosted_runner ? 1 : 0
  name                            = "vm-runner-${local.spoke_prefix}"
  location                        = var.spoke_region
  resource_group_name             = azurerm_resource_group.spoke.name
  size                            = var.runner_vm_size
  admin_username                  = "runneradmin"
  admin_password                  = random_password.runner_admin[0].result
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.runner[0].id]
  tags                            = local.common_tags

  identity {
    type         = "UserAssigned"
    identity_ids = [module.uami.resource_id]
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  depends_on = [
    azapi_resource.subnet_workload,
    azurerm_network_interface_security_group_association.runner
  ]
}
