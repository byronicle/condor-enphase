variable "zone" {
  type        = string
  description = "GCP zone for the VM"
  default     = "us-west1-a"
}

variable "machine_type" {
  type        = string
  description = "Machine type for the VM"
  default     = "e2-micro"
}

variable "project_id" {
  type        = string
  description = "GCP project ID for the instance"
}

variable "region" {
  type        = string
  description = "GCP region for the instance"
  default     = "us-west1"
}

variable "repo_name" {
  type        = string
  description = "Cloud Source Repository name to clone in the VM"
}

// port for application HTTP ingress
variable "app_port" {
  type        = number
  description = "Port for HTTP ingress to the application"
  default     = 80
}

// GCP secrets variables
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
