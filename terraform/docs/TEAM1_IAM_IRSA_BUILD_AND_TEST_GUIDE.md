# TEAM-1 IAM/IRSA — Build, Apply, and Verification Guide

**Project:** DMI Cohort 2 Capstone — Spring PetClinic on AWS EKS  
**Session anchor:** `TEAM1-IAM-IRSA-BUILD-TEST-20260512`  
**Prepared for:** Paul (TEAM-1 Infrastructure Lead)  
**Scope:** Build the IAM module, wire it into the dev environment, apply it,
           then verify each role works by temporarily simulating TEAM-2 and TEAM-3.

---

## What You Are Building

Four IAM roles that the downstream teams depend on:

| Role | Who uses it | What it unlocks |
|------|-------------|-----------------|
| `petclinic-dev-eso-role` | TEAM-2 | External Secrets Operator reads DB passwords from Secrets Manager |
| `petclinic-dev-lb-controller-role` | TEAM-2 | ALB Controller creates the Application Load Balancer |
| `petclinic-dev-ebs-csi-role` | TEAM-2 | EBS CSI Driver provisions storage volumes for Prometheus/Grafana |
| `petclinic-github-actions-role` | TEAM-3 | GitHub Actions pushes Docker images to ECR without storing AWS keys |

All four roles are **stable outputs** — created once and reused across sessions.

---

## Prerequisites

Before you start, confirm the following are already in place:

```bash
# 1. You are on the correct branch
git status
# Expected: On branch infra/paul (or infra/paul-fix after Priority 1 work)

# 2. EKS is running and you can connect to it
kubectl get nodes
# Expected: two nodes in Ready state

# 3. Terraform backend is accessible
cd terraform/environments/dev
terraform init
# Expected: Backend initialization successful
```

If `kubectl get nodes` fails, run:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name petclinic-dev \
  --profile petclinic-paul
```

---

## PHASE 1 — Copy the Module Into Your Workspace

### Step 1.1 — Add the IAM module files

Copy the four module files from the handoff package into your workspace:

```bash
cd /home/paul/production/petclinic-platform

mkdir -p terraform/modules/iam

# Copy these four files from the handoff package:
# terraform/modules/iam/versions.tf
# terraform/modules/iam/variables.tf
# terraform/modules/iam/main.tf
# terraform/modules/iam/outputs.tf
```

Verify the structure:

```bash
ls -1 terraform/modules/iam/
# Expected output:
# main.tf
# outputs.tf
# variables.tf
# versions.tf
```

### Step 1.2 — Wire the module into the dev environment

Open `terraform/environments/dev/main.tf` and add the IAM module block
**after the eks module block**. The IAM module reads outputs from the EKS
module, so order matters.

```hcl
module "iam" {
  source = "../../modules/iam"

  project        = var.project
  environment    = var.environment
  aws_account_id = var.aws_account_id
  aws_region     = var.aws_region

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  github_org    = var.github_org
  github_repo   = var.github_repo
  github_branch = var.github_branch

  tags = var.tags
}
```

### Step 1.3 — Add the new variables

Open `terraform/environments/dev/variables.tf` and add:

```hcl
variable "github_org" {
  description = "GitHub organisation or user name"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without org prefix)"
  type        = string
}

variable "github_branch" {
  description = "Branch allowed to assume the GitHub Actions CI role"
  type        = string
  default     = "main"
}
```

### Step 1.4 — Set the variable values

Open `terraform/environments/dev/terraform.tfvars` and add:

```hcl
github_org    = "petclinic-project"           # replace with your actual GitHub org
github_repo   = "spring-petclinic-microservices"
github_branch = "main"
```

### Step 1.5 — Add the IAM outputs

Open `terraform/environments/dev/outputs.tf` and add:

```hcl
output "iam_eso_role_arn" {
  value = module.iam.eso_role_arn
}

