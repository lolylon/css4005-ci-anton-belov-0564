# Evidence folder

Drop screenshots and command transcripts here after deploy. Name files with the prefix:

`ci-anton-belov-0564-<topic>.png`

Suggested set:

1. `vpc-subnets.png` — VPC + 6 subnets
2. `sg-table.png` — security group rules
3. `db-port-blocked.txt` — nc/telnet timeout to 3306 from public
4. `kubectl-nodes.txt` / `kubectl-pods.txt` / `kubectl-hpa.txt`
5. `alb-https.png` — browser (cert warning OK)
6. `loadtest-k6.png` + CloudWatch scale-out
7. `mysql-replica-status.txt` — SHOW REPLICA STATUS
8. `password-rejected.txt` — weak password rejected
9. `backup-s3.png` — objects under backups/mysql/
10. `restore-timing.txt` / `failover-timing.txt`
11. `alarms.png` — CPU/5xx firing and OK
12. `budget.png` — $15 budget
13. `ci-green.png` / `ci-blocked.png`
14. `destroy.png` — empty after teardown
