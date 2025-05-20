#!/bin/bash
apt-get update && apt-get install -y \
  docker.io \
  docker-compose \
  git \
  curl \
  apt-transport-https \
  ca-certificates \
  gnupg

# add Google Cloud SDK apt repo
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" \
  | tee /etc/apt/sources.list.d/google-cloud-sdk.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg \
  | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
apt-get update && apt-get install -y google-cloud-sdk

# clone code from Cloud Source Repository (uses VM service account)
mkdir -p /opt/app && cd /opt/app
gcloud config set project ${project_id}
gcloud source repos clone ${repo_name} .

# launch containers via docker-compose
docker-compose up -d
