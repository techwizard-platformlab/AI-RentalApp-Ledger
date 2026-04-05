variable "environment" {
  type = string
}

variable "app_name" {
  type    = string
  default = "rentalapp-ledger-oidc"
}

variable "github_org" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "resource_group_id" {
  type = string
}
