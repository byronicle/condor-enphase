#!/bin/bash
# This script bootstraps the server for the Condor Enphase application:
# - Installs Docker and Docker Compose
# - Installs Google Cloud SDK for secret management
# - Retrieves SSH deploy keys and environment variables from GCP Secret Manager
# - Clones the application repository
# - Writes configuration and secrets
# - Launches Docker containers via Docker Compose

# Install dependencies required for Docker and system utilities
apt-get update && apt-get install -y \
  git \
  curl \
  apt-transport-https \
  ca-certificates \
  gnupg

# Pull and install Docker Engine via official script
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Update apt cache and install essential packages (git, curl, HTTPS transport, CA certificates, GnuPG)
apt-get update && apt-get install -y \
  git \
  curl \
  apt-transport-https \
  ca-certificates \
  gnupg

# Configure Google Cloud SDK APT repository and install the SDK for secret access
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" \
  | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg \
  | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
apt-get update && apt-get install -y google-cloud-sdk

# Retrieve SSH deploy key from GCP Secret Manager, save to ~/.ssh/id_rsa, and set proper permissions
mkdir -p /root/.ssh
gcloud secrets versions access latest --secret=GH_DEPLOY_KEY > /root/.ssh/id_rsa
chmod 600 /root/.ssh/id_rsa

# Add GitHub to known hosts to avoid interactive SSH prompts on clone
ssh-keyscan github.com >> /root/.ssh/known_hosts

# Clone the application repository into /opt/app and set root ownership
git clone ${repo_name} /opt/app
chown -R root:root /opt/app

cd /opt/app

# Create .env file and populate with non-sensitive config values from Secret Manager
echo "# non-secret config" > /opt/app/.env
echo "ENPHASE_LOCAL_TOKEN=$(gcloud secrets versions access latest --secret=ENPHASE_LOCAL_TOKEN)" >> /opt/app/.env
echo "ENVOY_HOST=$(gcloud secrets versions access latest --secret=ENVOY_HOST)" >> /opt/app/.env
echo "TS_AUTHKEY=$(gcloud secrets versions access latest --secret=TS_AUTHKEY)" >> /opt/app/.env

# Persist sensitive credentials under /opt/app/secrets for application consumption
mkdir -p /opt/app/secrets
echo "$(gcloud secrets versions access latest --secret=influxdb_admin_password)" > /opt/app/secrets/influxdb_admin_password.txt
echo "$(gcloud secrets versions access latest --secret=influxdb_admin_token)" > /opt/app/secrets/influxdb_admin_token.txt

# Launch application services in detached mode using Docker Compose
docker compose -f /opt/app/docker-compose.yaml up -d