output "iam_lb_controller_role_arn" {
  value = module.iam.lb_controller_role_arn
}

output "iam_ebs_csi_role_arn" {
  value = module.iam.ebs_csi_role_arn
}

output "iam_github_actions_role_arn" {
  value = module.iam.github_actions_role_arn
}
```

---

## PHASE 2 — Validate and Apply

### Step 2.1 — Format and validate

```bash
cd /home/paul/production/petclinic-platform

terraform -chdir=terraform/environments/dev fmt -recursive
terraform -chdir=terraform/environments/dev validate
```

Expected:

```
Success! The configuration is valid.
```

If validate fails, read the error line carefully — it will name the exact
file and line number. Fix, re-run fmt, re-run validate before proceeding.

### Step 2.2 — Plan and review

```bash
terraform -chdir=terraform/environments/dev \
  plan -out plan-iam.out
```

Review the plan output. You should see exactly:

```
+ aws_iam_openid_connect_provider.github
+ aws_iam_policy.eso
+ aws_iam_policy.github_actions
+ aws_iam_policy.lb_controller
+ aws_iam_role.ebs_csi
+ aws_iam_role.eso
+ aws_iam_role.github_actions
+ aws_iam_role.lb_controller
+ aws_iam_role_policy_attachment.ebs_csi
+ aws_iam_role_policy_attachment.eso
+ aws_iam_role_policy_attachment.github_actions
+ aws_iam_role_policy_attachment.lb_controller

Plan: 12 to add, 0 to change, 0 to destroy.
```

No existing resources should show as changed or destroyed.
If you see any destroys on VPC, EKS, or RDS resources, stop and investigate.

### Step 2.3 — Apply

```bash
terraform -chdir=terraform/environments/dev \
  apply plan-iam.out
```

Expected:

```
Apply complete! Resources: 12 added, 0 changed, 0 destroyed.
```

### Step 2.4 — Capture the outputs

```bash
terraform -chdir=terraform/environments/dev output -json | \
  grep -E "iam_" | tee /tmp/iam-outputs.txt

cat /tmp/iam-outputs.txt
```

You will see four ARNs. Copy them — they go into `team-outputs/stable-outputs.env`
in the next step.

### Step 2.5 — Export to stable outputs

```bash
# Read the four ARN values from Terraform outputs
ESO_ROLE_ARN=$(terraform -chdir=terraform/environments/dev output -raw iam_eso_role_arn)
LB_ROLE_ARN=$(terraform -chdir=terraform/environments/dev output -raw iam_lb_controller_role_arn)
EBS_ROLE_ARN=$(terraform -chdir=terraform/environments/dev output -raw iam_ebs_csi_role_arn)
GHA_ROLE_ARN=$(terraform -chdir=terraform/environments/dev output -raw iam_github_actions_role_arn)

# Append to stable-outputs.env (these do not change between sessions)
cat >> team-outputs/stable-outputs.env << EOF

# IAM / IRSA Roles — added $(date +%Y-%m-%d)
IAM_ESO_ROLE_ARN=${ESO_ROLE_ARN}
IAM_LB_CONTROLLER_ROLE_ARN=${LB_ROLE_ARN}
IAM_EBS_CSI_ROLE_ARN=${EBS_ROLE_ARN}
IAM_GITHUB_ACTIONS_ROLE_ARN=${GHA_ROLE_ARN}
EOF

cat team-outputs/stable-outputs.env
```

### Step 2.6 — Commit and push

```bash
git add terraform/modules/iam/
git add terraform/environments/dev/main.tf
git add terraform/environments/dev/variables.tf
git add terraform/environments/dev/outputs.tf
git add terraform/environments/dev/terraform.tfvars
git add team-outputs/stable-outputs.env

git commit -m "Add IAM/IRSA module: ESO, ALB Controller, EBS CSI, GitHub Actions roles"

