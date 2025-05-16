// Root-level Terraform variables
variable "project_id" {
  type        = string
  description = "The GCP project ID"
}

// Cloud Source Repository name for deploying the application
variable "repo_name" {
  type        = string
  description = "Cloud Source Repository name to provision and clone"
  default     = "condor-enphase-app"
}
