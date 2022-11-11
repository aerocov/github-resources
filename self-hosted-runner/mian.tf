terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.19.1"
    }

    random = {
      source  = "hashicorp/random"
      version = "~>3.4"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~>4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  prefix = "ga-runner"
  tags = {
    platform = "ga-runner"
  }
  custom_data = <<EOF
        #cloud-config
        runcmd:
        - [mkdir, '/actions-runner']
        - cd /actions-runner
        - [curl, -o, 'actions-runner.tar.gz', -L, 'https://github.com/actions/runner/releases/download/v2.297.0/actions-runner-linux-x64-2.297.0.tar.gz']
        - [tar, xzf, './actions-runner.tar.gz']
        - [chmod, -R, 777, '/actions-runner']
        - [su, ${var.admin_user}, -c, '/actions-runner/config.sh --url https://github.com/dbc-tech --token ${var.registration_token}']
        - ./svc.sh install
        - ./svc.sh start
        - [rm, '/actions-runner/actions-runner.tar.gz']
        - curl -fsSL https://get.docker.com -o get-docker.sh
        - sh get-docker.sh
        - curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
        - shutdown -r
        EOF
}

resource "azurerm_resource_group" "rg" {
  name     = "${local.prefix}-resources"
  location = "West US 2"
  tags     = local.tags
}

resource "azurerm_virtual_network" "vn" {
  name                = "${local.prefix}-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "sb" {
  name                 = "${local.prefix}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vn.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "public_ip" {
  name                = "${local.prefix}-public-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "nic" {
  name                = "${local.prefix}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "${local.prefix}-nic_configuration"
    subnet_id                     = azurerm_subnet.sb.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

resource "azurerm_network_security_group" "sg" {
  name                = "${local.prefix}-sg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "sg_nic" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.sg.id
}

resource "random_id" "random_id" {
  keepers = {
    resource_group = azurerm_resource_group.rg.name
  }

  byte_length = 8
}

resource "azurerm_storage_account" "sta" {
  name                     = "diag${random_id.random_id.hex}"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_linux_virtual_machine" "vm_runner" {
  name                            = "${local.prefix}-vm"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  network_interface_ids           = [azurerm_network_interface.nic.id]
  size                            = "Standard_B2ms"
  custom_data                     = base64encode(local.custom_data)
  computer_name                   = "ga-runner"
  admin_username                  = var.admin_user
  disable_password_authentication = true

  os_disk {
    name                 = "${local.prefix}-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  admin_ssh_key {
    username   = var.admin_user
    public_key = tls_private_key.ssh_key.public_key_openssh
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.sta.primary_blob_endpoint
  }
}
