#!/bin/bash
# Self-hosted ClickHouse analytics node (db tier).
set -euxo pipefail

RESOURCE_PREFIX="${resource_prefix}"
AWS_REGION="${aws_region}"
SECRET_CH="${secret_clickhouse}"

export DEBIAN_FRONTEND=noninteractive
echo 'Acquire::ForceIPv4 "true";' >/etc/apt/apt.conf.d/99force-ipv4
apt-get update -y
apt-get upgrade -y
apt-get install -y apt-transport-https ca-certificates curl gnupg unzip unattended-upgrades
if ! command -v aws >/dev/null 2>&1; then
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -qo /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install -b /usr/local/bin || /tmp/aws/install --update -b /usr/local/bin
fi

DATA_DEV=""
for d in /dev/nvme1n1 /dev/xvdf; do
  if [ -b "$d" ]; then DATA_DEV="$d"; break; fi
done
if [ -n "$DATA_DEV" ]; then
  if ! blkid "$DATA_DEV" >/dev/null 2>&1; then
    mkfs.ext4 -L chdata "$DATA_DEV"
  fi
  mkdir -p /var/lib/clickhouse
  mount "$DATA_DEV" /var/lib/clickhouse || true
  grep -q 'LABEL=chdata' /etc/fstab || echo 'LABEL=chdata /var/lib/clickhouse ext4 defaults,nofail 0 2' >> /etc/fstab
fi

curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' | gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg || true
# Debian/Ubuntu apt repo
mkdir -p /etc/apt/keyrings
curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' | gpg --dearmor -o /etc/apt/keyrings/clickhouse-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/clickhouse-keyring.gpg] https://packages.clickhouse.com/deb stable main" > /etc/apt/sources.list.d/clickhouse.list
apt-get update -y
apt-get install -y clickhouse-server clickhouse-client

CH_PW="$(aws secretsmanager get-secret-value --region "$AWS_REGION" --secret-id "$SECRET_CH" --query SecretString --output text)"
install -d -m 700 /etc/clickhouse-server/secrets
printf '%s' "$CH_PW" > /etc/clickhouse-server/secrets/analytics
chmod 400 /etc/clickhouse-server/secrets/analytics
chown clickhouse:clickhouse /etc/clickhouse-server/secrets/analytics

cat >/etc/clickhouse-server/users.d/analytics.xml <<EOF
<clickhouse>
  <users>
    <analytics>
      <password>$CH_PW</password>
      <networks><ip>::/0</ip></networks>
      <profile>default</profile>
      <quota>default</quota>
    </analytics>
  </users>
</clickhouse>
EOF

# Default config only listens on localhost — open to VPC (SG still restricts)
mkdir -p /etc/clickhouse-server/config.d
cat >/etc/clickhouse-server/config.d/listen.xml <<'EOF'
<clickhouse>
  <listen_host>0.0.0.0</listen_host>
</clickhouse>
EOF

chown -R clickhouse:clickhouse /var/lib/clickhouse
systemctl enable clickhouse-server
systemctl restart clickhouse-server

for i in $(seq 1 60); do
  clickhouse-client --query 'SELECT 1' && break
  sleep 2
done

clickhouse-client --query "CREATE DATABASE IF NOT EXISTS campus"
clickhouse-client --query "
CREATE TABLE IF NOT EXISTS campus.events (
  ts DateTime,
  event String,
  item_id UInt64,
  payload String
) ENGINE = MergeTree ORDER BY (ts, event)
"

dpkg-reconfigure -f noninteractive unattended-upgrades || true
echo "clickhouse bootstrap complete"
