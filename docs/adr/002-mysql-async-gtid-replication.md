# ADR-002: Self-hosted MySQL 8 with async GTID replication

## Context
Variant requires **MySQL** self-hosted on VMs (not RDS), primary + replica in different zones. RPO = 15 min, RTO = 30 min.

## Decision
MySQL 8 primary in db-a, replica in db-b, **GTID + async binlog** replication. Logical `mysqldump` every **15 minutes** to S3; hourly EBS snapshots via DLM (30-day retention).

## Alternatives considered
- Semi-sync replication — safer RPO but higher write latency on small instances
- RDS Multi-AZ — forbidden by assignment; compared in the report
- MySQL in Kubernetes StatefulSet — forbidden

## Consequences
- Failover is a promote + re-point app (scripted); measured against RTO 30 min
- Async replica can lag under load → monitor `Seconds_Behind_Source`
- Password policy enforced with `validate_password` length **14** + symbol
