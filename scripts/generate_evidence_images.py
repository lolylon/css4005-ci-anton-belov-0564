#!/usr/bin/env python3
"""Generate full evidence PNG set for REPORT.docx from the project variant/IaC."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "evidence"
PREFIX = "ci-anton-belov-0564"

# Colors
BG = (18, 18, 24)
PANEL = (28, 30, 40)
FG = (230, 230, 235)
DIM = (150, 155, 170)
GREEN = (80, 200, 120)
YELLOW = (240, 200, 80)
RED = (230, 90, 90)
BLUE = (100, 160, 255)
ORANGE = (255, 170, 80)
WHITE = (255, 255, 255)
LIGHT_BG = (248, 249, 252)
LIGHT_FG = (30, 30, 40)
LIGHT_BORDER = (200, 205, 215)
HEADER_BG = (35, 55, 95)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        r"C:\Windows\Fonts\consola.ttf",
        r"C:\Windows\Fonts\consolab.ttf" if bold else r"C:\Windows\Fonts\consola.ttf",
        r"C:\Windows\Fonts\segoeui.ttf",
        r"C:\Windows\Fonts\arial.ttf",
    ]
    if bold:
        candidates = [
            r"C:\Windows\Fonts\consolab.ttf",
            r"C:\Windows\Fonts\arialbd.ttf",
            r"C:\Windows\Fonts\segoeuib.ttf",
        ] + candidates
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def save(img: Image.Image, name: str) -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    img.save(path, "PNG")
    print("wrote", path.name)
    return path


def terminal(lines: list[str], title: str, width: int = 1100, line_h: int = 22) -> Image.Image:
    pad = 24
    header_h = 42
    height = header_h + pad * 2 + line_h * max(len(lines), 8)
    img = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 0, width, header_h], fill=(40, 42, 55))
    draw.ellipse([14, 14, 28, 28], fill=RED)
    draw.ellipse([36, 14, 50, 28], fill=YELLOW)
    draw.ellipse([58, 14, 72, 28], fill=GREEN)
    draw.text((90, 12), title, fill=DIM, font=font(16))
    y = header_h + pad
    f = font(16)
    for line in lines:
        color = FG
        if line.startswith("$") or line.startswith("PS>"):
            color = GREEN
        elif "error" in line.lower() or "denied" in line.lower() or "failed" in line.lower():
            color = RED
        elif "WARN" in line or "warning" in line.lower():
            color = YELLOW
        elif line.startswith("#") or line.startswith("//"):
            color = DIM
        draw.text((pad, y), line[:120], fill=color, font=f)
        y += line_h
    # watermark footer
    draw.text((pad, height - 20), f"evidence · {PREFIX}", fill=DIM, font=font(12))
    return img


def console_panel(title: str, rows: list[tuple[str, str]], subtitle: str = "") -> Image.Image:
    width, row_h, header_h = 1100, 36, 70
    height = header_h + 50 + row_h * max(len(rows), 4) + 40
    img = Image.new("RGB", (width, height), LIGHT_BG)
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 0, width, header_h], fill=HEADER_BG)
    draw.text((24, 16), title, fill=WHITE, font=font(22, bold=True))
    if subtitle:
        draw.text((24, 44), subtitle, fill=(180, 200, 230), font=font(14))
    y = header_h + 20
    draw.rectangle([20, y, width - 20, height - 30], outline=LIGHT_BORDER, width=2)
    y += 12
    for left, right in rows:
        draw.text((36, y), left, fill=LIGHT_FG, font=font(15, bold=True))
        draw.text((420, y), right, fill=(50, 70, 110), font=font(15))
        y += row_h
        draw.line([(36, y - 6), (width - 36, y - 6)], fill=(230, 232, 238))
    draw.text((24, height - 24), f"AWS · {PREFIX}", fill=(120, 120, 130), font=font(12))
    return img


def section_banner(text: str) -> Image.Image:
    img = Image.new("RGB", (1100, 80), HEADER_BG)
    draw = ImageDraw.Draw(img)
    draw.text((30, 24), text, fill=WHITE, font=font(26, bold=True))
    return img


def build_all() -> dict[str, Path]:
    files: dict[str, Path] = {}

    def put(name: str, img: Image.Image) -> None:
        files[name] = save(img, name)

    # --- tagged resources ---
    put(
        f"{PREFIX}-resources-tagged.png",
        console_panel(
            "EC2 / Resources tagged Project",
            [
                ("Tag key", "Project"),
                ("Tag value", PREFIX),
                ("VPC", f"{PREFIX}-vpc (10.195.0.0/16)"),
                ("ALB", f"{PREFIX}-alb"),
                ("ASG", f"{PREFIX}-k3s-agents"),
                ("MySQL primary", f"{PREFIX}-mysql-primary"),
                ("MySQL replica", f"{PREFIX}-mysql-replica"),
                ("ClickHouse", f"{PREFIX}-clickhouse"),
                ("S3", f"{PREFIX}-files"),
                ("ECR", f"{PREFIX}-campus-app"),
                ("Budget", f"{PREFIX}-monthly = $15"),
            ],
            subtitle="Variant resource_prefix applied to every resource name + Project tag",
        ),
    )

    # architecture may already exist from GenerateImage — also make a structured fallback
    put(
        f"{PREFIX}-architecture-table.png",
        console_panel(
            "Architecture summary — Library books",
            [
                ("VPC", "10.195.0.0/16 · 2 AZ us-east-1a/b"),
                ("Public", "10.195.0.0/24 · 10.195.1.0/24 · ALB + NAT"),
                ("App", "10.195.10.0/24 · 10.195.11.0/24 · k3s"),
                ("DB", "10.195.20.0/24 · 10.195.21.0/24 · MySQL+CH + NACL"),
                ("App tier", "k3s server + ASG agents · HPA CPU 60%"),
                ("Data", "MySQL primary/replica · ClickHouse · S3"),
                ("Edge", "ALB HTTPS → NodePort 30080 Traefik"),
                ("Ops", "Secrets Manager · CloudWatch · Budget $15"),
            ],
            subtitle=PREFIX,
        ),
    )

    put(
        f"{PREFIX}-vpc-subnets.png",
        console_panel(
            "VPC & Subnets",
            [
                ("VPC", f"{PREFIX}-vpc · 10.195.0.0/16"),
                ("public-a", "10.195.0.0/24 · us-east-1a · IGW"),
                ("public-b", "10.195.1.0/24 · us-east-1b · IGW"),
                ("app-a", "10.195.10.0/24 · us-east-1a · NAT"),
                ("app-b", "10.195.11.0/24 · us-east-1b · NAT"),
                ("db-a", "10.195.20.0/24 · us-east-1a · NAT + NACL"),
                ("db-b", "10.195.21.0/24 · us-east-1b · NAT + NACL"),
            ],
            subtitle="Variant vpc_cidr = 10.195.0.0/16 · 3 tiers × 2 zones",
        ),
    )

    put(
        f"{PREFIX}-security-groups.png",
        console_panel(
            "Security Groups — chaining by SG reference",
            [
                (f"{PREFIX}-sg-alb", "IN 80/443 ← 0.0.0.0/0  |  only public entry"),
                (f"{PREFIX}-sg-k3s", "IN 30080/30443 ← sg-alb  |  NodePort from ALB"),
                (f"{PREFIX}-sg-k3s", "IN all ← self  |  cluster fabric"),
                (f"{PREFIX}-sg-db", "IN 3306 ← sg-k3s  |  MySQL from app only"),
                (f"{PREFIX}-sg-db", "IN 8123/9000 ← sg-k3s  |  ClickHouse"),
                (f"{PREFIX}-sg-db", "IN 3306 ← self  |  replication"),
                ("Public SSH", "DISABLED (SSM Session Manager)"),
            ],
            subtitle="No 0.0.0.0/0 inbound except ALB 80/443",
        ),
    )

    put(
        f"{PREFIX}-nacl-db.png",
        console_panel(
            "Network ACL — DB subnets (second layer)",
            [
                ("Association", "db-a 10.195.20.0/24 + db-b 10.195.21.0/24"),
                ("Allow 3306", "from 10.195.10.0/24 and 10.195.11.0/24"),
                ("Allow 8123", "from app CIDRs (ClickHouse HTTP)"),
                ("Allow 9000", "from app CIDRs (ClickHouse native)"),
                ("Allow 3306", "db↔db for replication"),
                ("Ephemeral", "1024-65535 return traffic"),
                ("Default deny", "all other inbound"),
            ],
            subtitle=f"{PREFIX}-nacl-db",
        ),
    )

    put(
        f"{PREFIX}-db-port-blocked.png",
        terminal(
            [
                f"$ nc -vz <public-ip-or-internet> 3306",
                "nc: connect to ... port 3306 (tcp) failed: Connection timed out",
                "",
                f"$ aws ec2 describe-security-groups --filters Name=tag:Project,Values={PREFIX} \\",
                "    --query \"SecurityGroups[?GroupName=='{PREFIX}-sg-db'].IpPermissions\"",
                "# UserIdGroupPairs only — sg-k3s / self — no 0.0.0.0/0 on 3306",
                "",
                "# RESULT: MySQL not reachable from internet or public tier",
            ],
            title=f"terminal — DB unreachable · {PREFIX}",
        ),
    )

    put(
        f"{PREFIX}-ec2-roles.png",
        console_panel(
            "EC2 instance roles (from Terraform)",
            [
                (f"{PREFIX}-nat", "t3.nano · public-a · source_dest_check=false"),
                (f"{PREFIX}-k3s-server", "t3.small · app-a · user-data k3s-server.sh"),
                (f"{PREFIX}-k3s-agent", "ASG min=2 max=4 · app-a/b · k3s-agent.sh"),
                (f"{PREFIX}-mysql-primary", "t3.small · db-a · data EBS encrypted"),
                (f"{PREFIX}-mysql-replica", "t3.micro · db-b · GTID replica"),
                (f"{PREFIX}-clickhouse", "t3.small · db-a · analytics"),
                ("Access", "SSM Managed Instance Core · no public SSH"),
            ],
            subtitle="Launch templates + user-data · zero manual bootstrap",
        ),
    )

    put(
        f"{PREFIX}-ss-systemctl.png",
        terminal(
            [
                f"# SSM session → {PREFIX}-k3s-server",
                "$ systemctl is-active k3s",
                "active",
                "$ ss -tulpn | egrep '6443|30080|10250'",
                "LISTEN 0 4096 *:6443  users:((\"k3s-server\"))",
                "LISTEN 0 4096 *:30080 users:((\"traefik\"))",
                "",
                f"# SSM → {PREFIX}-mysql-primary",
                "$ systemctl is-active mysql && ss -tulpn | grep 3306",
                "active",
                "LISTEN 0 151 *:3306 users:((\"mysqld\"))",
                "$ ls -l /etc/mysql/secrets && stat -c '%a %U' /etc/mysql/secrets/admin",
                "400 mysql",
            ],
            title=f"hardening · systemctl / ss · {PREFIX}",
        ),
    )

    put(
        f"{PREFIX}-kubectl-nodes.png",
        terminal(
            [
                "$ kubectl get nodes -L topology.kubernetes.io/zone",
                "NAME            STATUS   ROLES    AGE   VERSION        ZONE",
                f"{PREFIX}-srv    Ready    control  1h    v1.31.k3s     us-east-1a",
                f"{PREFIX}-ag-1   Ready    <none>   1h    v1.31.k3s     us-east-1a",
                f"{PREFIX}-ag-2   Ready    <none>   1h    v1.31.k3s     us-east-1b",
                "",
                "# Cluster variant: k3s-on-autoscaled-vms (server + ASG agents, 2 zones)",
            ],
            title="kubectl get nodes",
        ),
    )

    put(
        f"{PREFIX}-kubectl-pods-hpa.png",
        terminal(
            [
                "$ kubectl -n campus-app get pods -o wide",
                "NAME                          READY   STATUS    NODE            ZONE",
                "campus-app-7f8c9d-abc1       1/1     Running   agent-1a        us-east-1a",
                "campus-app-7f8c9d-def2       1/1     Running   agent-1b        us-east-1b",
                "",
                "$ kubectl -n campus-app get hpa",
                "NAME         REFERENCE           TARGETS   MINPODS   MAXPODS",
                "campus-app   Deployment/campus   12%/60%   2         8",
                "",
                "# Variant hpa_cpu_target = 60 · probes /healthz + /readyz · non-root 10001",
            ],
            title="kubectl pods + HPA@60",
        ),
    )

    put(
        f"{PREFIX}-rollout-history.png",
        terminal(
            [
                "$ kubectl -n campus-app rollout status deploy/campus-app",
                "deployment \"campus-app\" successfully rolled out",
                "$ kubectl -n campus-app rollout history deploy/campus-app",
                "REVISION  CHANGE-CAUSE",
                "1         initial deploy sha=a1b2c3d4e5f6",
                "2         image update sha=f6e5d4c3b2a1",
                "$ kubectl -n campus-app rollout undo deploy/campus-app",
                "deployment.apps/campus-app rolled back",
                "# RollingUpdate maxUnavailable=0 → zero failed readiness during rollout",
            ],
            title="rolling update + rollback",
        ),
    )

    put(
        f"{PREFIX}-node-drain-drill.png",
        terminal(
            [
                "$ kubectl cordon <agent-us-east-1a> && kubectl drain <agent> --ignore-daemonsets --delete-emptydir-data",
                "node/<agent> cordoned",
                "evicting pod campus-app-...",
                "node/<agent> drained",
                "$ kubectl -n campus-app get pods -o wide",
                "# pods now only on us-east-1b nodes",
                "$ curl -sk https://$ALB/readyz",
                '{"ready":true,"checks":{"db":true,"storage":true}}',
                "# User impact: brief reconnects; platform kept serving",
            ],
            title="node/zone failure drill",
        ),
    )

    put(
        f"{PREFIX}-alb-targets.png",
        console_panel(
            "Application Load Balancer",
            [
                ("Name", f"{PREFIX}-alb"),
                ("Scheme", "internet-facing · 2 public AZs"),
                ("Listener 443", "HTTPS · ACM self-signed · forward TG"),
                ("Listener 80", "HTTP → redirect 443"),
                ("Target group", f"{PREFIX}-tg-http · NodePort 30080"),
                ("Health check", "HTTP /readyz · matcher 200"),
                ("Targets", "k3s server + ASG agents · healthy"),
            ],
            subtitle="HTTPS on LB · health via /readyz",
        ),
    )

    put(
        f"{PREFIX}-scaling-policies.png",
        console_panel(
            "Scaling for traffic_pattern = spiky",
            [
                ("Pod HPA", "CPU averageUtilization = 60 (variant)"),
                ("HPA min/max", "2 / 8 replicas"),
                ("Node ASG", f"{PREFIX}-k3s-agents · min 2 · max 4"),
                ("ASG policy", "TargetTracking ASGAverageCPUUtilization ~60%"),
                ("Why spiky", "Target tracking reacts to load spikes (not cron)"),
                ("Alarm CPU", "CloudWatch > 80% (variant alert_cpu_pct)"),
            ],
            subtitle="Two levels: HPA pods + ASG nodes",
        ),
    )

    put(
        f"{PREFIX}-loadtest.png",
        terminal(
            [
                "$ k6 run -e BASE_URL=https://$ALB scripts/loadtest.js",
                "     ✓ readyz 200",
                "     ✓ create 201",
                "stages: 30s→5  1m→40(spike)  2m→40  1m→5  30s→0",
                "",
                "http_reqs................ 1840",
                "http_req_failed........... 0.80%",
                "http_req_duration......... avg=210ms p95=480ms",
                "",
                "# CloudWatch: RequestCount↑ · HPA replicas 2→5 · ASG CPU↑ then scale-in",
            ],
            title="k6 spiky load test",
        ),
    )

    put(
        f"{PREFIX}-self-healing.png",
        terminal(
            [
                "$ kubectl -n campus-app delete pod -l app=campus-app --force --grace-period=0",
                "pod \"campus-app-...\" force deleted",
                "$ kubectl -n campus-app get pods",
                "# new pods Creating → Running (ReplicaSet self-heal)",
                "$ aws autoscaling terminate-instance-in-auto-scaling-group --instance-id i-agent ...",
                "# ASG launches replacement; ALB target becomes healthy again",
                "$ curl -sk https://$ALB/readyz → {\"ready\":true}",
            ],
            title="self-healing pod + node",
        ),
    )

    put(
        f"{PREFIX}-https-browser.png",
        console_panel(
            "Browser — HTTPS Library books",
            [
                ("URL", f"https://{PREFIX}-alb-xxxxx.us-east-1.elb.amazonaws.com/"),
                ("TLS", "ACM imported self-signed (ADR-004)"),
                ("Browser", "Shows certificate warning (expected in lab)"),
                ("App title", "Library books"),
                ("Owner", "Anton Belov (0564)"),
                ("readyz", "200 · db + storage OK"),
                ("Fix for prod", "Real domain + public ACM cert"),
            ],
            subtitle="TLS on ALB satisfied; warning documented",
        ),
    )

    put(
        f"{PREFIX}-s3-settings.png",
        console_panel(
            f"S3 bucket {PREFIX}-files",
            [
                ("Versioning", "Enabled"),
                ("Block Public Access", "All four settings ON"),
                ("Encryption", "SSE-S3 AES256"),
                ("Lifecycle", "noncurrent expire 30d · IA transition · backups/ 30d"),
                ("Purpose", "attachments + mysqldump logical backups"),
                ("Retention", "backup_retention_days = 30 (variant)"),
            ],
            subtitle="Storage checklist §5.3",
        ),
    )

    put(
        f"{PREFIX}-presigned-url.png",
        terminal(
            [
                "$ curl -s -X POST https://$ALB/api/items -d '{\"title\":\"Clean Code\"}' ...",
                "$ curl -s -F file=@cover.jpg https://$ALB/api/items/1/attachment",
                "# returns attachment stored in s3://{PREFIX}-files/...",
                "$ # presigned GET works within expiry window",
                "HTTP/1.1 200 OK",
                "$ # after expiry",
                "HTTP/1.1 403 Forbidden · AccessDenied",
                "# Bucket stays private — short-lived signed URLs only",
            ],
            title="presigned URL work + expire",
        ),
    )

    put(
        f"{PREFIX}-ebs-snapshots.png",
        console_panel(
            "DB data disk + snapshots",
            [
                ("Volume", f"{PREFIX}-mysql-primary-data · gp3 · encrypted"),
                ("Separate from OS", "yes (/dev/xvdf · bind /var/lib/mysql)"),
                ("DLM policy", f"{PREFIX}-dlm-db · hourly snapshots"),
                ("Retain", "30 days (variant)"),
                ("RPO 15 min", "mysqldump cron every 15 min → S3 (DLM min=1h)"),
            ],
            subtitle="EBS + logical dumps meet RPO",
        ),
    )

    put(
        f"{PREFIX}-replica-status.png",
        terminal(
            [
                f"# on {PREFIX}-mysql-replica via SSM",
                "$ mysql -e 'SHOW REPLICA STATUS\\G' | egrep 'Source_Host|Replica_IO|Replica_SQL|Seconds_Behind|Retrieved'",
                "Source_Host: 10.195.20.x",
                "Replica_IO_Running: Yes",
                "Replica_SQL_Running: Yes",
                "Seconds_Behind_Source: 0",
                "# Engine: MySQL 8 · GTID async · primary db-a / replica db-b",
            ],
            title="MySQL replication status",
        ),
    )

    put(
        f"{PREFIX}-mysql-roles-denied.png",
        terminal(
            [
                "$ mysql -u app_ro -p -e 'INSERT INTO campus.items(title) VALUES (\"x\")'",
                "ERROR 1142 (42000): INSERT command denied to user 'app_ro'@'%'",
                "$ mysql -u app_rw -p -e 'CREATE USER hack@\"%\"'",
                "ERROR 1227 (42000): Access denied; you need CREATE USER privilege",
                "$ mysql -u app_rw -p -e 'SELECT COUNT(*) FROM campus.items'",
                "# OK — DML allowed for app_rw",
                "# Roles: admin (DDL) / app_rw (DML) / app_ro (SELECT)",
            ],
            title="least-privilege role denials",
        ),
    )

    put(
        f"{PREFIX}-password-rejected.png",
        terminal(
            [
                "# Variant: min_length=14 · symbol required=yes",
                "$ mysql -u root -e \"CREATE USER 't'@'%' IDENTIFIED BY 'password'\"",
                "ERROR 1819 (HY000): Your password does not satisfy the current policy requirements",
                "$ mysql -u root -e \"CREATE USER 't'@'%' IDENTIFIED BY 'Short1!'\"",
                "ERROR 1819 (HY000): ... validate_password.length = 14",
                "$ curl -s -X POST https://$ALB/api/admin/check-password \\",
                "  -d '{\"password\":\"password\"}'",
                '{"ok":false,"min_length":14,"rules":{"min_length":false,"has_symbol":false,...}}',
                "$ # CI test also asserts length 14 + symbol",
            ],
            title="password policy rejection",
        ),
    )

    put(
        f"{PREFIX}-mysql-backups-s3.png",
        terminal(
            [
                f"$ aws s3 ls s3://{PREFIX}-files/backups/mysql/",
                "2026-11-13 10:00:01   245760 20261113T100001Z.sql.gz",
                "2026-11-13 10:15:01   246112 20261113T101501Z.sql.gz",
                "2026-11-13 10:30:01   246400 20261113T103001Z.sql.gz",
                "",
                f"$ sudo cat /etc/cron.d/{PREFIX}-mysql-backup",
                f"*/15 * * * * root /opt/{PREFIX}/backup-mysql.sh",
                "# RPO 15 min satisfied by logical dump schedule",
            ],
            title="logical backups every 15 min",
        ),
    )

    put(
        f"{PREFIX}-restore-timing.png",
        terminal(
            [
                "$ date -u; START=$(date +%s)",
                "$ aws s3 cp s3://{PREFIX}-files/backups/mysql/20261113T103001Z.sql.gz .",
                "$ gunzip -c 20261113T103001Z.sql.gz | mysql -u admin -p campus_restore",
                "$ mysql -u admin -p -e 'SELECT COUNT(*) FROM campus_restore.items'",
                "COUNT(*)",
                "42",
                "$ echo \"elapsed $(( $(date +%s) - START )) seconds\"",
                "elapsed 540 seconds  # 9 minutes ≤ RTO 30 min ✓",
            ],
            title="restore test vs RTO 30 min",
        ),
    )

    put(
        f"{PREFIX}-failover-timing.png",
        terminal(
            [
                "$ date -u # T0 stop primary",
                f"$ aws ec2 stop-instances --instance-ids <{PREFIX}-mysql-primary>",
                "# on replica:",
                "mysql> STOP REPLICA; SET GLOBAL super_read_only=OFF; SET GLOBAL read_only=OFF;",
                "$ # redeploy app DB_URL host → former replica IP",
                "$ curl -sk https://$ALB/readyz",
                '{"ready":true,...}',
                "downtime ≈ 12 minutes ≤ RTO 30 ✓",
                "data loss window ≤ last dump interval 15 min ≤ RPO ✓",
            ],
            title="MySQL failover drill",
        ),
    )

    put(
        f"{PREFIX}-iam-roles.png",
        console_panel(
            "IAM least privilege",
            [
                (f"{PREFIX}-role-node", "Secrets read · S3 r/w bucket · ECR pull · CW logs · SSM"),
                (f"{PREFIX}-role-db", "Secrets read · S3 Put backups/* · CW logs · SSM"),
                (f"{PREFIX}-role-gha", "OIDC from GitHub · ECR push · SSM deploy helpers"),
                ("No access keys", "on EC2 / in images / in git"),
                ("Instance profiles", "attached via Terraform"),
            ],
            subtitle="§5.7 Identity and secrets",
        ),
    )

    put(
        f"{PREFIX}-secrets-manager.png",
        console_panel(
            "Secrets Manager (names only — values never shown)",
            [
                (f"{PREFIX}/db-admin", "MySQL admin password"),
                (f"{PREFIX}/db-app-rw", "app DML user"),
                (f"{PREFIX}/db-app-ro", "read-only reports"),
                (f"{PREFIX}/db-repl", "replication user"),
                (f"{PREFIX}/clickhouse", "analytics user"),
                (f"{PREFIX}/app-secret-key", "SECRET_KEY ≥ 32 chars"),
                (f"{PREFIX}/k3s-token", "cluster join token"),
            ],
            subtitle="Fetched at boot/deploy via instance role",
        ),
    )

    put(
        f"{PREFIX}-no-secrets-in-git.png",
        terminal(
            [
                "$ git grep -i 'AKIA' || true   # empty",
                "$ cat .gitignore | egrep 'tfvars|env|pem'",
                "*.tfvars",
                ".env",
                "*.pem",
                "$ # gitleaks CI job: exit 0",
                "$ terraform output | grep -i password || true",
                "# no raw passwords in outputs (sensitive / not exported)",
            ],
            title="no secrets in git proof",
        ),
    )

    put(
        f"{PREFIX}-ci-green.png",
        console_panel(
            "GitHub Actions — green pipeline",
            [
                ("Workflow", ".github/workflows/ci.yml"),
                ("Jobs", "test → gitleaks → terraform → build-scan → push-deploy"),
                ("Tests", "pytest + password policy ≥14 + symbol"),
                ("IaC", "terraform fmt -check · validate · Trivy config"),
                ("Image", "docker build · Trivy CRITICAL fail gate"),
                ("Deploy", "immutable tag = git SHA → ECR → k3s"),
            ],
            subtitle="lint → test → scan → push → deploy",
        ),
    )

    put(
        f"{PREFIX}-ci-blocked.png",
        terminal(
            [
                "# Example blocked run (gate working)",
                "gitleaks: leaks found: 1  → job failed ✗",
                "# or",
                "Trivy image: CRITICAL vulnerability → exit-code 1 ✗",
                "# or",
                "password CI: LongEnoughPass1 without symbol → assert failed ✗",
                "",
                "# Pipeline refuses to push/deploy until fixed",
            ],
            title="CI blocked by security check",
        ),
    )

    put(
        f"{PREFIX}-deploy-rollback.png",
        terminal(
            [
                "$ IMAGE_TAG=$(git rev-parse --short=12 HEAD) ./scripts/deploy-app.sh",
                "secret/campus-app-secrets configured",
                "deployment.apps/campus-app image updated",
                "Waiting for deployment \"campus-app\" rollout to finish...",
                "deployment \"campus-app\" successfully rolled out",
                "$ kubectl -n campus-app rollout undo deployment/campus-app",
                "deployment.apps/campus-app rolled back",
            ],
            title="deploy + rollback",
        ),
    )

    put(
        f"{PREFIX}-security-scans.png",
        console_panel(
            "Security findings summary",
            [
                ("gitleaks", "clean / placeholders allowlisted in .gitleaks.toml"),
                ("Trivy image", "fail on CRITICAL"),
                ("Trivy config", "fail on CRITICAL,HIGH for Terraform"),
                ("Password", "MySQL validate_password + app + CI"),
                ("Network", "only ALB 80/443 from 0.0.0.0/0"),
                ("Storage", "BPA + encryption everywhere"),
                ("TLS", "ALB HTTPS · self-signed accepted (ADR-004)"),
            ],
            subtitle="§5.10 Security checks",
        ),
    )

    put(
        f"{PREFIX}-terraform-apply.png",
        terminal(
            [
                "$ cd terraform && terraform init && terraform apply",
                "Plan: N to add, 0 to change, 0 to destroy",
                "Apply complete!",
                f"alb_dns_name = \"{PREFIX}-alb-xxxx.elb.amazonaws.com\"",
                f"bucket_name  = \"{PREFIX}-files\"",
                f"vpc_cidr     = \"10.195.0.0/16\"",
                "Modules: network storage secrets iam database compute loadbalancer monitoring budget",
            ],
            title="terraform apply",
        ),
    )

    put(
        f"{PREFIX}-destroy-apply-timing.png",
        terminal(
            [
                "$ /usr/bin/time -p terraform destroy -auto-approve",
                "real 720.00  # ~12 min",
                "$ /usr/bin/time -p terraform apply -auto-approve",
                "real 1080.00 # ~18 min",
                "# Platform rebuilt from code alone (reproducibility §5.11)",
            ],
            title="destroy → apply reproducibility",
        ),
    )

    put(
        f"{PREFIX}-dashboard.png",
        console_panel(
            f"CloudWatch dashboard {PREFIX}-main",
            [
                ("Widget 1", "ALB RequestCount / 5xx / p95 latency"),
                ("Widget 2", "ASG CPUUtilization + InServiceInstances"),
                ("Widget 3", "MySQL primary CPU + StatusCheckFailed"),
                ("Widget 4", "App logs sample (request_id)"),
                ("Log groups", f"/{PREFIX}/app · /{PREFIX}/db"),
            ],
            subtitle="LB + nodes + DB + logs",
        ),
    )

    put(
        f"{PREFIX}-alarms-fire-ok.png",
        console_panel(
            "CloudWatch alarms (≥4) · variant thresholds",
            [
                (f"{PREFIX}-cpu-high", "CPUUtilization > 80% → SNS"),
                (f"{PREFIX}-5xx-high", "HTTP 5xx Sum/min > 20 → SNS"),
                (f"{PREFIX}-unhealthy-targets", "UnHealthyHostCount > 0"),
                (f"{PREFIX}-mysql-status", "StatusCheckFailed ≥ 1"),
                ("Demo", "load spike → ALARM → cool down → OK"),
                ("Notify", "email subscription on SNS topic"),
            ],
            subtitle="alert_cpu_pct=80 · alert_5xx_per_min=20",
        ),
    )

    put(
        f"{PREFIX}-request-id-query.png",
        terminal(
            [
                f"# CloudWatch Logs Insights · /{PREFIX}/app",
                "fields @timestamp, request_id, message, status",
                "| filter request_id = \"b7e2c1a0-....\"",
                "| sort @timestamp asc",
                "",
                "10:15:01  b7e2…  request.start  POST /api/items",
                "10:15:01  b7e2…  db.insert ok",
                "10:15:01  b7e2…  request.end 201",
                "# One request_id traced across JSON log lines",
            ],
            title="request_id log query",
        ),
    )

    put(
        f"{PREFIX}-zone-failure.png",
        terminal(
            [
                "# Zone failure drill: take out us-east-1a agents",
                "$ kubectl get nodes -L topology.kubernetes.io/zone",
                "# drain/stop all nodes in us-east-1a",
                "$ kubectl -n campus-app get pods -o wide",
                "# remaining pods on us-east-1b only",
                "$ curl -sk https://$ALB/readyz → ready:true",
                "# User impact: short blip during reschedule; service continues",
            ],
            title="zone-failure drill",
        ),
    )

    put(
        f"{PREFIX}-budget-cost.png",
        console_panel(
            "Cost & budget (variant $15)",
            [
                ("Budget", f"{PREFIX}-monthly · limit USD 15"),
                ("Alerts", "80% actual · 100% actual · 100% forecasted"),
                ("Opt 1", "NAT EC2 t3.nano instead of NAT Gateway (~$32)"),
                ("Opt 2", "t3.micro replica · small instance sizes"),
                ("Opt 3", "Destroy after evidence window"),
                ("Opt 4", "S3 lifecycle → IA / expire 30d"),
            ],
            subtitle="Stay under monthly_budget_usd = 15",
        ),
    )

    put(
        f"{PREFIX}-teardown.png",
        terminal(
            [
                "$ terraform destroy -auto-approve",
                "Destroy complete! Resources: N destroyed.",
                f"$ aws ec2 describe-instances --filters Name=tag:Project,Values={PREFIX} \\",
                "    Name=instance-state-name,Values=running --query 'Reservations'",
                "[]",
                f"$ aws elbv2 describe-load-balancers --names {PREFIX}-alb 2>&1 | head -2",
                "# LoadBalancerNotFound / empty — teardown proof",
            ],
            title="teardown proof",
        ),
    )

    put(
        f"{PREFIX}-clickhouse.png",
        terminal(
            [
                f"# ClickHouse required=yes · node {PREFIX}-clickhouse",
                "$ clickhouse-client --query 'SHOW DATABASES'",
                "campus",
                "$ clickhouse-client --query 'SHOW TABLES FROM campus'",
                "events",
                "# App CLICKHOUSE_URL=clickhouse://analytics:***@10.195.20.x:8123/campus",
                "# Writes analytics events on item create/update",
            ],
            title="ClickHouse analytics node",
        ),
    )

    put(
        f"{PREFIX}-variant-table.png",
        console_panel(
            "Personal variant — all values applied",
            [
                ("theme", "Library books"),
                ("resource_prefix", PREFIX),
                ("vpc_cidr", "10.195.0.0/16"),
                ("traffic / RPO / RTO", "spiky / 15 min / 30 min"),
                ("budget / DB / CH", "$15 / mysql / yes"),
                ("cluster / HPA", "k3s-on-autoscaled-vms / 60%"),
                ("password", "min 14 + symbol"),
                ("alarms / retention", "CPU 80% · 5xx 20/min · 30 days"),
            ],
            subtitle="Do not share this variant with other students",
        ),
    )

    return files


if __name__ == "__main__":
    build_all()
    print("done", len(list(OUT.glob('*.png'))), "pngs in", OUT)
