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

// Secret inputs for infra module
variable "enphase_local_token" {
  type        = string
  description = "Enphase local token"
  sensitive   = true
}

variable "envoy_host" {
  type        = string
  description = "Envoy host"
  sensitive   = true
}

variable "ts_authkey" {
  type        = string
  description = "TS auth key"
  sensitive   = true
}

variable "influxdb_admin_password" {
  type        = string
  description = "InfluxDB admin password"
  sensitive   = true
}

variable "influxdb_admin_token" {
  type        = string
  description = "InfluxDB admin token"
  sensitive   = true
}