git push origin infra/paul
```

---

## PHASE 3 — Verification Tests (TEAM-1 Simulating TEAM-2 and TEAM-3)

These tests prove each role works end-to-end before handing off to the teams.

---

### TEST A — ESO Role (simulating TEAM-2)

**What this proves:** The ESO service account can assume its IRSA role and
read a secret from Secrets Manager. This is the exact path the External
Secrets Operator will take when TEAM-2 deploys it.

**Step A1 — Create the ESO namespace and annotated service account**

```bash
# Create the namespace ESO will live in
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -

# Create a test service account with the IRSA annotation
ESO_ROLE_ARN=$(terraform -chdir=terraform/environments/dev output -raw iam_eso_role_arn)

kubectl create serviceaccount external-secrets-sa \
  --namespace external-secrets \
  --dry-run=client -o yaml | \
kubectl annotate --local -f - \
  eks.amazonaws.com/role-arn="${ESO_ROLE_ARN}" \
  -o yaml | kubectl apply -f -

# Verify the annotation was set
kubectl get serviceaccount external-secrets-sa \
  -n external-secrets \
  -o jsonpath='{.metadata.annotations}'
```

Expected output includes:
```json
{"eks.amazonaws.com/role-arn":"arn:aws:iam::482352877891:role/petclinic-dev-eso-role"}
```

**Step A2 — Run a test pod that assumes the role and reads a secret**

First ensure the RDS secret exists in Secrets Manager (created by Aarti's RDS module):

```bash
aws secretsmanager list-secrets \
  --region us-east-1 \
  --filter Key=name,Values=petclinic/dev/ \
  --query 'SecretList[*].Name' \
  --output table
```

Now launch a pod using the annotated service account and attempt to read the secret:

```bash
ESO_ROLE_ARN=$(terraform -chdir=terraform/environments/dev output -raw iam_eso_role_arn)

# Get the exact secret name from the list output above
SECRET_NAME="petclinic/dev/rds-credentials"   # adjust if different

kubectl run eso-test \
  --rm -it \
  --restart=Never \
  --namespace external-secrets \
  --serviceaccount external-secrets-sa \
  --image amazon/aws-cli:latest \
  --env AWS_REGION=us-east-1 \
  -- secretsmanager get-secret-value \
       --secret-id "${SECRET_NAME}" \
       --query 'SecretString' \
       --output text
```

**Expected:** The secret JSON is printed (username and password fields visible).

**Failure means:** The trust policy condition does not match the service account
namespace or name. Check the exact namespace and SA name spelling.

---

### TEST B — ALB Controller Role (simulating TEAM-2)

**What this proves:** The ALB Controller service account can assume its role.
Full ALB creation will happen when TEAM-2 deploys the Helm chart — this test
confirms the role trust works before that step.

```bash
LB_ROLE_ARN=$(terraform -chdir=terraform/environments/dev output -raw iam_lb_controller_role_arn)

# Create the annotated service account in kube-system
kubectl create serviceaccount aws-load-balancer-controller \
  --namespace kube-system \
  --dry-run=client -o yaml | \
kubectl annotate --local -f - \
  eks.amazonaws.com/role-arn="${LB_ROLE_ARN}" \
  -o yaml | kubectl apply -f -

# Test: launch a pod using this SA and call EC2 DescribeVpcs
kubectl run alb-test \
  --rm -it \
  --restart=Never \
  --namespace kube-system \
  --serviceaccount aws-load-balancer-controller \
  --image amazon/aws-cli:latest \
  --env AWS_REGION=us-east-1 \
  -- ec2 describe-vpcs \
       --filters "Name=tag:Project,Values=petclinic" \
       --query 'Vpcs[*].VpcId' \
       --output table
