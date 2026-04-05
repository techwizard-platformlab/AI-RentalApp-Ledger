package shared

import future.keywords.if

test_deny_prod_tagged_resource if {
  count(deny) > 0 with input as {
    "resource_changes": [{
      "address": "azurerm_resource_group.prod",
      "type": "azurerm_resource_group",
      "change": {
        "actions": ["create"],
        "after": {
          "location": "eastus",
          "tags": {"env": "prod", "project": "rentalapp", "owner": "team"}
        }
      }
    }]
  }
}

test_allow_dev_tagged_resource if {
  count(deny) == 0 with input as {
    "resource_changes": [{
      "address": "azurerm_resource_group.dev",
      "type": "azurerm_resource_group",
      "change": {
        "actions": ["create"],
        "after": {
          "location": "eastus",
          "tags": {"env": "dev", "project": "rentalapp", "owner": "team"}
        }
      }
    }]
  }
}

test_deny_too_many_public_ips if {
  count(deny) > 0 with input as {
    "resource_changes": [
      {"address": "azurerm_public_ip.ip1", "type": "azurerm_public_ip", "change": {"actions": ["create"], "after": {"location": "eastus", "tags": {"env": "dev", "project": "x", "owner": "y"}}}},
      {"address": "azurerm_public_ip.ip2", "type": "azurerm_public_ip", "change": {"actions": ["create"], "after": {"location": "eastus", "tags": {"env": "dev", "project": "x", "owner": "y"}}}},
      {"address": "azurerm_public_ip.ip3", "type": "azurerm_public_ip", "change": {"actions": ["create"], "after": {"location": "eastus", "tags": {"env": "dev", "project": "x", "owner": "y"}}}},
      {"address": "azurerm_public_ip.ip4", "type": "azurerm_public_ip", "change": {"actions": ["create"], "after": {"location": "eastus", "tags": {"env": "dev", "project": "x", "owner": "y"}}}}
    ]
  }
}
