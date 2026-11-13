# ADR-003: k3s on autoscaled VMs (variant cluster type)

## Context
Variant `cluster = k3s-on-autoscaled-vms`. Traffic pattern is **spiky**.

## Decision
- One k3s **server** EC2 in app-a
- k3s **agents** in an Auto Scaling Group across app-a/app-b (min 2)
- Join token from Secrets Manager
- Traefik NodePorts 30080/30443 behind an ALB
- Pod HPA CPU target **60%**; ASG target tracking at ~60% CPU for spikes

## Alternatives considered
- Fixed 3-node k3s — no node autoscaling for spikes
- EKS — higher control-plane cost vs $15 budget

## Consequences
- Server is a control-plane SPOF (agents ASG is HA for workloads)
- ALB health checks `/readyz` through Traefik Ingress
- Spiky load test should scale pods first, then nodes
