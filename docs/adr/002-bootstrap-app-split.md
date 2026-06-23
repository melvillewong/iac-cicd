# 002. Two-stage bootstrap and app split

Status: accepted
Date: 2026-06-13

## Context

CI cannot run until the IAM role it assumes and the S3 state bucket it reads both exist. But those resources are themselves Terraform-managed. A single configuration that manages its own prerequisites cannot bootstrap itself: the role must exist before the workflow can authenticate to create the role.

## Decision

Split the configuration in two:

- `bootstrap/` creates the OIDC provider, IAM role, and S3 state bucket. Applied locally, once, by a human with existing credentials.
- `app/` holds the workload Terraform manages on every run. Applied by CI.

Both store state in the same bucket under separate keys (`bootstrap/terraform.tfstate`, `app/terraform.tfstate`) so the two state files never collide.

## Consequences

- Breaks the chicken-and-egg cycle: the prerequisites exist before CI needs them.
- Clear separation between one-time setup infrastructure and CI-managed workload.
- `bootstrap/` is applied manually and is not part of the CI loop, so changes to it are not gated the same way.
- Two state files to track instead of one.
