// Root-level Terraform variables
variable "project_id" {
  type        = string
  description = "The GCP project ID"
}

variable "project_number" {
  type        = string
  description = "The GCP project number"
}

variable "region" {
  type        = string
  description = "The GCP region"
  default     = "us-west1"
}

variable "zone" {
  type        = string
  description = "The GCP zone"
  default     = "us-west1-a"
}

// Cloud Source Repository name for deploying the application
variable "repo_name" {
  type        = string
  description = "Cloud Source Repository name to provision and clone"
  default     = "condor-enphase-app"
}

// GitHub App installation ID
variable "installation_id" {
  type        = string
  description = "GitHub App installation ID"
}

// GitHub personal access token (PAT) for authentication
variable "github_pat" {
  type        = string
  description = "GitHub personal access token (PAT) for authentication"
}