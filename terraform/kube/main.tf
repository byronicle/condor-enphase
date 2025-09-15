# Enphase Solar Monitoring Kubernetes Infrastructure
# 
# This module deploys a complete solar monitoring stack on Google Kubernetes Engine (GKE)
# with Tailscale networking for secure access to home network devices.
#
# File Organization:
# - cluster.tf     - GKE cluster, node pools, and service accounts
# - networking.tf  - Tailscale operator and home network connectivity
# - storage.tf     - Persistent volume claims for data storage
# - secrets.tf     - Kubernetes secrets, namespaces, and config maps
# - influxdb.tf    - InfluxDB time-series database deployment
# - grafana.tf     - Grafana visualization platform deployment  
# - ingestor.tf    - Custom Python application for data collection
# - variables.tf   - Input variable definitions
# - outputs.tf     - Output value definitions
# - provider.tf    - Provider configurations
#
# Architecture:
# - Ingestor connects to Enphase Envoy device via Tailscale cluster egress
# - Data flows: Envoy -> Ingestor -> InfluxDB -> Grafana
# - Grafana exposed via Tailscale for secure remote access
# - All services run as Kubernetes deployments with persistent storage