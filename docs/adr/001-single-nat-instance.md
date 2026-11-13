# ADR-001: Single NAT EC2 instead of NAT Gateway

## Context
Monthly budget cap is **$15**. An AWS NAT Gateway alone is ~$32/month plus data processing, which exceeds the entire budget.

## Decision
Use one **t3.micro NAT instance** in `us-east-1a` with IP forwarding/MASQUERADE for both private AZs (Free Tier eligible; `t3.nano` is blocked on the new AWS Free plan). Document the AZ SPOF trade-off.

## Alternatives considered
- Dual NAT Gateways (HA, ~$64+/mo) — over budget
- Dual NAT instances — still more cost; better HA
- VPC endpoints only — incomplete for apt/k3s installs

## Consequences
- Cost stays inside the evidence window when combined with destroy-after-demo
- Loss of the NAT AZ breaks private egress until recovery
- Acceptable for lab; production would use NAT GW per AZ or fck-nat HA
