# Library books — CSS4005 Final Cloud Platform

> **Anton Belov · prefix `ci-anton-belov-0564` · AWS · VPC `10.195.0.0/16`**
>
> Production-shaped FastAPI **campus-app** (theme: library books) on **k3s** over autoscaled EC2, self-hosted **MySQL** + **ClickHouse**, ALB/HTTPS, Terraform, CI/CD, monitoring — built for CSS4005.

Assignment: [final-project.pdf](https://weeebdev-edu.github.io/css4005/pdfs/final-project.pdf) · Report: [`REPORT.md`](REPORT.md)

## Architecture (short)

Internet → **ALB (HTTPS)** → Traefik NodePort on **k3s** (server + ASG agents, 2 AZs) → app pods (**HPA CPU 60%**) → **MySQL primary/replica** + **ClickHouse** in private db subnets. Attachments/backups on **S3**. Secrets in **Secrets Manager**. Alarms in **CloudWatch** (CPU 80%, 5xx/min 20). Budget alert **$15**.

Diagram: [`docs/diagrams/architecture.mmd`](docs/diagrams/architecture.mmd) · ADRs: [`docs/adr/`](docs/adr/)

## Variant (do not share)

| Knob | Value |
| --- | --- |
| Theme | Library books |
| Prefix | `ci-anton-belov-0564` |
| VPC | `10.195.0.0/16` |
| Traffic | spiky |
| RPO / RTO | 15 min / 30 min |
| Budget | $15 |
| DB | MySQL + ClickHouse |
| Cluster | k3s-on-autoscaled-vms |
| HPA | 60% |
| Password | ≥14 + symbol |
| Alarms | CPU 80%, 5xx 20/min |
| Retention | 30 days |

## Repo layout

```
app/                 FastAPI service (template)
terraform/           AWS modules (network → monitoring)
scripts/             cloud-init + deploy-app + loadtest + state bootstrap
deploy/k8s/          Deployment, Service, Ingress, HPA
docs/adr/            Architecture Decision Records
docs/evidence/       Drop screenshots here after drills
REPORT.md            Graded report (export to PDF)
```

## Local app (5 minutes)

```bash
cp .env.example .env
docker compose --profile mysql --profile clickhouse up --build
curl localhost:8000/readyz
curl -X POST localhost:8000/api/items -H 'content-type: application/json' \
  -d '{"title":"Clean Code","description":"Library book"}'
```

```bash
make venv && make test && make lint
```

## Deploy on AWS (order)

1. **AWS CLI** configured (`aws sts get-caller-identity`).
2. Bootstrap remote state:
   ```bash
   chmod +x scripts/*.sh
   ./scripts/bootstrap-state.sh
   cp terraform/backend.tf.example terraform/backend.tf
   ```
3. Copy tfvars and set your email:
   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   # edit budget_alert_email, app_owner, github_org_repo
   ```
4. Apply:
   ```bash
   cd terraform
   terraform init
   terraform apply
   ```
5. Confirm SNS email subscription; wait for MySQL/k3s user-data (~10–15 min).
6. Build & deploy app:
   ```bash
   SHA=$(git rev-parse --short=12 HEAD)
   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$(terraform -chdir=terraform output -raw ecr_repository_url | cut -d/ -f1)"
   docker build -t "$(terraform -chdir=terraform output -raw ecr_repository_url):$SHA" .
   docker push "$(terraform -chdir=terraform output -raw ecr_repository_url):$SHA"
   IMAGE_TAG=$SHA ./scripts/deploy-app.sh
   ```
7. Open `terraform output -raw app_url` (accept self-signed warning).
8. Load test / drills / screenshots → `docs/evidence/` → finish `REPORT.md` → PDF.
9. **Tear down:** `terraform destroy` (budget!).

### GitHub Actions

- Set secret `AWS_ROLE_ARN` to `terraform output -raw gha_role_arn` (after setting `github_org_repo` in tfvars and re-apply).
- Push to `main` runs lint/test/scans; deploy runs when the role secret is present.

## Operations cheatsheet

```bash
# SSM shell (no public SSH)
aws ssm start-session --target $(aws ec2 describe-instances --filters Name=tag:Name,Values=ci-anton-belov-0564-k3s-server Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].InstanceId' --output text)

kubectl get nodes -L topology.kubernetes.io/zone
kubectl -n campus-app get pods -o wide
kubectl -n campus-app get hpa
kubectl -n campus-app rollout undo deployment/campus-app

k6 run -e BASE_URL="$(cd terraform && terraform output -raw app_url)" scripts/loadtest.js
```

## What you must still do for full marks

IaC and manifests are in this repo. Rubric “Full” also needs **live evidence**: DB unreachable test, load-test graphs, restore/failover timed vs RTO, alarm fire→OK, zone drill, cost vs budget, teardown screenshot, and oral defense of every file.

## License / honesty

Individual coursework. AI used as a scaffolding tool; you must be able to explain the platform at defense.