```

**Expected:** The VPC ID of `petclinic-dev` VPC is printed.

---

### TEST C — GitHub Actions Role (simulating TEAM-3)

**What this proves:** The GitHub Actions role can be assumed from GitHub
Actions and that it can push an image to ECR.

This test is done from the GitHub Actions interface, not from the command line.

**Step C1 — Store secrets in GitHub**

In the GitHub repository → Settings → Secrets and Variables → Actions:

| Secret Name | Value |
|-------------|-------|
| `AWS_REGION` | `us-east-1` |
| `AWS_ROLE_ARN` | *(value of `iam_github_actions_role_arn` from Terraform output)* |
| `AWS_ACCOUNT_ID` | `482352877891` |

**Step C2 — Create a minimal validation workflow**

Create `.github/workflows/validate-iam.yml` in the application repository:

```yaml
name: Validate IAM OIDC

on:
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Verify identity
        run: aws sts get-caller-identity

      - name: Verify ECR access
        run: |
          aws ecr get-login-password --region ${{ secrets.AWS_REGION }} | \
          docker login --username AWS --password-stdin \
            ${{ secrets.AWS_ACCOUNT_ID }}.dkr.ecr.${{ secrets.AWS_REGION }}.amazonaws.com
          echo "ECR login successful"
```

**Step C3 — Run the workflow manually**

Go to Actions tab → Validate IAM OIDC → Run workflow → Run workflow.

**Expected:** Both steps pass. The `aws sts get-caller-identity` output shows
the GitHub Actions role ARN, not a human user. The ECR login succeeds.

**Failure means:** Either the GitHub OIDC provider was not registered (check
`aws iam list-open-id-connect-providers`), or the subject condition
(`repo:{org}/{repo}:ref:refs/heads/main`) does not match the actual repo/branch.

---

## PHASE 4 — Post-Test Cleanup

After tests pass, remove the test service accounts (TEAM-2 will re-create
these properly when they install the Helm charts):

```bash
# Remove test service accounts — TEAM-2 will manage these properly
kubectl delete serviceaccount external-secrets-sa -n external-secrets
kubectl delete serviceaccount aws-load-balancer-controller -n kube-system

# Remove the test namespaces only if TEAM-2 has not started work yet
# kubectl delete namespace external-secrets   # only if safe to do so
```

Do NOT delete the IAM roles. They are stable outputs and must persist.

---

## PHASE 5 — Final Status Confirmation

Run this final check to confirm all four roles exist in AWS:

```bash
aws iam list-roles \
  --region us-east-1 \
  --query 'Roles[?starts_with(RoleName, `petclinic`)].RoleName' \
  --output table
```

Expected output includes:

```
petclinic-dev-eso-role
petclinic-dev-lb-controller-role
petclinic-dev-ebs-csi-role
petclinic-github-actions-role
```

When all four are confirmed, update the output status file:

```bash
cat >> team-outputs/output-status.env << 'EOF'
IAMRolesStatus=VALID
IAMLastUpdatedBy=TEAM-1
IAMLastUpdatedDate=$(date +%Y-%m-%d)
EOF
```

Commit and push the updated status:

```bash
git add team-outputs/
git commit -m "Mark IAM/IRSA roles as VALID in output-status"
git push origin infra/paul
```

---

## Summary Checklist

```
[ ] IAM module files copied to terraform/modules/iam/
[ ] Module wired into terraform/environments/dev/main.tf
[ ] Variables and tfvars updated with GitHub org/repo
[ ] terraform fmt + validate pass
[ ] terraform plan shows 12 resources, no destroys
[ ] terraform apply completes: 12 added
[ ] Four role ARNs exported to team-outputs/stable-outputs.env
[ ] Changes committed and pushed to infra/paul
[ ] TEST A: ESO role — pod reads Secrets Manager secret successfully
[ ] TEST B: ALB Controller role — pod calls EC2 DescribeVpcs successfully
[ ] TEST C: GitHub Actions role — OIDC workflow passes, ECR login succeeds
[ ] Test service accounts cleaned up
[ ] output-status.env updated and committed
```
