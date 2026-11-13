# Defense presentation outline (~7 min)

1. **Variant (30s)** — Library books, prefix `ci-anton-belov-0564`, VPC `10.195.0.0/16`, MySQL+CH, k3s ASG, HPA 60%, budget $15  
2. **Architecture walk-through (2 min)** — diagram: ALB → k3s → MySQL/CH; SG chaining; why NAT instance (ADR-001)  
3. **Hardest problem (1.5 min)** — $15 budget vs NAT GW; RPO 15m via mysqldump cron  
4. **Live demo (2 min)** — open ALB URL, `kubectl get pods -o wide`, `kubectl get hpa`, create a book item  
5. **One drill (1 min)** — pod delete or node drain; show self-heal  

Prepare answers: explain `terraform/modules/network/main.tf`, `scripts/mysql-primary.sh`, `deploy/k8s/hpa.yaml`, failover steps.
