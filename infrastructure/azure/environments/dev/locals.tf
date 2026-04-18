locals {
  tags = {
    env     = var.environment
    project = var.project
    owner   = var.owner
    managed = "terraform"
  }

}
