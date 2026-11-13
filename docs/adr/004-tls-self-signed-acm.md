# ADR-004: Self-signed TLS imported into ACM

## Context
HTTPS on the ALB is required. No custom domain is assumed for the lab.

## Decision
Generate a self-signed certificate with Terraform (`tls` provider), import into **ACM**, attach to the ALB HTTPS listener. HTTP redirects to HTTPS.

## Alternatives considered
- ACM public cert + Route53 domain — better UX, needs owned domain
- Terminate TLS only on Traefik — ALB would be HTTP-only (weaker)

## Consequences
- Browsers show a warning (expected); document that a real domain removes it
- Satisfies “TLS on the LB” for the rubric without buying a domain
