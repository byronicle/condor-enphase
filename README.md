# condor-enphase

A Python application that fetches solar production and consumption data from a local Enphase Envoy device, writes time-series metrics to InfluxDB, and provides comprehensive visualization through Grafana dashboards. This improves on the limited graphs provided by Enphase with detailed monitoring and historical analysis.

## Architecture

The application supports two deployment architectures:

### Cloud Deployment (Recommended)
Runs on Google Kubernetes Engine (GKE) with Tailscale networking for secure access to home network resources:

- **Ingestor Service**: Python application that polls the Enphase Envoy device
- **InfluxDB**: Time-series database for storing solar metrics
- **Grafana**: Visualization platform with custom solar dashboard
- **Tailscale Operator**: Provides secure networking to reach home devices

### Local Deployment (Raspberry Pi)
Runs directly on a Raspberry Pi using Docker Compose for local monitoring:

- **Local Network Access**: Direct connection to Enphase Envoy device
- **Docker Compose**: Simplified deployment with container orchestration
- **Port Forwarding**: Optional remote access via port forwarding or VPN

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

### Cloud Deployment

#### Google Cloud
- gcloud CLI authenticated and set to your GCP project
- Terraform v1.5+ installed
- GKE API enabled in your project
- Service account with GKE and Container Registry permissions

#### Tailscale
- Tailscale account with OAuth application configured
- Subnet router configured on home network (for Envoy access)

### Local Deployment (Raspberry Pi)

#### Hardware
- Raspberry Pi 4+ (8GB RAM recommended for better performance)
- 32GB+ microSD card (Class 10 or better)
- Stable internet connection
- Enphase Envoy device on same local network

#### Software
- Raspberry Pi OS Lite (64-bit)
- Docker and Docker Compose
- Git

## Deployment Options

### Option 1: Cloud Deployment on GKE

This is the recommended approach for production use, offering scalability, reliability, and remote access via Tailscale.

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-username/condor-enphase.git
   cd condor-enphase
   ```

2. **Configure Terraform variables**
   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

3. **Deploy infrastructure**
   ```bash
   cd terraform
   terraform init
   terraform plan
   terraform apply
   ```

4. **Access Grafana**
   - Grafana will be available via Tailscale at `grafana-k8s-cluster`
   - Default credentials: `admin/admin` (change on first login)

### Option 2: Local Deployment on Raspberry Pi

This option runs everything locally on a Raspberry Pi, ideal for users who prefer local control and don't need remote access.

#### Step 1: Prepare Raspberry Pi

1. **Install Raspberry Pi OS**
   ```bash
   # Flash Raspberry Pi OS Lite (64-bit) to SD card
   # Enable SSH during imaging or create empty 'ssh' file on boot partition
   ```

2. **Initial setup**
   ```bash
   # SSH into your Pi
   ssh pi@<raspberry-pi-ip>
   
   # Update system
   sudo apt update && sudo apt upgrade -y
   
   # Install required packages
   sudo apt install -y git curl
   ```

3. **Install Docker and Docker Compose**
   ```bash
   # Install Docker
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh
   sudo usermod -aG docker pi
   
   # Install Docker Compose
   sudo apt install -y docker-compose
   
   # Logout and login again for group changes
   exit
   ssh pi@<raspberry-pi-ip>
   ```

#### Step 2: Deploy Application

1. **Clone repository**
   ```bash
   git clone https://github.com/your-username/condor-enphase.git
   cd condor-enphase
   ```

2. **Configure environment**
   ```bash
   # Copy example environment file
   cp .env.example .env
   
   # Edit .env file with your values
   nano .env
   ```

   Required configuration:
   ```bash
   # Enphase Envoy Configuration
   ENPHASE_LOCAL_TOKEN=your_envoy_token_here
   ENVOY_HOST=192.168.1.xxx  # Your Envoy IP address
   
   # InfluxDB Configuration
   INFLUXDB_ADMIN_PASSWORD=your_secure_password
   INFLUXDB_ADMIN_TOKEN=your_secure_token
   
   # Optional: Tailscale for remote access
   TS_AUTHKEY=your_tailscale_authkey  # Optional
   ```

3. **Start services**
   ```bash
   # Start all services
   docker-compose up -d
   
   # Check logs
   docker-compose logs -f
   
   # Verify services are running
   docker-compose ps
   ```

#### Step 3: Access Services

1. **Local access**
   - Grafana: `http://<raspberry-pi-ip>:3000`
   - InfluxDB: `http://<raspberry-pi-ip>:8086`
   - Default Grafana credentials: `admin/admin`

2. **Import dashboard**
   - Log into Grafana
   - Go to Dashboards → Import
   - Upload `solar-dashboard.json` from the repository
   - Configure InfluxDB data source if needed

#### Step 4: Optional Remote Access

1. **Port forwarding** (Simple but less secure)
   ```bash
   # Forward port 3000 on your router to Pi's port 3000
   # Access via: http://your-public-ip:3000
   ```

2. **Tailscale** (Recommended for security)
   ```bash
   # Install Tailscale on Pi
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up --authkey=your_authkey
   
   # Access Grafana via Tailscale IP
   ```

#### Maintenance

1. **Update containers**
   ```bash
   cd condor-enphase
   docker-compose pull
   docker-compose up -d
   ```

2. **View logs**
   ```bash
   docker-compose logs [service-name]
   ```

3. **Backup data**
   ```bash
   # Backup InfluxDB data
   docker-compose exec influxdb influx backup /tmp/backup
   docker cp $(docker-compose ps -q influxdb):/tmp/backup ./influxdb-backup
   
   # Backup Grafana data
   docker cp $(docker-compose ps -q grafana):/var/lib/grafana ./grafana-backup
   ```

## Performance Considerations

### Raspberry Pi Optimization
- **Memory**: 8GB RAM recommended, 4GB minimum
- **Storage**: Use high-quality SD card or USB SSD for better I/O
- **Cooling**: Ensure adequate cooling for continuous operation
- **Power**: Use official Pi power supply for stability


