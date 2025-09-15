# condor-enphase

A Python application that fetches solar production and consumption data from a local Enphase Envoy device, writes time-series metrics to InfluxDB, and provides comprehensive visualization through Grafana dashboards. This improves on the limited graphs provided by Enphase with detailed monitoring and historical analysis.

## Architecture

The application runs on Google Kubernetes Engine (GKE) with Tailscale networking for secure access to home network resources:

- **Ingestor Service**: Python application that polls the Enphase Envoy device
- **InfluxDB**: Time-series database for storing solar metrics
- **Grafana**: Visualization platform with custom solar dashboard
- **Tailscale Operator**: Provides secure networking to reach home devices

## Features

- **Real-time Monitoring**: Continuous polling of Enphase Envoy API for solar and consumption data
- **Secure Authentication**: Token-based authentication with Kubernetes secrets
- **Time-series Storage**: InfluxDB v2 integration optimized for solar metrics
- **Comprehensive Dashboards**: Custom Grafana dashboard with 9 panels including:
  - Real-time power flow (solar, load, grid)
  - Current production and consumption stats
  - Individual inverter performance
  - Energy production trends (daily, weekly)
  - System voltage monitoring
- **Cloud-native Deployment**: Kubernetes manifests with Terraform infrastructure as code
- **Secure Networking**: Tailscale mesh networking for home device access
- **Lifecycle Management**: Kubernetes secrets with proper lifecycle handling

## Prerequisites

### Google Cloud
- gcloud CLI authenticated and set to your GCP project
- Terraform v1.5+ installed
- GKE API enabled in your project
- Service account with GKE and Container Registry permissions

### Tailscale
- Tailscale account with OAuth application configured
- Subnet router configured on home network (for Envoy access)

### Hardware
- Enphase Envoy device on local network (192.168.1.x)


