#!/bin/bash
apt-get update && apt-get install -y \
  docker.io \
  docker-compose \
  git \
  curl \
  apt-transport-https \
  ca-certificates \
  gnupg

# write out private key
mkdir -p /root/.ssh
cat << 'EOF' > /root/.ssh/id_rsa
${git_private_key}
EOF
chmod 600 /root/.ssh/id_rsa

# trust GitHub
ssh-keyscan github.com >> /root/.ssh/known_hosts

# clone your repo
git clone ${repo_name} /opt/app
chown -R root:root /opt/app

# launch containers via docker-compose
docker-compose up -d /opt/app/docker-compose.yml
