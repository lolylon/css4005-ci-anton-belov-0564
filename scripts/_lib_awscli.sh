# Shared AWS CLI v2 bootstrap (Ubuntu 22.04 has no apt package "awscli").
install_awscli_v2() {
  if command -v aws >/dev/null 2>&1; then
    return 0
  fi
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y curl unzip ca-certificates
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -qo /tmp/awscliv2.zip -d /tmp
  if [ -x /usr/local/bin/aws ]; then
    /tmp/aws/install --update -b /usr/local/bin
  else
    /tmp/aws/install -b /usr/local/bin
  fi
  aws --version
}

force_apt_ipv4() {
  echo 'Acquire::ForceIPv4 "true";' >/etc/apt/apt.conf.d/99force-ipv4
}
