#!/bin/bash
# MySQL 8 async replica (binlog/GTID) in second AZ.
set -euxo pipefail

RESOURCE_PREFIX="${resource_prefix}"
AWS_REGION="${aws_region}"
SECRET_REPL="${secret_repl}"
SECRET_ADMIN="${secret_admin}"
PRIMARY_IP="${primary_private_ip}"

export DEBIAN_FRONTEND=noninteractive
echo 'Acquire::ForceIPv4 "true";' >/etc/apt/apt.conf.d/99force-ipv4
apt-get update -y
apt-get upgrade -y
apt-get install -y mysql-server mysql-client jq curl unzip rsync unattended-upgrades
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
    mkfs.ext4 -L mysqldata "$DATA_DEV"
  fi
  mkdir -p /var/lib/mysql-data
  mount "$DATA_DEV" /var/lib/mysql-data || true
  grep -q 'LABEL=mysqldata' /etc/fstab || echo 'LABEL=mysqldata /var/lib/mysql-data ext4 defaults,nofail 0 2' >> /etc/fstab
  systemctl stop mysql || true
  if [ ! -d /var/lib/mysql-data/mysql ]; then
    rsync -a /var/lib/mysql/ /var/lib/mysql-data/
  fi
  mv /var/lib/mysql /var/lib/mysql.bak.os || true
  mkdir -p /var/lib/mysql
  mount --bind /var/lib/mysql-data /var/lib/mysql
  grep -q 'mysql-data /var/lib/mysql' /etc/fstab || echo '/var/lib/mysql-data /var/lib/mysql none bind 0 0' >> /etc/fstab
  chown -R mysql:mysql /var/lib/mysql-data
fi

get_secret() {
  aws secretsmanager get-secret-value --region "$AWS_REGION" --secret-id "$1" --query SecretString --output text
}
REPL_PW="$(get_secret "$SECRET_REPL")"

install -d -m 700 /etc/mysql/secrets
printf '%s' "$REPL_PW" > /etc/mysql/secrets/repl
chmod 400 /etc/mysql/secrets/repl
chown mysql:mysql /etc/mysql/secrets/repl

cat >/etc/mysql/mysql.conf.d/zz-replica.cnf <<EOF
[mysqld]
server-id=2
bind-address=0.0.0.0
gtid_mode=ON
enforce_gtid_consistency=ON
log_bin=mysql-bin
relay_log=relay-bin
read_only=1
super_read_only=1
binlog_format=ROW
EOF

systemctl enable mysql
systemctl restart mysql
for i in $(seq 1 60); do mysqladmin ping --silent && break; sleep 2; done

# Wait for primary
for i in $(seq 1 90); do
  if mysqladmin ping -h "$PRIMARY_IP" --silent 2>/dev/null; then break; fi
  sleep 5
done

mysql -u root <<SQL
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='$PRIMARY_IP',
  SOURCE_USER='repl',
  SOURCE_PASSWORD='$REPL_PW',
  SOURCE_AUTO_POSITION=1,
  GET_SOURCE_PUBLIC_KEY=1;
START REPLICA;
SHOW REPLICA STATUS\G
SQL

dpkg-reconfigure -f noninteractive unattended-upgrades || true
echo "mysql-replica bootstrap complete; primary=$PRIMARY_IP"
