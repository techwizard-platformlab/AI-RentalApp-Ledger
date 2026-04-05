variable "environment"         { type = string }
variable "location"            { type = string }
variable "location_short"      { type = string }
variable "resource_group_name" { type = string }
variable "subnet_ids"          { type = map(string); default = {} } # name → subnet ID to associate
variable "tags"                { type = map(string); default = {} }
