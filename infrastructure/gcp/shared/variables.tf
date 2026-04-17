variable "project_id" {
  description = "GCP project ID — injected via TF_VAR_project_id (GitHub Secret: GCP_PROJECT_ID)"
  type        = string
  sensitive   = true
}
