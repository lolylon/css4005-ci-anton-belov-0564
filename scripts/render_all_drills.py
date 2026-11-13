import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from render_live_evidence import render

P = "ci-anton-belov-0564"
pairs = [
    ("password-rejected.txt", f"{P}-password-rejected.png", "Password policy reject"),
    ("db-port-blocked.txt", f"{P}-db-port-blocked.png", "DB 3306 blocked from public"),
    ("restore-timing.txt", f"{P}-restore-timing.png", "Logical restore RTO"),
    ("replica-status.txt", f"{P}-replica-status.png", "MySQL replica status"),
    ("hpa-scale.txt", f"{P}-kubectl-pods-hpa.png", "HPA scale to 4 replicas"),
    ("node-drain.txt", f"{P}-node-drain-drill.png", "Node drain drill"),
    ("zone-failure.txt", f"{P}-zone-failure.png", "Zone failure drill"),
    ("alarms-drill.txt", f"{P}-alarms-fire-ok.png", "Alarm ALARM to OK"),
    ("loadtest-curl.txt", f"{P}-loadtest.png", "Load test"),
    ("self-healing.txt", f"{P}-self-healing.png", "Pod self-heal"),
    ("mysql-backups-s3.txt", f"{P}-mysql-backups-s3.png", "MySQL backups in S3"),
    ("final-status.txt", f"{P}-final-status.png", "Final cluster status"),
]
for a, b, c in pairs:
    try:
        render(a, b, c)
    except Exception as e:
        print("fail", a, e)
