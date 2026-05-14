# TEAM-1 to TEAM-2 and TEAM-3 — IAM/IRSA Handoff Guide

**Project:** DMI Cohort 2 Capstone — Spring PetClinic on AWS EKS  
**Prepared by:** TEAM-1 Infrastructure  
**Audience:** TEAM-2 (Kubernetes Platform) and TEAM-3 (CI/CD)  
**Last updated:** see `team-outputs/output-status.env → IAMLastUpdatedDate`

---

## How to Read This Document

TEAM-1 has created IAM roles that allow your Kubernetes controllers and CI
pipeline to talk to AWS services securely — without storing any passwords or
AWS access keys anywhere.

Before you use anything in this guide, check that the roles are ready:

```bash
git pull

cat team-outputs/output-status.env
```

Look for this line:

```
IAMRolesStatus=VALID
```

If it says `STALE` or is missing, contact TEAM-1 before continuing.

---

## Understanding Stable vs Dynamic Outputs

TEAM-1 provides two categories of outputs. This distinction affects how you
use them and what happens when the infrastructure is stopped and restarted
between sessions.

### Stable Outputs

Stable outputs live in:

```
team-outputs/stable-outputs.env
```

These are created once and do not change between sessions, even when the EKS
cluster or RDS database is stopped to save cost.

**IAM role ARNs are stable outputs.** They will have the same values tomorrow
as they do today. You can safely hardcode them into Kubernetes annotations and
GitHub secrets once — you will not need to update them again unless TEAM-1
explicitly notifies you of a change.

### Dynamic Outputs

Dynamic outputs live in:

```
team-outputs/dynamic-outputs.env
```

These values change when the infrastructure is stopped and restarted. Examples
include EKS API endpoint, ALB DNS name, and RDS endpoint.

**Rule:** Before each working session, run:

```bash
git pull
cat team-outputs/output-status.env
```

If `InfrastructureStatus=STOPPED`, dynamic outputs from the last session are
stale. Ask TEAM-1 to start the environment and refresh the outputs before you
continue.

---

## Reading the IAM Role ARNs

All four IAM role ARNs are in the stable outputs file:

```bash
cat team-outputs/stable-outputs.env | grep IAM
```

You will see something like:

```
IAM_ESO_ROLE_ARN=arn:aws:iam::482352877891:role/petclinic-dev-eso-role
IAM_LB_CONTROLLER_ROLE_ARN=arn:aws:iam::482352877891:role/petclinic-dev-lb-controller-role
IAM_EBS_CSI_ROLE_ARN=arn:aws:iam::482352877891:role/petclinic-dev-ebs-csi-role
IAM_GITHUB_ACTIONS_ROLE_ARN=arn:aws:iam::482352877891:role/petclinic-github-actions-role
```

The account ID (`482352877891`) and role names will always be the same.
The ARN format never changes for existing roles.

---

## TEAM-2 — Kubernetes Platform

### What you receive

Three IRSA role ARNs:

| Variable in stable-outputs.env | Role purpose |
|-------------------------------|--------------|
| `IAM_ESO_ROLE_ARN` | External Secrets Operator reads DB passwords from Secrets Manager |
| `IAM_LB_CONTROLLER_ROLE_ARN` | AWS Load Balancer Controller creates and manages the ALB |
| `IAM_EBS_CSI_ROLE_ARN` | EBS CSI Driver provisions persistent volumes (Prometheus, Grafana) |

### How IRSA works — the annotation

You activate an IRSA role by adding one annotation to the Kubernetes
ServiceAccount that the controller runs as. When the pod starts, EKS
automatically exchanges the ServiceAccount token for temporary AWS credentials
scoped to that role. No secrets, no env vars with AWS keys.

The annotation key is always:

```
eks.amazonaws.com/role-arn
```

### ESO — External Secrets Operator

When you install ESO (via Helm or manifest), make sure its ServiceAccount is
in namespace `external-secrets` and has the annotation below.

