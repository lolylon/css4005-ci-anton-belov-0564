#!/bin/bash
# k3s server node — joins agents via token from Secrets Manager.
set -euxo pipefail

RESOURCE_PREFIX="${resource_prefix}"
AWS_REGION="${aws_region}"
SECRET_K3S="${secret_k3s_token}"
ECR_URL="${ecr_repository_url}"

export DEBIAN_FRONTEND=noninteractive
echo 'Acquire::ForceIPv4 "true";' >/etc/apt/apt.conf.d/99force-ipv4
apt-get update -y
apt-get upgrade -y
apt-get install -y curl jq unzip unattended-upgrades apt-transport-https ca-certificates
if ! command -v aws >/dev/null 2>&1; then
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -qo /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install -b /usr/local/bin || /tmp/aws/install --update -b /usr/local/bin
fi

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
NODE_AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)

K3S_TOKEN="$(aws secretsmanager get-secret-value --region "$AWS_REGION" --secret-id "$SECRET_K3S" --query SecretString --output text)"

# Disable public traefik LoadBalancer; we front with ALB → NodePort
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable=traefik --node-label topology.kubernetes.io/zone=$NODE_AZ --node-ip $PRIVATE_IP --tls-san $PRIVATE_IP" K3S_TOKEN="$K3S_TOKEN" sh -

# Wait for node ready
for i in $(seq 1 60); do
  kubectl get nodes && break
  sleep 5
done

# Install Traefik with fixed NodePorts for ALB target group
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Namespace
metadata:
  name: traefik
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: traefik
  namespace: traefik
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: traefik
  namespace: traefik
spec:
  replicas: 2
  selector:
    matchLabels:
      app: traefik
  template:
    metadata:
      labels:
        app: traefik
    spec:
      serviceAccountName: traefik
      containers:
        - name: traefik
          image: traefik:v3.1
          args:
            - --providers.kubernetesingress=true
            - --providers.kubernetesingress.ingressclass=traefik
            - --entrypoints.web.address=:80
            - --entrypoints.websecure.address=:443
            - --api.dashboard=false
            - --log.level=INFO
          ports:
            - name: web
              containerPort: 80
            - name: websecure
              containerPort: 443
---
apiVersion: v1
kind: Service
metadata:
  name: traefik
  namespace: traefik
spec:
  type: NodePort
  selector:
    app: traefik
  ports:
    - name: web
      port: 80
      targetPort: 80
      nodePort: 30080
    - name: websecure
      port: 443
      targetPort: 443
      nodePort: 30443
YAML

# RBAC for ingress
kubectl apply -f - <<'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: traefik
rules:
  - apiGroups: [""]
    resources: ["services", "endpoints", "secrets", "nodes", "pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["discovery.k8s.io"]
    resources: ["endpointslices"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["extensions", "networking.k8s.io"]
    resources: ["ingresses", "ingressclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses/status"]
    verbs: ["update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: traefik
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: traefik
subjects:
  - kind: ServiceAccount
    name: traefik
    namespace: traefik
---
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: traefik
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: traefik.io/ingress-controller
YAML

# ECR login helper cron for kubelet pulls via instance role
mkdir -p /opt/$RESOURCE_PREFIX
cat >/opt/$RESOURCE_PREFIX/ecr-login.sh <<EOS
#!/bin/bash
set -euo pipefail
REGION="$AWS_REGION"
ECR="$ECR_URL"
PASS=\$(aws ecr get-login-password --region "\$REGION")
# Create/refresh image pull secret in campus-app ns when it exists
if kubectl get ns campus-app >/dev/null 2>&1; then
  kubectl -n campus-app create secret docker-registry ecr-pull \
    --docker-server=\$(echo "\$ECR" | cut -d/ -f1) \
    --docker-username=AWS \
    --docker-password="\$PASS" \
    --dry-run=client -o yaml | kubectl apply -f -
fi
EOS
chmod 700 /opt/$RESOURCE_PREFIX/ecr-login.sh
echo "*/6 * * * * root /opt/$RESOURCE_PREFIX/ecr-login.sh >> /var/log/ecr-login.log 2>&1" > /etc/cron.d/$RESOURCE_PREFIX-ecr

# Publish kubeconfig / server IP for CI deploy via SSM
aws ssm put-parameter --region "$AWS_REGION" --name "/$RESOURCE_PREFIX/k3s-server-ip" --type String --value "$PRIVATE_IP" --overwrite || true
cp /etc/rancher/k3s/k3s.yaml /tmp/k3s.yaml
sed -i "s/127.0.0.1/$PRIVATE_IP/" /tmp/k3s.yaml
aws ssm put-parameter --region "$AWS_REGION" --name "/$RESOURCE_PREFIX/kubeconfig" --type SecureString --value "$(cat /tmp/k3s.yaml)" --overwrite || true
rm -f /tmp/k3s.yaml

dpkg-reconfigure -f noninteractive unattended-upgrades || true
echo "k3s-server ready on $PRIVATE_IP az=$NODE_AZ id=$INSTANCE_ID"
