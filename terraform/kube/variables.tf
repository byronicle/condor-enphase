variable "zone" {
  type        = string
  description = "GCP zone for resources"
  default     = "us-west1-a"
}

variable "cluster_name" {
  type        = string
  description = "GKE cluster name"
  default     = "enphase-cluster"
}

variable "node_machine_type" {
  type        = string
  description = "Machine type for GKE nodes"
  default     = "e2-small"
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

variable "project_id" {
  type        = string
  description = "GCP project ID for the instance"
}

variable "region" {
  type        = string
  description = "GCP region for the instance"
  default     = "us-west1"
}

variable "ingestor_image" {
  type        = string
  description = "Docker image for the ingestor application"
  default     = "gcr.io/your-project/enphase-ingestor:latest"
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

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for resources"
  default     = "enphase"
}
