# Drill runbooks (RTO ≤ 30 min, RPO ≤ 15 min)

Record wall-clock times into `docs/evidence/` and §7/§13 of `REPORT.md`.

## 1. Pod self-healing

```bash
kubectl -n campus-app delete pod -l app=campus-app --force --grace-period=0
# watch replacements; curl ALB /readyz should stay 200
```

## 2. Node failure

```bash
# pick an agent instance id, or:
kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
# OR stop the EC2 instance in console
kubectl get pods -n campus-app -o wide
```

## 3. Zone failure

Stop/drain all k3s nodes in `us-east-1a`. Confirm pods only on `us-east-1b` and ALB still healthy.

## 4. Logical restore (RTO)

```bash
# on a scratch MySQL or via SSM on a temp host
aws s3 cp s3://ci-anton-belov-0564-files/backups/mysql/<stamp>.sql.gz .
gunzip -c <stamp>.sql.gz | mysql -u admin -p campus
# verify: SELECT COUNT(*) FROM items;
# record elapsed minutes — must be ≤ 30
```

## 5. MySQL failover (RTO)

1. Note last write time / row count on primary.
2. `aws ec2 stop-instances --instance-ids <primary>`
3. On replica (SSM):
   ```sql
   STOP REPLICA;
   SET GLOBAL super_read_only=OFF;
   SET GLOBAL read_only=OFF;
   ```
4. Redeploy app with new `DB_URL` host = former replica IP (`IMAGE_TAG=... ./scripts/deploy-app.sh` after patching deploy script / terraform output).
5. Measure downtime; data loss window should be ≤ 15 min (last dump / replica lag).

## 6. Alarm fire → OK

Generate 5xx or CPU spike (k6 / stress), capture alarm ALARM state, then idle until OK. Screenshot SNS email.
