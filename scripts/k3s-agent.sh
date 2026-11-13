#!/bin/bash
# k3s agent — ASG launch template; join token from Secrets Manager.
set -euxo pipefail

RESOURCE_PREFIX="${resource_prefix}"
AWS_REGION="${aws_region}"
SECRET_K3S="${secret_k3s_token}"

export DEBIAN_FRONTEND=noninteractive
echo 'Acquire::ForceIPv4 "true";' >/etc/apt/apt.conf.d/99force-ipv4
apt-get update -y
apt-get upgrade -y
apt-get install -y curl jq unzip unattended-upgrades
if ! command -v aws >/dev/null 2>&1; then
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -qo /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install -b /usr/local/bin || /tmp/aws/install --update -b /usr/local/bin
fi

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
NODE_AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)

K3S_TOKEN="$(aws secretsmanager get-secret-value --region "$AWS_REGION" --secret-id "$SECRET_K3S" --query SecretString --output text)"

# Discover server IP (written by k3s-server bootstrap)
for i in $(seq 1 60); do
  SERVER_IP=$(aws ssm get-parameter --region "$AWS_REGION" --name "/$RESOURCE_PREFIX/k3s-server-ip" --query 'Parameter.Value' --output text 2>/dev/null || true)
  if [ -n "$SERVER_IP" ] && [ "$SERVER_IP" != "None" ]; then break; fi
  sleep 10
done

curl -sfL https://get.k3s.io | K3S_URL="https://$SERVER_IP:6443" K3S_TOKEN="$K3S_TOKEN" INSTALL_K3S_EXEC="agent --node-label topology.kubernetes.io/zone=$NODE_AZ --node-ip $PRIVATE_IP" sh -

dpkg-reconfigure -f noninteractive unattended-upgrades || true
echo "k3s-agent joined $SERVER_IP az=$NODE_AZ"