**ServiceAccount namespace:** `external-secrets`  
**ServiceAccount name:** `external-secrets-sa`

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets-sa
  namespace: external-secrets
  annotations:
    eks.amazonaws.com/role-arn: "<value of IAM_ESO_ROLE_ARN>"
```

If you use the ESO Helm chart, pass this via values:

```yaml
serviceAccount:
  create: true
  name: external-secrets-sa
  annotations:
    eks.amazonaws.com/role-arn: "<value of IAM_ESO_ROLE_ARN>"
```

What the role allows ESO to do: read any secret under the path prefix
`petclinic/dev/*` in AWS Secrets Manager. Nothing else.

### ALB Controller — AWS Load Balancer Controller

**ServiceAccount namespace:** `kube-system`  
**ServiceAccount name:** `aws-load-balancer-controller`

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: "<value of IAM_LB_CONTROLLER_ROLE_ARN>"
```

If you use the Helm chart (recommended):

```yaml
# In your Helm values file for aws-load-balancer-controller
serviceAccount:
  create: true
  name: aws-load-balancer-controller
  annotations:
    eks.amazonaws.com/role-arn: "<value of IAM_LB_CONTROLLER_ROLE_ARN>"

clusterName: petclinic-dev
region: us-east-1
vpcId: "<value of VPC_ID from dynamic-outputs.env>"
```

What the role allows: create and manage Application Load Balancers, target
groups, listeners, and security group rules. The role does not allow EC2
instance operations or IAM changes.

### EBS CSI Driver

The EBS CSI Driver role is applied to the EKS managed add-on, not to a
user-deployed Helm chart. TEAM-1 handles this in Terraform:

```hcl
# Already configured by TEAM-1 in the eks module
addon "aws-ebs-csi-driver" {
  service_account_role_arn = module.iam.ebs_csi_role_arn
}
```

You do not need to annotate anything for EBS CSI. When you create a
PersistentVolumeClaim with `storageClassName: gp2`, it will work
automatically. Verify it by checking:

```bash
kubectl get storageclass
# Expected: gp2 listed as (default) or available
```

### Verify Your Setup

After annotating service accounts, verify the role assumption works:

```bash
# Check ESO service account annotation
kubectl get serviceaccount external-secrets-sa \
  -n external-secrets \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'

# Check ALB Controller service account annotation
kubectl get serviceaccount aws-load-balancer-controller \
  -n kube-system \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
```

Both should print the correct role ARNs from your stable-outputs.env.

---

## TEAM-3 — CI/CD Pipeline

### What you receive

One OIDC role ARN:

| Variable in stable-outputs.env | Role purpose |
|-------------------------------|--------------|
| `IAM_GITHUB_ACTIONS_ROLE_ARN` | GitHub Actions assumes this role via OIDC to push Docker images to ECR |

### What OIDC federation means for you

Traditional CI/CD requires AWS access keys (ID + secret) stored as GitHub
secrets. If those keys leak, attackers have permanent AWS access.

With OIDC federation, there are no long-lived credentials. GitHub generates a
short-lived identity token for each workflow run. AWS validates that token
against the registered GitHub OIDC provider and returns temporary credentials
valid for that run only. When the run ends, the credentials expire.

Your GitHub Actions workflows never store or see an AWS secret key.

### GitHub Repository Secrets to Set

Go to your GitHub repository → Settings → Secrets and Variables → Actions.
Add these three secrets:

| Secret Name | Value | Where to get it |
|-------------|-------|-----------------|
| `AWS_REGION` | `us-east-1` | Fixed — our region |
| `AWS_ROLE_ARN` | *(ARN value)* | `cat team-outputs/stable-outputs.env` → `IAM_GITHUB_ACTIONS_ROLE_ARN` |
| `AWS_ACCOUNT_ID` | `482352877891` | Fixed — our AWS account |

These are stable values. Set them once and do not change them.

### Workflow Configuration

Every workflow that needs to push to ECR must include these two steps before
any Docker or ECR commands:

```yaml
permissions:
  id-token: write    # Required for OIDC — do not remove
  contents: read

steps:
  - name: Configure AWS credentials
    uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
      aws-region: ${{ secrets.AWS_REGION }}

  - name: Login to ECR
    run: |
      aws ecr get-login-password --region ${{ secrets.AWS_REGION }} | \
      docker login \
        --username AWS \
        --password-stdin \
        ${{ secrets.AWS_ACCOUNT_ID }}.dkr.ecr.${{ secrets.AWS_REGION }}.amazonaws.com
```

The `permissions: id-token: write` block is mandatory. Without it, GitHub will
not generate the OIDC token and the role assumption will fail.

### ECR Repository URLs

After the ECR login step, push images using this URL pattern:

```
482352877891.dkr.ecr.us-east-1.amazonaws.com/petclinic-dev/{service-name}:{tag}
```

Example for `customers-service` with commit SHA tag:

```bash
docker tag customers-service:local \
  482352877891.dkr.ecr.us-east-1.amazonaws.com/petclinic-dev/customers-service:${GITHUB_SHA::7}

docker push \
  482352877891.dkr.ecr.us-east-1.amazonaws.com/petclinic-dev/customers-service:${GITHUB_SHA::7}
```

The full list of ECR repository URLs is in stable-outputs.env under the
`ECR_*` variables (provided separately by TEAM-1 from the ECR module outputs).

### What the CI Role Can and Cannot Do

The `petclinic-github-actions-role` is scoped to ECR push operations only.

**Allowed:**
- `ecr:GetAuthorizationToken` — get ECR login token
- `ecr:PutImage`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload` — push images
- Read operations on petclinic ECR repositories

**Not allowed:**
- Running Terraform (`s3:*`, `dynamodb:*`)
- Accessing EKS API
- Reading Secrets Manager
- Any EC2, RDS, IAM operations

This is intentional. CI builds images and pushes them. Deployment is handled
by ArgoCD (TEAM-2), not by GitHub Actions.

---

## Rules — What Not to Do

These rules protect the infrastructure for the whole team:

```
DO NOT run terraform apply or terraform destroy.
    Only TEAM-1 runs Terraform.

DO NOT manually edit or delete the IAM roles in the AWS Console.
    The roles are Terraform-managed. Console changes will conflict on the next apply.

DO NOT add new policies to the IAM roles yourself.
    If you need additional permissions, open an issue with TEAM-1.

DO NOT store AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY in GitHub secrets.
    The OIDC role replaces those. If you see these variable names in a workflow,
    that workflow is using the old method and must be updated.

DO NOT use the IAM role ARNs from the dynamic-outputs.env file.
    IAM role ARNs are always in stable-outputs.env.
```

---

## Escalation — When to Contact TEAM-1

Contact TEAM-1 if:

- `IAMRolesStatus` in output-status.env shows `STALE` or is missing
- A pod fails with `AccessDenied` when calling Secrets Manager or ECR
- A GitHub Actions workflow fails at the `configure-aws-credentials` step
- You need to add an additional permission to one of the roles
- The ALB Controller cannot create the load balancer
- A PersistentVolumeClaim stays in `Pending` state (possible EBS CSI issue)

---

## Quick Reference Card

```
# TEAM-2 — check your service account annotations
kubectl get sa external-secrets-sa -n external-secrets -o yaml | grep role-arn
kubectl get sa aws-load-balancer-controller -n kube-system -o yaml | grep role-arn

# TEAM-3 — confirm the GitHub Actions role ARN
cat team-outputs/stable-outputs.env | grep IAM_GITHUB_ACTIONS_ROLE_ARN

# Verify all IAM roles exist in AWS
aws iam list-roles \
  --query 'Roles[?starts_with(RoleName, `petclinic`)].RoleName' \
  --output table

# Check infrastructure status before starting work
git pull && cat team-outputs/output-status.env
```
