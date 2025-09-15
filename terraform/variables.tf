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

// Kubernetes cluster configuration
variable "cluster_name" {
  type        = string
  description = "GKE cluster name"
  default     = "enphase-cluster"
}

variable "node_machine_type" {
  type        = string
  description = "Machine type for GKE nodes"
  default     = "e2-micro"
}

variable "node_disk_size" {
  type        = number
  description = "Disk size in GB for GKE nodes"
  default     = 20
}

variable "use_spot_instances" {
  type        = bool
  description = "Use spot instances for cost savings (may cause interruptions)"
  default     = false
}

variable "storage_class" {
  type        = string
  description = "Kubernetes storage class for persistent volumes"
  default     = "standard"
}

variable "influxdb_storage_size" {
  type        = string
  description = "Storage size for InfluxDB data"
  default     = "10Gi"
}

variable "grafana_storage_size" {
  type        = string
  description = "Storage size for Grafana data"
  default     = "5Gi"
}

variable "ingestor_image" {
  type        = string
  description = "Docker image for the ingestor application (e.g., gcr.io/your-project-id/enphase-ingestor:latest)"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for resources"
  default     = "enphase"
}

// Secret inputs for kube module
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

variable "tailscale_oauth_client_id" {
  type        = string
  description = "Tailscale OAuth client ID for Kubernetes operator"
  sensitive   = true
}

variable "tailscale_oauth_client_secret" {
  type        = string
  description = "Tailscale OAuth client secret for Kubernetes operator"
  sensitive   = true
}

