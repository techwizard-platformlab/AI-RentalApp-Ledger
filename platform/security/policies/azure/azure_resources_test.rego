package azure

import future.keywords.if

# ─────────────────────────────────────────────────────────────────────────────
# Test: AKS node count > 2 triggers deny
# ─────────────────────────────────────────────────────────────────────────────
test_deny_aks_too_many_nodes if {
  count(deny) > 0 with input as {
    "resource_changes": [{
      "address": "module.aks.azurerm_kubernetes_cluster.main",
      "type": "azurerm_kubernetes_cluster",
      "change": {
        "actions": ["create"],
        "after": {
          "location": "eastus",
          "tags": {"env": "dev", "project": "rentalapp", "owner": "team"},
          "default_node_pool": [{"node_count": 3, "vm_size": "Standard_B2s"}]
        }
      }
    }]
  }
}

test_allow_aks_two_nodes if {
  count(deny) == 0 with input as {
    "resource_changes": [{
      "address": "module.aks.azurerm_kubernetes_cluster.main",
      "type": "azurerm_kubernetes_cluster",
      "change": {
        "actions": ["create"],
        "after": {
          "location": "eastus",
          "tags": {"env": "dev", "project": "rentalapp", "owner": "team"},
          "default_node_pool": [{"node_count": 2, "vm_size": "Standard_B2s"}]
        }
      }
    }]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Test: unapproved VM size triggers deny
# ─────────────────────────────────────────────────────────────────────────────
test_deny_unapproved_vm_size if {
  count(deny) > 0 with input as {
    "resource_changes": [{
      "address": "module.aks.azurerm_kubernetes_cluster.main",
      "type": "azurerm_kubernetes_cluster",
      "change": {
        "actions": ["create"],
        "after": {
          "location": "eastus",
          "tags": {"env": "dev", "project": "rentalapp", "owner": "team"},
          "default_node_pool": [{"node_count": 1, "vm_size": "Standard_D4s_v3"}]
        }
      }
    }]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Test: ACR Premium SKU triggers deny
# ─────────────────────────────────────────────────────────────────────────────
test_deny_acr_premium if {
  count(deny) > 0 with input as {
    "resource_changes": [{
      "address": "azurerm_container_registry.main",
      "type": "azurerm_container_registry",
      "change": {
        "actions": ["create"],
        "after": {
          "location": "eastus",
          "sku": "Premium",
          "tags": {"env": "dev", "project": "rentalapp", "owner": "team"}
        }
      }
    }]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Test: missing required tag triggers deny
# ─────────────────────────────────────────────────────────────────────────────
test_deny_missing_tags if {
  count(deny) > 0 with input as {
    "resource_changes": [{
      "address": "azurerm_resource_group.main",
      "type": "azurerm_resource_group",
      "change": {
        "actions": ["create"],
        "after": {
          "location": "eastus",
          "tags": {"env": "dev"}
        }
      }
    }]
  }
}
