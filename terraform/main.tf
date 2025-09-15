
# =============================================================================
# Enphase Solar Monitoring Infrastructure
# =============================================================================
#
# This Terraform configuration deploys a complete solar monitoring solution 
# on Google Cloud Platform using Google Kubernetes Engine (GKE).
#
# Architecture Overview:
# ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
# │   Home Network  │    │   GKE Cluster    │    │     Users       │
# │                 │    │                  │    │                 │
# │ Enphase Envoy ◄─┼────┼─► Ingestor       │    │ Grafana Access  │
# │ (192.168.1.x)   │    │      ▼           │    │ via Tailscale   │
# │                 │    │   InfluxDB       │    │                 │
# │ Tailscale       │    │      ▼           │    │                 │
# │ Subnet Router   │    │   Grafana ◄──────┼────┤                 │
# └─────────────────┘    └──────────────────┘    └─────────────────┘
#
# Key Features:
# - Real-time solar production and consumption monitoring
# - Secure networking via Tailscale mesh VPN
# - Time-series data storage with InfluxDB
# - Rich visualizations with Grafana dashboards
# - Cost-optimized GKE deployment for free tier eligibility
#
# Data Flow:
# 1. Ingestor polls Enphase Envoy device via Tailscale cluster egress
# 2. Solar metrics stored in InfluxDB time-series database
# 3. Grafana provides visualization accessible via Tailscale
#
# Security:
# - All secrets managed via Kubernetes secrets with lifecycle protection
# - Tailscale provides zero-trust network access
# - GKE workload identity for secure GCP service access
# - No public load balancers or exposed endpoints
#
# =============================================================================

# Kubernetes Infrastructure Module
# 
# Deploys the complete solar monitoring stack including:
# - GKE cluster with optimized node configuration
# - Tailscale operator for secure networking
# - InfluxDB for time-series data storage
# - Grafana for visualization and dashboards
# - Custom ingestor application for data collection
module "kube" {
  source = "./kube"

  # Infrastructure Configuration
  project_id        = var.project_id        # GCP project ID
  zone             = var.zone              # GKE cluster zone (for free tier)
  region           = var.region            # GCP region
  cluster_name     = var.cluster_name      # Name of the GKE cluster

  # Node Pool Configuration
  node_machine_type  = var.node_machine_type  # VM type (e2-small for free tier)
  node_disk_size    = var.node_disk_size     # Boot disk size in GB
  use_spot_instances = var.use_spot_instances # Use preemptible instances for cost savings

  # Storage Configuration
  storage_class         = var.storage_class         # Kubernetes storage class
  influxdb_storage_size = var.influxdb_storage_size # InfluxDB persistent volume size
  grafana_storage_size  = var.grafana_storage_size  # Grafana persistent volume size

  # Application Configuration
  ingestor_image = var.ingestor_image # Container image for custom ingestor app
  namespace     = var.namespace       # Kubernetes namespace for all resources

  # Enphase Integration Secrets
  enphase_local_token = var.enphase_local_token # Token for Enphase Envoy API access
  envoy_host         = var.envoy_host          # IP address of Enphase Envoy device

  # Tailscale Networking Secrets
  ts_authkey                    = var.ts_authkey                    # Legacy Tailscale auth key (deprecated)
  tailscale_oauth_client_id     = var.tailscale_oauth_client_id     # OAuth client ID for Tailscale operator
  tailscale_oauth_client_secret = var.tailscale_oauth_client_secret # OAuth client secret for Tailscale operator

  # InfluxDB Configuration Secrets
  influxdb_admin_password = var.influxdb_admin_password # InfluxDB admin user password
  influxdb_admin_token   = var.influxdb_admin_token    # InfluxDB admin API token
}

