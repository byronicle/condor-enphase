# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Python application for monitoring Enphase solar systems. It fetches data from local Enphase Envoy devices, stores time-series data in InfluxDB, and provides Grafana dashboards for visualization. The project supports both local (Raspberry Pi) and cloud (Google Kubernetes Engine) deployments.

## Architecture

### Core Components
- **Ingestor Service** (`app/main.py`): Python application that polls Enphase Envoy API endpoints
- **Enphase Client** (`app/enphase_client.py`): Handles authentication and API communication with Envoy devices
- **InfluxDB Writer** (`app/influx_writer.py`): Manages time-series data storage to InfluxDB
- **Docker Compose**: Local deployment stack with InfluxDB, Grafana, and Tailscale networking
- **Terraform Infrastructure**: GKE cluster deployment in `terraform/` directory

### Deployment Options
1. **Local**: Docker Compose on Raspberry Pi with direct network access to Enphase Envoy
2. **Cloud**: GKE deployment with Tailscale networking for secure home device access

## Development Commands

### Local Development
```bash
# Run locally with Docker Compose
docker-compose up -d

# View logs
docker-compose logs -f [service-name]

# Stop services
docker-compose down

# Update containers
docker-compose pull && docker-compose up -d
```

### Build and Test
```bash
# Build Docker image
docker build -t condor-enphase .

# Run Python application directly (requires .env file)
cd app && python main.py
```

### Infrastructure (Terraform)
```bash
cd terraform

# Initialize and plan
terraform init
terraform plan

# Deploy infrastructure
terraform apply

# Deploy Kubernetes resources
cd kube
terraform init
terraform plan
terraform apply
```

## Configuration

### Environment Variables
Key configuration in `.env` file for local deployment:
- `ENPHASE_LOCAL_TOKEN`: Authentication token for Envoy device
- `ENVOY_HOST`: IP address of Enphase Envoy device
- `INFLUXDB_URL`, `INFLUXDB_ORG`, `INFLUXDB_BUCKET`: InfluxDB connection settings
- `TS_AUTHKEY`: Optional Tailscale authentication key

### Terraform Variables
Configure `terraform/terraform.tfvars` for cloud deployment:
- GCP project settings
- Tailscale OAuth configuration
- Kubernetes cluster specifications

## Key Files

### Application Code
- `app/main.py`: Main application entry point and data collection logic
- `app/enphase_client.py`: Enphase API client with authentication handling
- `app/influx_writer.py`: InfluxDB time-series data writer
- `requirements.txt`: Python dependencies

### Infrastructure
- `docker-compose.yaml`: Local deployment stack definition
- `Dockerfile`: Application container definition
- `terraform/main.tf`: GCP infrastructure (VPC, GKE cluster)
- `terraform/kube/`: Kubernetes resources (deployments, services, secrets)

### Configuration
- `solar-dashboard.json`: Grafana dashboard configuration
- `init/`: InfluxDB initialization scripts
- `secrets/`: Directory for local secrets (influxdb credentials)

## Data Flow

1. **Collection**: Application polls 5 Enphase Envoy endpoints every cycle
2. **Processing**: Converts hardware timestamps to UTC, normalizes data
3. **Storage**: Writes time-series points to InfluxDB with proper tagging
4. **Visualization**: Grafana displays real-time and historical solar metrics

### Monitored Endpoints
- `/ivp/pdm/energy` → Production and consumption energy data
- `/api/v1/production` → Total production metrics
- `/ivp/meters/readings` → Individual CT meter readings
- `/api/v1/production/inverters` → Per-inverter performance
- `/ivp/livedata/status` → Real-time power flow data

## Networking

### Local Deployment
- Direct network access to Enphase Envoy device
- Optional Tailscale for remote access
- Grafana accessible at `http://pi-ip:3000`

### Cloud Deployment
- Tailscale mesh networking for secure home device access
- Kubernetes services with internal networking
- Grafana accessible via Tailscale at `grafana-k8s-cluster`