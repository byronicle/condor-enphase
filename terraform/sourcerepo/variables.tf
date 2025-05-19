// Root-level Terraform variables
variable "project_id" {
  type        = string
  description = "The GCP project ID"
}

variable "project_number" {
  type        = string
  description = "The GCP project number"
}

// Cloud Source Repository name for deploying the application
variable "repo_name" {
  type        = string
  description = "Cloud Source Repository name to provision and clone"
  default     = "condor-enphase-app"
}

// GitHub connection name
variable "connection_name" {
  type        = string
  description = "Name of the GitHub connection"
  default     = "github-connection"
} 

// GitHub personal access token (PAT) for authentication
variable "github_pat" {
  type        = string
  description = "GitHub personal access token (PAT) for authentication"
}

// Secret ID for the GitHub token
variable "secret_id" {
  type        = string
  description = "Secret ID for the GitHub token"
  default     = "github-token"
}

// GitHub App installation ID
variable "installation_id" {
  type        = string
  description = "GitHub App installation ID"
}

// Region for the GitHub connection
variable "region" {
  type        = string
  description = "Region for the GitHub connection"
  default     = "us-west1"
}