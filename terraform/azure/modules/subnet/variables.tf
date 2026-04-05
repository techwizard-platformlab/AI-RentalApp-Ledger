variable "environment"         { type = string }
variable "location_short"      { type = string }
variable "resource_group_name" { type = string }
variable "vnet_name"           { type = string }
variable "subnets"             { type = map(string) } # name → CIDR
