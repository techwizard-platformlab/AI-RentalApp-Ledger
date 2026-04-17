locals {
  tags = {
    env     = var.environment
    project = var.project
    owner   = var.owner
    managed = "terraform"
  }

  acr_ready = var.acr_name != ""
}
