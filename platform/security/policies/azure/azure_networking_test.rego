package azure

import future.keywords.if

test_deny_public_vnet_cidr if {
  count(deny) > 0 with input as {
    "resource_changes": [{
      "address": "azurerm_virtual_network.main",
      "type": "azurerm_virtual_network",
      "change": {
        "actions": ["create"],
        "after": {
          "address_space": ["8.8.8.0/24"],
          "tags": {"env": "dev", "project": "rentalapp", "owner": "team"},
          "location": "eastus"
        }
      }
    }]
  }
}

test_allow_private_vnet_cidr if {
  count(deny) == 0 with input as {
    "resource_changes": [{
      "address": "azurerm_virtual_network.main",
      "type": "azurerm_virtual_network",
      "change": {
        "actions": ["create"],
        "after": {
          "address_space": ["10.0.0.0/16"],
          "tags": {"env": "dev", "project": "rentalapp", "owner": "team"},
          "location": "eastus"
        }
      }
    }]
  }
}

test_deny_nsg_allow_all if {
  count(deny) > 0 with input as {
    "resource_changes": [{
      "address": "azurerm_network_security_rule.allow_all",
      "type": "azurerm_network_security_rule",
      "change": {
        "actions": ["create"],
        "after": {
          "direction": "Inbound",
          "access": "Allow",
          "source_address_prefix": "0.0.0.0/0",
          "destination_port_range": "*",
          "location": "eastus",
          "tags": {"env": "dev", "project": "rentalapp", "owner": "team"}
        }
      }
    }]
  }
}
