# TEAM-1 Infrastructure — IAM / IRSA Build Session Walkthrough

**Project:** Spring PetClinic Microservices — DMI Cohort 2, Capstone Part II  
**Team:** TEAM-1-INFRA  
**Lead:** Paul (Branch: `infra/paul`)  
**Session Focus:** Build, deploy, and smoke-test the IAM / IRSA / OIDC module  
**Status at session close:** IAM roles deployed ✅ | GitHub Actions CI role test in progress 🔄  

---

## Table of Contents

1. [Where We Started](#1-where-we-started)
2. [The Big Picture — Why IAM Roles Matter](#2-the-big-picture--why-iam-roles-matter)
3. [The Keycard Analogy](#3-the-keycard-analogy)
4. [What We Built — The Four Keycards](#4-what-we-built--the-four-keycards)
5. [How the Terraform Module Is Structured](#5-how-the-terraform-module-is-structured)
6. [The Errors We Hit and How We Fixed Them](#6-the-errors-we-hit-and-how-we-fixed-them)
7. [Testing the ESO Keycard — IRSA Smoke Test](#7-testing-the-eso-keycard--irsa-smoke-test)
8. [Testing the GitHub Actions Keycard](#8-testing-the-github-actions-keycard)
9. [Where We Stopped](#9-where-we-stopped)
10. [What the Other Teams Need From Us](#10-what-the-other-teams-need-from-us)

---

## 1. Where We Started

TEAM-1 had already built and deployed the core AWS infrastructure:

- **VPC** — private network with public subnets across two availability zones
- **EKS** — Kubernetes cluster (`petclinic-dev`) running on `t4g.small` ARM nodes
- **ECR** — eight container registries, one per microservice
- **RDS** — MySQL database instance with AWS-managed credentials in Secrets Manager

The RDS fix (merged from `infra/aarti` into `infra/paul`) was the last integration before this session began. With all four infrastructure modules stable, the team had a complete Terraform plan of 53 resources with zero destroys.

The missing piece: **the cluster had no way to securely talk to AWS**. The robots running inside Kubernetes — the secrets fetcher, the load balancer manager, the storage driver, the CI pipeline — all needed AWS credentials. That is what this session solved.

---

## 2. The Big Picture — Why IAM Roles Matter

Every component that runs in the cluster needs to call AWS APIs. The naive solution is to create an AWS access key, paste it into a Kubernetes secret, and reference it from your pods. Teams do this all the time. It works. It is also a ticking security bomb — keys get rotated late, leaked in logs, committed to git, or forgotten entirely.

The production-grade alternative is **no stored credentials at all**. Instead, each component gets a temporary identity that AWS issues at pod startup, rotates every few hours, and revokes automatically when the pod stops. This system is called **IRSA** — IAM Roles for Service Accounts — and it is the AWS-recommended pattern for all EKS workloads.

This session built the IRSA foundation that every other team in this project depends on.

---

## 3. The Keycard Analogy

Think of your building's access control system.

Every room in the building (Secrets Manager, the load balancer, ECR, EBS storage) has a card reader on the door. To enter, you need the right keycard. The keycard doesn't belong to a person — it belongs to a role. A cleaner's keycard opens the supply closet. A developer's keycard opens the server room. Neither card opens the other's door.

In this project:

| The Building | AWS |
|---|---|
| A room | An AWS service (Secrets Manager, ELB, ECR, EBS) |
| A keycard | An IAM Role |
| The card reader | AWS STS (Security Token Service) |
| A robot using a card | A Kubernetes pod |
| The card issuer | EKS OIDC Provider |

When a pod starts, EKS looks at its service account. If the service account is annotated with a role ARN, EKS injects a short-lived identity token into the pod. The pod presents that token to the card reader (AWS STS). STS checks the door policy (trust policy) on the role. If the namespace and service account name match exactly — it issues a temporary keycard. The keycard expires in one hour. A fresh one is issued automatically.

No passwords stored anywhere. No keys to leak.

---

## 4. What We Built — The Four Keycards

The Terraform module `terraform/modules/iam` creates four IAM roles. Each role is a keycard scoped to the minimum permissions its robot needs.

### Keycard 1 — External Secrets Operator (ESO)

**Role name:** `petclinic-dev-eso-role`  
**Used by:** TEAM-2 when installing External Secrets Operator  
**Kubernetes identity:** `namespace: external-secrets` / `serviceaccount: external-secrets-sa`  
**What it can do:** Read the exact RDS master password secret from Secrets Manager — nothing else  
**Why it matters:** Without this, the application cannot retrieve its database credentials and cannot start

### Keycard 2 — AWS Load Balancer Controller

**Role name:** `petclinic-dev-lb-controller-role`  
**Used by:** TEAM-2 when installing the ALB Controller  
**Kubernetes identity:** `namespace: kube-system` / `serviceaccount: aws-load-balancer-controller`  
**What it can do:** Create and manage Application Load Balancers, target groups, security groups, listeners  
**Why it matters:** Without this, no public traffic can reach the application

### Keycard 3 — EBS CSI Driver

**Role name:** `petclinic-dev-ebs-csi-role`  
**Used by:** TEAM-2 when enabling the EBS CSI add-on  
**Kubernetes identity:** `namespace: kube-system` / `serviceaccount: ebs-csi-controller-sa`  
**What it can do:** Provision and attach EBS volumes (uses the AWS-managed `AmazonEBSCSIDriverPolicy`)  
**Why it matters:** Without this, Prometheus and Grafana have nowhere to persist their data

### Keycard 4 — GitHub Actions CI Role

**Role name:** `petclinic-github-actions-role`  
**Used by:** TEAM-3 in their GitHub Actions CI workflows  
**GitHub identity:** `repo:lua-cloud03/petclinic-platform` (any branch)  
**What it can do:** Authenticate to ECR and push Docker images — scoped to `petclinic-dev/*` repos only  
**Why it matters:** Without this, the CI pipeline cannot deliver built images to the cluster

---

## 5. How the Terraform Module Is Structured

```
terraform/
└── modules/
│   └── iam/
│       ├── versions.tf      — Terraform >= 1.6.0, AWS provider ~> 5.0
│       ├── variables.tf     — 9 input variables
│       ├── main.tf          — All four roles and their policies
│       └── outputs.tf       — Four ARN outputs for downstream teams
└── environments/
    └── dev/
        ├── main.tf          — Wires the IAM module with EKS OIDC + RDS secret ARN
        ├── variables.tf     — Includes github_org, github_repo, github_branch
        └── outputs.tf       — Exposes all four IAM role ARNs
```

**Key design decisions:**

**`trimprefix` on the OIDC URL** — The EKS module returns the OIDC provider URL with `https://` prefix. IAM trust policy condition keys require the bare hostname. A local strips the prefix:
```hcl
oidc_url = trimprefix(var.oidc_provider_url, "https://")
```

**Inline policies instead of standalone policies** — The DMI course environment has an explicit deny policy (`DMI-Deny-Account-IAM-Admin-Tampering`) that blocks `iam:CreatePolicy`. All permission policies use `aws_iam_role_policy` (inline) which calls `iam:PutRolePolicy` — not blocked.

**Data source for the GitHub OIDC provider** — The GitHub OIDC provider already existed in the AWS account. Trying to create it with a `resource` block throws `EntityAlreadyExists`. The module reads it with a `data` source instead:
```hcl
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}
```

**`default_tags` in the provider** — The AWS provider applies `Project`, `Environment`, `Team`, and `ManagedBy` tags to every resource automatically. Each resource in the module only sets `Name`.

---

## 6. The Errors We Hit and How We Fixed Them

This section documents the three apply errors encountered and their root causes. These are learning points for the team.

### Error 1 — IAM Role Description ValidationError

**Error message:**
```
Value at 'description' failed to satisfy constraint:
Member must satisfy regular expression pattern: [	
 -~¡-ÿ]*
```

**Root cause:** The description fields in the IAM roles used em dash characters (`—`, Unicode U+2014). The AWS IAM API rejects any character above ASCII 255 in description strings.

**Fix:** Replaced all `—` with plain hyphen `-` in every `description` field across `main.tf`.

---

### Error 2 — AccessDenied on iam:CreatePolicy

**Error message:**
```
explicit deny in an identity-based policy: DMI-Deny-Account-IAM-Admin-Tampering
is not authorized to perform: iam:CreatePolicy
```

**Root cause:** The DMI course environment has an SCP-style deny policy attached to student IAM users that explicitly blocks `iam:CreatePolicy`. The original module used `aws_iam_policy` resources, which call `iam:CreatePolicy`.

**Fix:** Converted all standalone `aws_iam_policy` + `aws_iam_role_policy_attachment` pairs to `aws_iam_role_policy` inline resources. Inline policies use `iam:PutRolePolicy`, which is not blocked.

Before:
```hcl
resource "aws_iam_policy" "eso" { ... }
resource "aws_iam_role_policy_attachment" "eso" { ... }
```

After:
```hcl
resource "aws_iam_role_policy" "eso" {
  name   = "${local.name_prefix}-eso-policy"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso_permissions.json
}
```

---

### Error 3 — EntityAlreadyExists for GitHub OIDC Provider

**Error message:**
```
EntityAlreadyExists: Provider with url https://token.actions.githubusercontent.com already exists
```

**Root cause:** The GitHub OIDC provider is created once per AWS account. Another student or previous deployment had already created it. Terraform tried to create it again.

**Fix:** Replaced the `resource "aws_iam_openid_connect_provider" "github"` block with a `data` source that reads the existing provider.

---

## 7. Testing the ESO Keycard — IRSA Smoke Test

With the roles deployed, the team ran a live smoke test to confirm the IRSA chain works end to end.

**First attempt — wrong service account**

A test pod was run in a temporary namespace `irsa-test` with a test service account `eso-test-sa`. It failed with:
```
AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity
```

This was not a bug. The ESO role's trust policy is scoped to exactly one identity:
```
system:serviceaccount:external-secrets:external-secrets-sa
```
The test used a different service account — the door bouncer correctly rejected it. This was the security working as designed.

**Second attempt — correct namespace and service account**

The test was re-run using the exact namespace and service account name the trust policy expects:

```bash
kubectl create namespace external-secrets
kubectl create serviceaccount external-secrets-sa -n external-secrets
kubectl annotate serviceaccount external-secrets-sa \
  -n external-secrets \
  eks.amazonaws.com/role-arn=arn:aws:iam::482352877891:role/petclinic-dev-eso-role
```

A pod running `aws sts get-caller-identity` confirmed the full IRSA chain:

```json
{
  "Arn": "arn:aws:sts::482352877891:assumed-role/petclinic-dev-eso-role/botocore-session-XXXXXXXXXX"
}
```

The `assumed-role/petclinic-dev-eso-role` in the ARN confirms the pod assumed the correct keycard. The IRSA chain is verified:

```
Pod → Service Account → OIDC Token → AWS STS → petclinic-dev-eso-role assumed ✅
```

**Side benefit:** The `external-secrets` namespace and annotated service account now exist in the cluster, ready for TEAM-2. When TEAM-2 installs ESO via Helm, the keycard is already in the door.

---

## 8. Testing the GitHub Actions Keycard

**Goal:** Confirm that a GitHub Actions workflow on branch `infra/paul` can assume `petclinic-github-actions-role` and authenticate to ECR — with no stored AWS credentials anywhere.

**Workflow file:** `.github/workflows/test-iam.yml`

```yaml
name: Test IAM Keycard
on:
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Assume CI role via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::482352877891:role/petclinic-github-actions-role
          aws-region: us-east-1

      - name: Confirm identity is the CI role, not a human user
        run: aws sts get-caller-identity

      - name: Log into ECR
        run: |
          aws ecr get-login-password --region us-east-1 | \
          docker login --username AWS --password-stdin \
            482352877891.dkr.ecr.us-east-1.amazonaws.com
          echo "ECR login successful - CI robot has its keycard"
```

**Issues encountered during test setup:**

| Attempt | Error | Root Cause | Fix Applied |
|---|---|---|---|
| Run #1 | `Input required: aws-region` | `aws-region` was read from a secret — it is not sensitive and must be hardcoded | Hardcoded `us-east-1` directly in the workflow |
| Run #2 | `Could not load credentials from any providers` | `AWS_ROLE_ARN` secret likely empty or malformed | Hardcoded the role ARN directly to remove secrets from the equation |
| Run #3 | `Not authorized to perform sts:AssumeRoleWithWebIdentity` (12 retries) | Trust policy used `StringEquals` on a specific branch; workflow was triggered from wrong branch via `workflow_dispatch` | Changed trust policy condition to `StringLike` with repo wildcard `repo:lua-cloud03/petclinic-platform:*` |
| Run #4 | Git push rejected — diverged branches | Remote `infra/paul` had commits not present locally | Resolved with `git pull --rebase origin infra/paul` |

**Status at session close:** Workflow file committed on `infra/paul`. Push to `develop` pending (requires PR per team policy). GitHub Actions test pending final trigger from correct branch.

---

## 9. Where We Stopped

| Item | Status |
|---|---|
| VPC, EKS, ECR, RDS deployed | ✅ Complete |
| IAM module built and deployed | ✅ Complete |
| ESO IRSA chain verified in cluster | ✅ Complete |
| `external-secrets` namespace + SA ready for TEAM-2 | ✅ Complete |
| GitHub Actions workflow file written | ✅ Complete |
| Trust policy updated to `StringLike` wildcard | ✅ Complete |
| GitHub Actions test passing (screenshot) | 🔄 Pending — PR to `develop` required first |
| TEAM-2 and TEAM-3 handoff notes | ✅ Written (`TEAM1_TO_TEAM2_TEAM3_IAM_HANDOFF.md`) |

**Pending action before this sprint closes:**

1. Raise a PR from `infra/paul` → `develop` (per team PR policy)
2. Once merged, trigger **Test IAM Keycard** workflow from the Actions tab, selecting `infra/paul` branch
3. Screenshot the passing run showing `assumed-role/petclinic-github-actions-role` in the identity output

---

## 10. What the Other Teams Need From Us

Run this on Paul's machine after the PR is merged to get the handoff values:

```bash
cd ~/production/petclinic-platform/terraform/environments/dev

terraform output iam_eso_role_arn
terraform output iam_lb_controller_role_arn
terraform output iam_ebs_csi_role_arn
terraform output iam_github_actions_role_arn
```

### For TEAM-2

| What They Need | Terraform Output | Used For |
|---|---|---|
| ESO role ARN | `iam_eso_role_arn` | Annotate `external-secrets-sa` in `external-secrets` namespace |
| LB Controller role ARN | `iam_lb_controller_role_arn` | Annotate `aws-load-balancer-controller` SA in `kube-system` |
| EBS CSI role ARN | `iam_ebs_csi_role_arn` | Annotate `ebs-csi-controller-sa` in `kube-system` |

TEAM-2 also inherits the `external-secrets` namespace and `external-secrets-sa` service account that TEAM-1 already created and annotated in the cluster. They can proceed directly to installing ESO via Helm.

### For TEAM-3

| What They Need | Terraform Output | Used For |
|---|---|---|
| GitHub Actions role ARN | `iam_github_actions_role_arn` | Set as `AWS_ROLE_ARN` in GitHub repository secrets |

TEAM-3 does not need to touch any Terraform. They add the role ARN as a GitHub secret and reference it in their CI workflow with `aws-actions/configure-aws-credentials@v4`.

---

*Document authored by TEAM-1-INFRA — DMI Cohort 2, Capstone Part II*  
*Last updated: Session close — IAM/IRSA build complete, GitHub Actions test pending PR merge*
