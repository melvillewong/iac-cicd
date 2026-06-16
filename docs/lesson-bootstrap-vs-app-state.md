# Lesson — CI plan failed: bootstrap vs app state

Postmortem of the first plan-on-PR run (PR #1). Auth worked; `plan` failed. Fixing it forced a state-architecture change. Captures the full path: symptom → root cause → design → migration → insights.

## Symptom

- PR #1 opened, workflow `iac-test` ran
- OIDC auth succeeded (role `github-action-cicd` assumed ✓)
- `terraform plan` failed → `plan status` step exited 1

## Error

```
github-action-cicd is not authorized to perform:
  s3:GetBucketPolicy            on the state bucket
  iam:GetOpenIDConnectProvider  on the OIDC provider
  ssm:DescribeParameters        on the param
```

All `AccessDenied`, all on **read** actions.

## Root cause

- `terraform plan` **refreshes every resource in its state** (reads each from AWS to compute the diff)
- the state held all of: S3 bucket, OIDC provider, IAM role, IAM role policy, SSM param
- the CI role's policy granted least-privilege write on ssm param + s3 state objects only
- so plan tried to read the bucket config + IAM/OIDC internals → no perms → denied

The CI role was managing the same state that contains its own credentials infra (the snake eating its tail).

## Two fixes considered

**Option A — split state (chosen).**
- bootstrap resources (bucket, OIDC, role, policy) → separate config + state, applied locally by admin
- app config → only the SSM param → CI manages this
- CI plan refreshes only the param → existing ssm perms suffice
- CI never reads IAM/bucket internals → least-privilege intact

**Option B — broaden CI role perms (rejected).**
- add `s3:GetBucket*`, `iam:GetOpenIDConnectProvider`, `iam:GetRole*`, `ssm:DescribeParameters`...
- gets green fast, but CI can then read its own IAM trust policy → defeats least-privilege, fragile

## Chosen design

```
05-cicd/
  bootstrap/   bucket + OIDC + role + policy   state key: bootstrap/terraform.tfstate   applied locally (admin)
  app/         ssm param only                  state key: terraform.tfstate             applied by CI
```

- two configs = two root modules = two states (two backend `key`s, same bucket)
- each dir: own `backend.hcl`, own `terraform init`, own `.terraform/` + `.terraform.lock.hcl`
- workflow runs in `app/` (`defaults.run.working-directory: app`)
- bootstrap's role policy can't reference `aws_ssm_parameter.message.arn` (now in another state) → uses a constructed ARN string

## Migration (move resources, never destroy)

Resources already exist in AWS; only state bindings move.

```bash
# bootstrap: new state, import the 4 existing resources
cd bootstrap
terraform init -backend-config=backend.hcl
terraform import aws_s3_bucket.terraform_state terraform-state-<account>
terraform import aws_iam_openid_connect_provider.default arn:aws:iam::<account>:oidc-provider/token.actions.githubusercontent.com
terraform import aws_iam_role.default github-action-cicd
terraform import aws_iam_role_policy.default github-action-cicd:cicd-permission
terraform plan        # expect: No changes

# app: existing state, drop the 4 (leave only ssm param)
cd ../app
terraform init -backend-config=backend.hcl
terraform state rm aws_s3_bucket.terraform_state aws_iam_openid_connect_provider.default aws_iam_role.default aws_iam_role_policy.default
terraform plan        # expect: No changes
```

- `import` records existing AWS resources into state, changes nothing in AWS
- `state rm` drops tracking, does NOT destroy the AWS resource
- both `plan`s saying "No changes" = clean move

## Insights

- **plan refreshes the whole state.** Whatever sits in a config's state, the runner must have read perms for. Shrinking the state = shrinking required perms.
- **don't let CI manage its own bootstrap.** State bucket, OIDC provider, CI role = admin-owned, applied once. CI manages only app resources. Standard real-world layering (bootstrap/foundation vs app/workload), sometimes even separate repos.
- **state is derivable from reality.** `terraform import` reads from live AWS, not from any prior state. Lose all state → rebuild via import (given resources + config exist). S3 versioning is the extra safety net.
- **new state never reads the old.** A config on a new backend `key` starts empty; `import` populates it purely from AWS reality (the resource ID + API), never from the original state object. That's why bootstrap (new key) imports while app (same key as original) just `state rm`s.
- **a backend is per-config.** Two states = two backend configs (differ only by `key`), pointing at the same bucket.
- **blast radius.** With split state a bad CI apply can only touch the param, never destroy the state bucket or its own role (which would brick everything).
- **least-privilege is a forcing function.** The tight policy didn't just limit damage, it surfaced the bad architecture. A broad policy would have hidden it.
