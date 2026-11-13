#!/bin/bash
# MySQL 8 primary — cloud-init. Secrets from Secrets Manager via instance role.
set -euxo pipefail

RESOURCE_PREFIX="${resource_prefix}"
AWS_REGION="${aws_region}"
BUCKET_NAME="${bucket_name}"
PASSWORD_MIN_LENGTH="${password_min_length}"
RPO_MINUTES="${rpo_minutes}"
SECRET_ADMIN="${secret_admin}"
SECRET_APP_RW="${secret_app_rw}"
SECRET_APP_RO="${secret_app_ro}"
SECRET_REPL="${secret_repl}"

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
ADMIN_PW="$(get_secret "$SECRET_ADMIN")"
APP_RW_PW="$(get_secret "$SECRET_APP_RW")"
APP_RO_PW="$(get_secret "$SECRET_APP_RO")"
REPL_PW="$(get_secret "$SECRET_REPL")"

install -d -m 700 /etc/mysql/secrets
umask 077
printf '%s' "$ADMIN_PW"  > /etc/mysql/secrets/admin
printf '%s' "$APP_RW_PW" > /etc/mysql/secrets/app_rw
printf '%s' "$APP_RO_PW" > /etc/mysql/secrets/app_ro
printf '%s' "$REPL_PW"   > /etc/mysql/secrets/repl
chown -R mysql:mysql /etc/mysql/secrets
chmod 400 /etc/mysql/secrets/*

PRIVATE_IP="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 || true)"
# IMDSv2 fallback
if [ -z "$PRIVATE_IP" ]; then
  TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
fi

# Override Ubuntu default bind-address=127.0.0.1 (later files alone are not enough on 8.0)
sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf || true
sed -i 's/^mysqlx-bind-address.*/mysqlx-bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf || true

cat >/etc/mysql/mysql.conf.d/zz-primary.cnf <<EOF
[mysqld]
server-id=1
bind-address=0.0.0.0
gtid_mode=ON
enforce_gtid_consistency=ON
log_bin=mysql-bin
binlog_format=ROW
binlog_expire_logs_seconds=604800
plugin-load-add=validate_password.so
validate-password=FORCE_PLUS_PERMANENT
validate_password_policy=MEDIUM
validate_password_length=$PASSWORD_MIN_LENGTH
validate_password_mixed_case_count=1
validate_password_number_count=1
validate_password_special_char_count=1
EOF

systemctl enable mysql
systemctl restart mysql
for i in $(seq 1 60); do mysqladmin ping --silent && break; sleep 2; done

# Create users via escaped SQL file (passwords never in argv)
SQL_FILE=$(mktemp)
trap 'rm -f "$SQL_FILE"' EXIT
{
  echo "INSTALL COMPONENT 'file://component_validate_password';"
  echo "SET GLOBAL validate_password.policy = MEDIUM;"
  echo "SET GLOBAL validate_password.length = $PASSWORD_MIN_LENGTH;"
  echo "SET GLOBAL validate_password.mixed_case_count = 1;"
  echo "SET GLOBAL validate_password.number_count = 1;"
  echo "SET GLOBAL validate_password.special_char_count = 1;"
  echo "CREATE DATABASE IF NOT EXISTS campus;"
  printf "CREATE USER IF NOT EXISTS 'admin'@'%%' IDENTIFIED BY '%s';\n" "$ADMIN_PW"
  printf "CREATE USER IF NOT EXISTS 'app_rw'@'%%' IDENTIFIED BY '%s' WITH MAX_USER_CONNECTIONS 50;\n" "$APP_RW_PW"
  printf "CREATE USER IF NOT EXISTS 'app_ro'@'%%' IDENTIFIED BY '%s' WITH MAX_USER_CONNECTIONS 10;\n" "$APP_RO_PW"
  printf "CREATE USER IF NOT EXISTS 'repl'@'%%' IDENTIFIED WITH mysql_native_password BY '%s';\n" "$REPL_PW"
  echo "GRANT ALL PRIVILEGES ON campus.* TO 'admin'@'%';"
  echo "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX ON campus.* TO 'app_rw'@'%';"
  echo "GRANT SELECT ON campus.* TO 'app_ro'@'%';"
  echo "GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'repl'@'%';"
  echo "FLUSH PRIVILEGES;"
} > "$SQL_FILE"
mysql -u root < "$SQL_FILE" || mysql -u root < "$SQL_FILE"

install -d -m 755 "/opt/$RESOURCE_PREFIX"
cat >"/opt/$RESOURCE_PREFIX/backup-mysql.sh" <<EOS
#!/bin/bash
set -euo pipefail
REGION="$AWS_REGION"
BUCKET="$BUCKET_NAME"
STAMP=\$(date -u +%Y%m%dT%H%M%SZ)
TMP="/tmp/campus-\$STAMP.sql.gz"
mysqldump -u admin -p"\$(cat /etc/mysql/secrets/admin)" --single-transaction --routines --triggers campus | gzip > "\$TMP"
aws s3 cp "\$TMP" "s3://\$BUCKET/backups/mysql/\$STAMP.sql.gz" --region "\$REGION"
rm -f "\$TMP"
EOS
chmod 700 "/opt/$RESOURCE_PREFIX/backup-mysql.sh"

echo "*/$RPO_MINUTES * * * * root /opt/$RESOURCE_PREFIX/backup-mysql.sh >> /var/log/mysql-backup.log 2>&1" > "/etc/cron.d/$RESOURCE_PREFIX-mysql-backup"
chmod 644 "/etc/cron.d/$RESOURCE_PREFIX-mysql-backup"

dpkg-reconfigure -f noninteractive unattended-upgrades || true
aws ssm put-parameter --region "$AWS_REGION" --name "/$RESOURCE_PREFIX/mysql-primary-ip" --type String --value "$PRIVATE_IP" --overwrite || true
echo "mysql-primary bootstrap complete on $PRIVATE_IP"
