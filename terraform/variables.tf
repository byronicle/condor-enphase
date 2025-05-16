// Root-level Terraform variables
variable "project_id" {
  type        = string
  description = "The GCP project ID"
}

variable "region" {
  type        = string
  description = "The GCP region"
}

variable "zone" {
  type        = string
  description = "The GCP zone"
}

// Cloud Source Repository name for deploying the application
variable "repo_name" {
  type        = string
  description = "Cloud Source Repository name to provision and clone"
  default     = "condor-enphase-app"
}

// email of the service account to attach to the VM for Cloud Source access
variable "service_account_email" {
  type        = string
  description = "GCP service account email to attach to the compute instance"
}
