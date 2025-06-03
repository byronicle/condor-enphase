#!/bin/bash
apt-get update && apt-get install -y \
  docker.io \
  docker-compose \
  git \
  curl \
  apt-transport-https \
  ca-certificates \
  gnupg

# Install Google Cloud SDK
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" \
  | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg \
  | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
apt-get update && apt-get install -y google-cloud-sdk



# write out private key
mkdir -p /root/.ssh
cat << 'EOF' > /root/.ssh/id_rsa
$(gcloud secrets versions access --secret=GH_DPLOY_KEY)
EOF
chmod 600 /root/.ssh/id_rsa

# trust GitHub
ssh-keyscan github.com >> /root/.ssh/known_hosts

# clone your repo
git clone ${repo_name} /opt/app
chown -R root:root /opt/app

cd /opt/app

# Create or truncate .env
echo "# non-secret config" > /opt/app/.env
echo "ENPHASE_LOCAL_TOKEN=$(gcloud secrets versions access --secret=ENPHASE_LOCAL_TOKEN)" >> /opt/app/.env
echo "ENVOY_HOST=$(gcloud secrets versions access --secret=ENVOY_HOST)" >> /opt/app/.env
echo "TS_AUTHKEY=$(gcloud secrets versions access --secret=TS_AUTHKEY)" >> /opt/app/.env

# write out secrets to files
mkdir -p /opt/app/secrets
echo "$(gcloud secrets versions access --secret=INFLUXDB_ADMIN_PASSWORD)" > /opt/app/secrets/influxdb_admin_password.txt
echo "$(gcloud secrets versions access --secret=INFLUXDB_ADMIN_TOKEN)" > /opt/app/secrets/influxdb_admin_token.txt

# launch containers via docker-compose
docker-compose up -d /opt/app/docker-compose.yml
