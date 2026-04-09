package azure

import future.keywords.in
import future.keywords.if

# ─────────────────────────────────────────────────────────────────────────────
# Helper: resources being created or updated
# ─────────────────────────────────────────────────────────────────────────────
net_resources[r] {
  r := input.resource_changes[_]
  r.change.actions[_] in ["create", "update"]
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny VNet CIDR outside 10.0.0.0/8 private range
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] {
  r := net_resources[_]
  r.type == "azurerm_virtual_network"
  cidr := r.change.after.address_space[_]
  not startswith(cidr, "10.")
  not startswith(cidr, "172.16.")
  not startswith(cidr, "172.17.")
  not startswith(cidr, "172.18.")
  not startswith(cidr, "172.19.")
  not startswith(cidr, "172.20.")
  not startswith(cidr, "172.21.")
  not startswith(cidr, "172.22.")
  not startswith(cidr, "172.23.")
  not startswith(cidr, "172.24.")
  not startswith(cidr, "172.25.")
  not startswith(cidr, "172.26.")
  not startswith(cidr, "172.27.")
  not startswith(cidr, "172.28.")
  not startswith(cidr, "172.29.")
  not startswith(cidr, "172.30.")
  not startswith(cidr, "172.31.")
  not startswith(cidr, "192.168.")
  msg := sprintf(
    "[NETWORK] VNet '%s' uses public CIDR '%s'. Only private RFC-1918 ranges allowed (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16).",
    [r.address, cidr]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny NSG with inbound allow-all rule (0.0.0.0/0 on all ports)
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] {
  r := net_resources[_]
  r.type == "azurerm_network_security_rule"
  upper(r.change.after.direction) == "INBOUND"
  upper(r.change.after.access) == "ALLOW"
  r.change.after.source_address_prefix == "0.0.0.0/0"
  r.change.after.destination_port_range == "*"
  msg := sprintf(
    "[SECURITY] NSG rule '%s' allows ALL inbound traffic from 0.0.0.0/0 on all ports. This is too permissive.",
    [r.address]
  )
}

# Also check inline security_rules on azurerm_network_security_group
deny[msg] {
  r := net_resources[_]
  r.type == "azurerm_network_security_group"
  rule := r.change.after.security_rule[_]
  upper(rule.direction) == "Inbound"
  upper(rule.access) == "Allow"
  rule.source_address_prefix == "0.0.0.0/0"
  rule.destination_port_range == "*"
  msg := sprintf(
    "[SECURITY] NSG '%s' has an allow-all inbound rule. Restrict to specific ports and sources.",
    [r.address]
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# RULE: Deny subnet without NSG association
# ─────────────────────────────────────────────────────────────────────────────
deny[msg] {
  r := net_resources[_]
  r.type == "azurerm_subnet"
  # NSG can be associated via azurerm_subnet_network_security_group_association
  # Check if there's no matching association resource for this subnet
  subnet_id := r.change.after.id
  not subnet_has_nsg_association(subnet_id)
  msg := sprintf(
    "[SECURITY] Subnet '%s' has no NSG association. All subnets must be protected by an NSG.",
    [r.address]
  )
}

subnet_has_nsg_association(subnet_id) {
  assoc := input.resource_changes[_]
  assoc.type == "azurerm_subnet_network_security_group_association"
  assoc.change.after.subnet_id == subnet_id
}

# Warn: no NSG association found in plan at all (may be existing)
warn[msg] {
  r := net_resources[_]
  r.type == "azurerm_subnet"
  not r.change.after.network_security_group_id
  msg := sprintf(
    "[WARN] Subnet '%s': verify it has an NSG associated (not visible in this plan scope).",
    [r.address]
  )
}
