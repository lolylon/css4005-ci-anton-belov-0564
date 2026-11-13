#!/usr/bin/env python3
"""Build REPORT.docx: every evidence block = action + screenshot slot + explanation."""

from pathlib import Path

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

OUT = Path(__file__).resolve().parents[1] / "REPORT.docx"
PREFIX = "ci-anton-belov-0564"


def set_cell_shading(cell, color_hex: str) -> None:
    shading = OxmlElement("w:shd")
    shading.set(qn("w:fill"), color_hex)
    shading.set(qn("w:val"), "clear")
    cell._tePr = cell._tc.get_or_add_tcPr()
    cell._tc.get_or_add_tcPr().append(shading)


def add_screenshot_block(doc: Document, title: str, how: str, explanation: str, evidence_file: str) -> None:
    doc.add_heading(title, level=3)

    p = doc.add_paragraph()
    run = p.add_run("What I did / command:")
    run.bold = True
    doc.add_paragraph(how)

    evidence_path = Path(__file__).resolve().parents[1] / "docs" / "evidence" / evidence_file
    if evidence_path.exists() and evidence_path.suffix.lower() in {".png", ".jpg", ".jpeg"}:
        pic = doc.add_paragraph()
        pic.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run = pic.add_run()
        run.add_picture(str(evidence_path), width=Cm(15.5))
        cap = doc.add_paragraph()
        cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
        cr = cap.add_run(f"Figure: docs/evidence/{evidence_file}")
        cr.italic = True
        cr.font.size = Pt(9)
        cr.font.color.rgb = RGBColor(0x66, 0x66, 0x66)
    else:
        box = doc.add_paragraph()
        box.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run = box.add_run(
            f"[ PASTE SCREENSHOT HERE ]\n"
            f"File hint: docs/evidence/{evidence_file}\n"
            f"Must show prefix «{PREFIX}» in the UI or command output."
        )
        run.italic = True
        run.font.color.rgb = RGBColor(0x66, 0x66, 0x66)
        run.font.size = Pt(11)

        table = doc.add_table(rows=1, cols=1)
        table.style = "Table Grid"
        cell = table.rows[0].cells[0]
        cell.text = (
            f"\n\n          >>> INSERT IMAGE: {evidence_file} <<<\n"
            f"          (AWS Console / terminal / kubectl / browser)\n\n"
        )
        set_cell_shading(cell, "FFF3CD")
    doc.add_paragraph()

    p = doc.add_paragraph()
    run = p.add_run("What happened (explanation):")
    run.bold = True
    doc.add_paragraph(explanation)
    doc.add_paragraph("—" * 40)


def add_table(doc: Document, headers: list[str], rows: list[list[str]]) -> None:
    table = doc.add_table(rows=1 + len(rows), cols=len(headers))
    table.style = "Table Grid"
    for i, h in enumerate(headers):
        table.rows[0].cells[i].text = h
        for p in table.rows[0].cells[i].paragraphs:
            for r in p.runs:
                r.bold = True
    for r_i, row in enumerate(rows):
        for c_i, val in enumerate(row):
            table.rows[r_i + 1].cells[c_i].text = val
    doc.add_paragraph()


def build() -> None:
    doc = Document()
    section = doc.sections[0]
    section.top_margin = Cm(1.5)
    section.bottom_margin = Cm(1.5)
    section.left_margin = Cm(2)
    section.right_margin = Cm(2)

    title = doc.add_heading("CSS4005 Final Project Report", level=0)
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    sub = doc.add_paragraph(
        "Library books platform · AWS · resource prefix ci-anton-belov-0564\n"
        "Format: for each step — action, screenshot, explanation underneath.\n"
        "Submit as PDF (Word → Save As → PDF). Keep these section headings (rubric)."
    )
    sub.alignment = WD_ALIGN_PARAGRAPH.CENTER

    # --- 0 Cover ---
    doc.add_heading("0. Cover", level=1)
    add_table(
        doc,
        ["Field", "Value"],
        [
            ["Student", "Anton Belov (0564) — FILL full student ID"],
            ["Course / stream", "CSS4005 — FILL ENG-1 / ENG-2"],
            ["Track", "AWS (own account)"],
            ["Region / zones", "us-east-1 · us-east-1a, us-east-1b"],
            ["Repository", "FILL https://github.com/USER/REPO (public)"],
            ["Demo video (if torn down)", "FILL or N/A"],
            ["Submission date", "FILL"],
        ],
    )

    # --- 1 Variant ---
    doc.add_heading("1. Variant applied", level=1)
    doc.add_paragraph(
        "Every row below is applied in code. After deploy, add a screenshot proving it where noted."
    )
    add_table(
        doc,
        ["Field", "My value", "Where applied"],
        [
            ["theme", "Library books", "APP_NAME / items = books"],
            ["resource_prefix", PREFIX, "All resource names + Project tag"],
            ["vpc_cidr", "10.195.0.0/16", "VPC + subnet CIDRs"],
            ["traffic_pattern", "spiky", "ASG target tracking + k6 spike"],
            ["rpo", "15 min", "mysqldump cron every 15 min"],
            ["rto", "30 min", "restore + failover drills"],
            ["monthly_budget_usd", "15", "AWS Budget alert"],
            ["db_engine", "mysql", "Primary + replica VMs"],
            ["clickhouse_required", "yes", "ClickHouse VM + CLICKHOUSE_URL"],
            ["cluster", "k3s-on-autoscaled-vms", "server + agent ASG"],
            ["hpa_cpu_target", "60", "deploy/k8s/hpa.yaml"],
            ["password_min_length", "14", "MySQL + app + CI"],
            ["password_require_symbol", "yes", "validate_password + checker"],
            ["alert_cpu_pct", "80", "CloudWatch CPU alarm"],
            ["alert_5xx_per_min", "20", "CloudWatch 5xx alarm"],
            ["backup_retention_days", "30", "S3 lifecycle + DLM"],
        ],
    )
    add_screenshot_block(
        doc,
        "1.1 Proof: resources named with prefix",
        "AWS Console → EC2 → Instances (or VPC → Your VPCs). Filter by tag Project = ci-anton-belov-0564.",
        "All major resources carry the personal prefix/tag so graders can see this is my variant, not a shared copy.",
        f"{PREFIX}-resources-tagged.png",
    )

    # --- 2 Architecture ---
    doc.add_heading("2. Architecture", level=1)
    doc.add_heading("2.1 Diagram", level=2)
    add_screenshot_block(
        doc,
        "Architecture diagram",
        "Export docs/diagrams/architecture.mmd (Mermaid) to PNG, or draw in draw.io matching the live build.",
        "Diagram shows 2 AZs, public/app/db tiers, ALB, NAT, k3s, MySQL primary/replica, ClickHouse, S3, Secrets Manager, ECR, CloudWatch.",
        f"{PREFIX}-architecture.png",
    )

    doc.add_heading("2.2 Shared responsibility", level=2)
    doc.add_paragraph(
        "AWS: physical infrastructure, hypervisor, managed ALB/S3/IAM/Secrets Manager/CloudWatch APIs. "
        "Me: VPC design, SG/NACL, NAT instance, OS hardening, self-hosted MySQL/ClickHouse (backups, replication, failover), "
        "k3s, app deploy, CI/CD, alarms, cost control. Self-hosting the DB moves patching/failover from AWS RDS onto me."
    )

    doc.add_heading("2.3 ADRs (≥ 4)", level=2)
    for adr, summary in [
        ("ADR-001 Single NAT instance", "NAT Gateway ~$32/mo exceeds $15 budget → one t3.nano NAT; AZ SPOF accepted for lab."),
        ("ADR-002 MySQL async GTID", "Primary+replica; RPO via 15-min mysqldump; hourly EBS snapshots."),
        ("ADR-003 k3s on ASG", "Variant cluster type; HPA 60% + ASG target tracking for spiky traffic."),
        ("ADR-004 Self-signed TLS on ALB", "No custom domain → ACM import; browser warning expected."),
    ]:
        doc.add_paragraph(f"{adr}: {summary}", style="List Bullet")

    # --- 3 Networking ---
    doc.add_heading("3. Networking", level=1)
    doc.add_paragraph("Subnet plan:")
    add_table(
        doc,
        ["Tier", "Zone", "CIDR", "Route"],
        [
            ["public", "us-east-1a", "10.195.0.0/24", "IGW"],
            ["public", "us-east-1b", "10.195.1.0/24", "IGW"],
            ["app", "us-east-1a", "10.195.10.0/24", "NAT ENI"],
            ["app", "us-east-1b", "10.195.11.0/24", "NAT ENI"],
            ["db", "us-east-1a", "10.195.20.0/24", "NAT ENI"],
            ["db", "us-east-1b", "10.195.21.0/24", "NAT ENI"],
        ],
    )

    add_screenshot_block(
        doc,
        "3.1 VPC and subnets",
        "AWS Console → VPC → Your VPCs / Subnets. Show VPC 10.195.0.0/16 and six subnets named with prefix.",
        "Network matches the variant CIDR and 3-tier × 2-AZ design required by the assignment.",
        f"{PREFIX}-vpc-subnets.png",
    )
    add_screenshot_block(
        doc,
        "3.2 Security group chaining",
        "Console → Security Groups for sg-alb, sg-k3s, sg-db. Show inbound rules (ALB 80/443 from internet; k3s from ALB SG; DB from k3s SG).",
        "Chaining is by security-group reference, not by opening the whole VPC CIDR. Only the ALB has 0.0.0.0/0 inbound on 80/443.",
        f"{PREFIX}-security-groups.png",
    )
    add_screenshot_block(
        doc,
        "3.3 NACL on DB subnets (second layer)",
        "VPC → Network ACLs → ci-anton-belov-0564-nacl-db. Show allow MySQL/ClickHouse only from app CIDRs.",
        "Stateless second layer: even if an SG is misconfigured, DB ports stay limited to app subnet CIDRs.",
        f"{PREFIX}-nacl-db.png",
    )
    add_screenshot_block(
        doc,
        "3.4 Evidence: DB port unreachable from public / internet",
        "From a public host or your laptop: nc -vz <mysql-primary-private-ip> 3306 (or Test-NetConnection). Also try from a public-subnet instance if you have one.",
        "Connection times out / fails. Proves MySQL is not exposed to the internet or the public tier — only app SG can reach 3306.",
        f"{PREFIX}-db-port-blocked.png",
    )

    # --- 4 Compute / k8s ---
    doc.add_heading("4. Compute, Linux and the Kubernetes cluster", level=1)
    doc.add_paragraph(
        "Cluster type: k3s-on-autoscaled-vms. Server EC2 + agent ASG (min 2) across app subnets. "
        "User-data: scripts/k3s-server.sh, k3s-agent.sh, mysql-*.sh, clickhouse.sh. Access via SSM (no public SSH)."
    )
    add_screenshot_block(
        doc,
        "4.1 Launch template / instances",
        "EC2 → Launch Templates + Instances tagged Role=k3s-server / k3s-agent / mysql-primary / mysql-replica / clickhouse.",
        "Every role boots from Terraform + user-data with no manual SSH install steps.",
        f"{PREFIX}-ec2-roles.png",
    )
    add_screenshot_block(
        doc,
        "4.2 Hardening: ss -tulpn and systemctl (via SSM)",
        "aws ssm start-session --target <instance-id> then: ss -tulpn; systemctl status k3s mysql clickhouse-server",
        "Only required ports listen; services run under package users / non-root app; SSM used instead of public SSH.",
        f"{PREFIX}-ss-systemctl.png",
    )
    add_screenshot_block(
        doc,
        "4.3 kubectl get nodes (zones)",
        "kubectl get nodes -L topology.kubernetes.io/zone",
        "Nodes span both availability zones with the topology label used for pod spreading.",
        f"{PREFIX}-kubectl-nodes.png",
    )
    add_screenshot_block(
        doc,
        "4.4 Pods, Deployment, HPA@60",
        "kubectl -n campus-app get pods -o wide; kubectl -n campus-app get deploy,hpa; cat deploy/k8s/hpa.yaml (averageUtilization: 60)",
        "≥2 replicas, probes on /healthz and /readyz, non-root, HPA target matches variant 60%.",
        f"{PREFIX}-kubectl-pods-hpa.png",
    )
    add_screenshot_block(
        doc,
        "4.5 Rolling update + rollback",
        "Deploy new image tag; kubectl -n campus-app rollout status deploy/campus-app; kubectl rollout history; then kubectl rollout undo …",
        "RollingUpdate keeps readiness; undo restores previous revision — proves CI/CD rollback path.",
        f"{PREFIX}-rollout-history.png",
    )
    add_screenshot_block(
        doc,
        "4.6 Node / zone failure drill",
        "kubectl cordon+drain one agent OR stop the EC2; watch pods reschedule; curl ALB /readyz.",
        "Workloads move to remaining nodes; site keeps answering. User impact: brief blips at most, no long outage.",
        f"{PREFIX}-node-drain-drill.png",
    )

    # --- 5 LB / AS ---
    doc.add_heading("5. Load balancing and auto scaling", level=1)
    add_screenshot_block(
        doc,
        "5.1 ALB listeners + target health (/readyz)",
        "EC2 → Load Balancers → ci-anton-belov-0564-alb → Listeners (443 HTTPS, 80 redirect) + Target Group health.",
        "HTTPS terminates on ALB (self-signed ACM). Health checks hit /readyz through Traefik NodePort 30080.",
        f"{PREFIX}-alb-targets.png",
    )
    add_screenshot_block(
        doc,
        "5.2 Spiky scaling: HPA + ASG target tracking",
        "Show ASG scaling policy (target tracking CPU) and HPA YAML 60%. Explain spiky → target tracking (not scheduled).",
        "Pods scale first on CPU 60%; nodes scale when ASG average CPU rises — fits spiky traffic pattern.",
        f"{PREFIX}-scaling-policies.png",
    )
    add_screenshot_block(
        doc,
        "5.3 Load test graphs (k6 + CloudWatch)",
        "k6 run -e BASE_URL=https://$ALB scripts/loadtest.js ; capture k6 summary + CloudWatch RequestCount / CPU / InService instances.",
        "Spike stages raise load; metrics show scale-out then scale-in after the spike ends.",
        f"{PREFIX}-loadtest.png",
    )
    add_screenshot_block(
        doc,
        "5.4 Self-healing (pod kill + node terminate)",
        "kubectl delete pod … ; terminate one agent EC2; curl /readyz during the event.",
        "Kubernetes recreates the pod; ASG launches a replacement node; ALB continues serving healthy targets.",
        f"{PREFIX}-self-healing.png",
    )
    add_screenshot_block(
        doc,
        "5.5 HTTPS / browser certificate warning",
        "Open https://<alb-dns>/ in browser; screenshot the warning page and then the app home (Library books).",
        "Self-signed cert satisfies TLS-on-LB for the lab; a real domain + ACM public cert would remove the warning (ADR-004).",
        f"{PREFIX}-https-browser.png",
    )

    # --- 6 Storage ---
    doc.add_heading("6. Storage", level=1)
    add_screenshot_block(
        doc,
        "6.1 S3 bucket: versioning, BPA, encryption, lifecycle",
        "S3 → ci-anton-belov-0564-files → Properties/Permissions/Management. Or aws s3api get-bucket-lifecycle-configuration …",
        "Versioning on, Block Public Access on, AES256, lifecycle expires noncurrent/backups at 30 days and transitions to IA.",
        f"{PREFIX}-s3-settings.png",
    )
    add_screenshot_block(
        doc,
        "6.2 Presigned URL works then expires",
        "Upload attachment via API; open presigned URL; wait past expiry; reload and show AccessDenied.",
        "Objects are private; short-lived URLs allow download without making the bucket public.",
        f"{PREFIX}-presigned-url.png",
    )
    add_screenshot_block(
        doc,
        "6.3 DB data EBS + snapshot list (30-day retention)",
        "EC2 → Volumes (mysql-primary-data) + Snapshots filtered by Project tag / DLM.",
        "Data disk is separate from OS disk, encrypted; DLM hourly snapshots retained 30 days. RPO 15 min is met by mysqldump cron.",
        f"{PREFIX}-ebs-snapshots.png",
    )

    # --- 7 Database ---
    doc.add_heading("7. Self-hosted database", level=1)
    doc.add_paragraph(
        "MySQL 8 primary (db-a) + replica (db-b), GTID async replication. ClickHouse in db tier for analytics events."
    )
    add_screenshot_block(
        doc,
        "7.1 Replication lag / SHOW REPLICA STATUS",
        "On replica via SSM: mysql -e 'SHOW REPLICA STATUS\\G' | egrep 'Source_Host|Replica_IO|Replica_SQL|Seconds_Behind'",
        "Replica is running; Seconds_Behind_Source near 0 under idle load — HA read path ready for failover drill.",
        f"{PREFIX}-replica-status.png",
    )
    add_screenshot_block(
        doc,
        "7.2 Roles admin / app_rw / app_ro — denied actions",
        "As app_ro try DROP TABLE / INSERT (should fail). As app_rw try CREATE USER (should fail). Show errors.",
        "Least-privilege works: app uses app_rw only; reports can use app_ro; admin is schema owner not used by the app.",
        f"{PREFIX}-mysql-roles-denied.png",
    )
    add_screenshot_block(
        doc,
        "7.3 Weak password rejected (MySQL + /api/admin/check-password)",
        "MySQL: CREATE USER with 'password' or short string. App: POST /api/admin/check-password with weak body. Show both failures.",
        "Policy length ≥14 and symbol required (variant) is enforced in DB validate_password and in the app checker / CI test.",
        f"{PREFIX}-password-rejected.png",
    )
    add_screenshot_block(
        doc,
        "7.4 Logical backups in S3 every ≤15 min (RPO)",
        "S3 → backups/mysql/ list objects with timestamps ~15 minutes apart. Show cron on primary.",
        "Logical dumps meet RPO 15 min. Combined with snapshots for crash-consistent disk recovery.",
        f"{PREFIX}-mysql-backups-s3.png",
    )
    add_screenshot_block(
        doc,
        "7.5 Restore test timed vs RTO 30 min",
        "Download latest dump; restore into a fresh DB; SELECT to verify rows; record start/end timestamps.",
        "FILL: restore took __ minutes (must be ≤ 30). Data present proves backup integrity.",
        f"{PREFIX}-restore-timing.png",
    )
    add_screenshot_block(
        doc,
        "7.6 Failover drill timed vs RTO / data loss vs RPO",
        "Stop primary; promote replica (STOP REPLICA; read_only=OFF); point app DB_URL to new primary; measure downtime.",
        "FILL: downtime __ min (≤30 RTO); data loss window __ min (≤15 RPO).",
        f"{PREFIX}-failover-timing.png",
    )
    doc.add_paragraph("Self-hosted vs RDS: see comparison in REPORT.md §7 — lab/budget → self-hosted; production strict RTO → RDS Multi-AZ.")

    # --- 8 IAM ---
    doc.add_heading("8. Identity and secrets", level=1)
    add_screenshot_block(
        doc,
        "8.1 IAM roles (node / db) — least privilege",
        "IAM → Roles → ci-anton-belov-0564-role-node and role-db. Screenshot permissions summary.",
        "Nodes read only our secrets, our bucket, ECR pull, logs. No long-lived access keys on servers.",
        f"{PREFIX}-iam-roles.png",
    )
    add_screenshot_block(
        doc,
        "8.2 Secrets Manager entries",
        "Secrets Manager → secrets under ci-anton-belov-0564/* (names only — never screenshot secret values).",
        "DB passwords, SECRET_KEY, k3s token live in Secrets Manager and are fetched at boot/deploy.",
        f"{PREFIX}-secrets-manager.png",
    )
    add_screenshot_block(
        doc,
        "8.3 Proof: no secrets in git",
        "git grep / gitleaks CI green; show .gitignore ignores *.tfvars and .env; terraform outputs have no raw passwords.",
        "Secrets are generated by Terraform random_password into Secrets Manager; state is in encrypted S3 backend.",
        f"{PREFIX}-no-secrets-in-git.png",
    )

    # --- 9 CI/CD ---
    doc.add_heading("9. Containers and CI/CD", level=1)
    add_screenshot_block(
        doc,
        "9.1 Green CI run (lint → test → scan → push)",
        "GitHub → Actions → successful workflow on main. Expand jobs.",
        "Pipeline enforces quality and security gates before an immutable git-SHA image is pushed to ECR.",
        f"{PREFIX}-ci-green.png",
    )
    add_screenshot_block(
        doc,
        "9.2 Failed run blocked by a check",
        "Intentionally fail gitleaks/Trivy or show a historical failed job that exited non-zero.",
        "Gates are real: CRITICAL findings or secret leaks stop the pipeline.",
        f"{PREFIX}-ci-blocked.png",
    )
    add_screenshot_block(
        doc,
        "9.3 Deploy + rollback",
        "Deploy script / Actions deploy job; kubectl rollout undo; show history before/after.",
        "Deploy waits on rollout status; rollback restores previous image quickly.",
        f"{PREFIX}-deploy-rollback.png",
    )

    # --- 10 Security ---
    doc.add_heading("10. Security checks — findings table", level=1)
    add_table(
        doc,
        ["Check", "Tool", "Finding", "Severity", "Status"],
        [
            ["Secret scan", "gitleaks", "FILL after CI", "—", "fixed/accepted"],
            ["Image scan", "Trivy", "FILL", "CRITICAL gate", ""],
            ["IaC scan", "Trivy config", "FILL", "HIGH/CRITICAL", ""],
            ["Password policy", "DB+app+CI", "len≥14 + symbol", "—", "enforced"],
            ["Network", "manual", "only ALB 80/443 public", "—", "ok"],
            ["Storage", "manual", "BPA + encryption", "—", "ok"],
            ["IAM", "manual", "least privilege roles", "—", "ok"],
            ["TLS", "manual", "self-signed ACM", "low UX", "accepted ADR-004"],
        ],
    )
    add_screenshot_block(
        doc,
        "10.1 Security scan outputs",
        "Attach CI logs for gitleaks + Trivy image + Trivy config.",
        "Findings are tracked; CRITICAL issues fail the build; accepted items have a written reason.",
        f"{PREFIX}-security-scans.png",
    )

    # --- 11 IaC ---
    doc.add_heading("11. Infrastructure as Code", level=1)
    doc.add_paragraph(
        "Modules: network, storage, secrets, iam, database, compute, loadbalancer, monitoring, budget. "
        "State: S3 + DynamoDB lock (backend.tf). CI runs fmt + validate."
    )
    add_screenshot_block(
        doc,
        "11.1 terraform apply / module tree",
        "Show repo terraform/ tree and a successful apply summary with prefix-named resources.",
        "Entire platform is reproducible from code; variant values live in terraform.tfvars (not committed with secrets).",
        f"{PREFIX}-terraform-apply.png",
    )
    add_screenshot_block(
        doc,
        "11.2 destroy → apply timing (reproducibility)",
        "Time terraform destroy then terraform apply; screenshot final outputs.",
        "FILL: destroy __ min, apply __ min. Platform returns to working state from code alone.",
        f"{PREFIX}-destroy-apply-timing.png",
    )

    # --- 12 Monitoring ---
    doc.add_heading("12. Monitoring and logging", level=1)
    add_screenshot_block(
        doc,
        "12.1 CloudWatch dashboard",
        "CloudWatch → Dashboards → ci-anton-belov-0564-main (ALB, ASG CPU, MySQL, logs).",
        "Dashboard covers LB traffic/errors/latency, node CPU, DB host health, and a log sample.",
        f"{PREFIX}-dashboard.png",
    )
    add_screenshot_block(
        doc,
        "12.2 Alarms (≥4) — one firing then OK",
        "Show alarms CPU>80, 5xx>20/min, unhealthy hosts, MySQL status. Trigger one; screenshot ALARM then OK + SNS email.",
        "Variant thresholds are configured; notification channel proves operators would be alerted.",
        f"{PREFIX}-alarms-fire-ok.png",
    )
    add_screenshot_block(
        doc,
        "12.3 Logs Insights query by request_id",
        "CloudWatch Logs Insights on /ci-anton-belov-0564/app — query one request_id across lines.",
        "JSON logs with request_id allow tracing a single user request end-to-end.",
        f"{PREFIX}-request-id-query.png",
    )

    # --- 13 HA / cost ---
    doc.add_heading("13. High availability, Well-Architected and cost", level=1)
    add_screenshot_block(
        doc,
        "13.1 Zone-failure drill",
        "Take out one AZ’s nodes; show pods only in the other zone; ALB still healthy.",
        "Platform survives single-AZ loss for the app tier; record user-visible impact.",
        f"{PREFIX}-zone-failure.png",
    )
    doc.add_heading("Well-Architected (short)", level=2)
    for pillar, text in [
        ("Operational excellence", "IaC, CI, ADRs, SSM, runbooks in docs/DRILLS.md"),
        ("Security", "SG+NACL, secrets manager, scans, non-root, no public DB"),
        ("Reliability", "2 AZ, replica, HPA/ASG, drills vs RPO/RTO"),
        ("Performance efficiency", "Spiky target tracking, HPA 60%"),
        ("Cost optimization", "NAT instance, small instances, $15 budget, destroy after evidence"),
        ("Sustainability", "Rightsizing, scale-to-min, teardown"),
    ]:
        doc.add_paragraph(f"{pillar}: {text}", style="List Bullet")

    add_screenshot_block(
        doc,
        "13.2 Budget alert at $15 + cost estimate",
        "AWS Budgets → ci-anton-belov-0564-monthly; Pricing Calculator screenshot; Billing actual spend.",
        "Budget cap matches variant. Optimizations: (1) NAT instance not Gateway, (2) t3.micro replica, (3) destroy after demo, (4) S3 IA lifecycle.",
        f"{PREFIX}-budget-cost.png",
    )
    add_screenshot_block(
        doc,
        "13.3 Teardown proof",
        "terraform destroy; Console shows no leftover EC2/ALB/NAT for the prefix (or empty filtered list).",
        "Resources are not left billing after grading — required by rubric.",
        f"{PREFIX}-teardown.png",
    )

    # --- 14 Reflection ---
    doc.add_heading("14. Reflection", level=1)
    doc.add_paragraph(
        "Hardest problem: fitting ALB + multi-VM MySQL/ClickHouse/k3s under a $15 monthly cap. "
        "Solved with NAT instance (ADR-001) and a short evidence window then destroy."
    )
    doc.add_paragraph(
        "Next: HA k3s servers, in-cluster Prometheus scrape of /metrics, automated failover parameter swap."
    )
    doc.add_paragraph(
        "Sources: course final-project PDF/rubric/template; AWS/k3s/MySQL docs; AI assistant (Cursor) used to scaffold "
        "Terraform and this report — I reviewed the design and can explain every file at defense."
    )

    doc.add_heading("How to finish this Word report", level=1)
    for step in [
        "Run terraform apply and all drills from docs/DRILLS.md.",
        "Save each screenshot into docs/evidence/ using the filenames in the yellow boxes.",
        "In Word: click each yellow box → Insert → Pictures → select the PNG.",
        "Replace every FILL / __ minutes with your measured numbers.",
        "File → Save As → PDF → submit REPORT.pdf with the public GitHub link.",
    ]:
        doc.add_paragraph(step, style="List Number")

    doc.save(OUT)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    build()
