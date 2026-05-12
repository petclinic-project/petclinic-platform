# =============================================================================
# terraform/modules/iam/main.tf
#
# Keycards for the four robots that need AWS access:
#
#   1. petclinic-{env}-eso-role           External Secrets Operator  (TEAM-2)
#   2. petclinic-{env}-lb-controller-role AWS Load Balancer Controller (TEAM-2)
#   3. petclinic-{env}-ebs-csi-role       EBS CSI Driver              (TEAM-2)
#   4. petclinic-github-actions-role      GitHub Actions CI push      (TEAM-3)
#
# Tags: Project / Environment / Team / ManagedBy are applied automatically by
# the AWS provider default_tags in provider.tf. Each resource only sets Name.
# =============================================================================

locals {
  name_prefix = "${var.project}-${var.environment}"

  # Strip the https:// prefix from the OIDC URL.
  # IAM trust policy condition keys require the bare hostname, not a full URL.
  # e.g. "oidc.eks.us-east-1.amazonaws.com/id/XXXX"  - not "https://..."
  oidc_url = trimprefix(var.oidc_provider_url, "https://")
}


# =============================================================================
# 1. EXTERNAL SECRETS OPERATOR (ESO)
#    Kubernetes SA : external-secrets-sa   namespace: external-secrets
#    Room it opens : Secrets Manager - the exact RDS master password secret
# =============================================================================

data "aws_iam_policy_document" "eso_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "${local.name_prefix}-eso-role"
  assume_role_policy = data.aws_iam_policy_document.eso_trust.json
  description        = "IRSA role - External Secrets Operator reads RDS credentials from Secrets Manager"

  tags = {
    Name = "${local.name_prefix}-eso-role"
  }
}

data "aws_iam_policy_document" "eso_permissions" {
  statement {
    sid    = "ReadRDSSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    # Scoped to the exact RDS secret ARN - not a broad path wildcard
    resources = [var.rds_secret_arn]
  }
}

# Inline policy - avoids iam:CreatePolicy (blocked by DMI course deny policy)
resource "aws_iam_role_policy" "eso" {
  name   = "${local.name_prefix}-eso-policy"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso_permissions.json
}


# =============================================================================
# 2. AWS LOAD BALANCER CONTROLLER
#    Kubernetes SA : aws-load-balancer-controller   namespace: kube-system
#    Room it opens : EC2 / ELB - creates and manages the Application Load Balancer
# =============================================================================

data "aws_iam_policy_document" "lb_controller_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lb_controller" {
  name               = "${local.name_prefix}-lb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_trust.json
  description        = "IRSA role - AWS Load Balancer Controller creates and manages the ALB"

  tags = {
    Name = "${local.name_prefix}-lb-controller-role"
  }
}

data "aws_iam_policy_document" "lb_controller_permissions" {

  statement {
    sid    = "DescribeNetworkResources"
    effect = "Allow"
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:DescribeCoipPools",
      "ec2:GetCoipPoolUsage",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageSecurityGroupRules"
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageLoadBalancers"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:SetWebAcl",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CertificateAndCognito"
    effect = "Allow"
    actions = [
      "acm:ListCertificates",
      "acm:DescribeCertificate",
      "iam:ListServerCertificates",
      "iam:GetServerCertificate",
      "cognito-idp:DescribeUserPoolClient",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "TagResources"
    effect = "Allow"
    actions = [
      "tag:GetResources",
      "tag:TagResources",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "ServiceLinkedRole"
    effect  = "Allow"
    actions = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }
}

# Inline policy - avoids iam:CreatePolicy (blocked by DMI course deny policy)
resource "aws_iam_role_policy" "lb_controller" {
  name   = "${local.name_prefix}-lb-controller-policy"
  role   = aws_iam_role.lb_controller.id
  policy = data.aws_iam_policy_document.lb_controller_permissions.json
}


# =============================================================================
# 3. EBS CSI DRIVER
#    Kubernetes SA : ebs-csi-controller-sa   namespace: kube-system
#    Room it opens : EBS storage - provisions volumes for Prometheus and Grafana
# =============================================================================

data "aws_iam_policy_document" "ebs_csi_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${local.name_prefix}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_trust.json
  description        = "IRSA role - EBS CSI Driver provisions persistent storage volumes"

  tags = {
    Name = "${local.name_prefix}-ebs-csi-role"
  }
}

# AWS provides a managed policy for the EBS CSI Driver - no custom policy needed
resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}


# =============================================================================
# 4. GITHUB ACTIONS CI ROLE
#    Used by  : TEAM-3 GitHub Actions workflows
#    Room it opens : ECR only - push Docker images, nothing else
#    No Kubernetes SA - trust is based on GitHub's OIDC identity token
# =============================================================================

# GitHub OIDC provider already exists in this AWS account - read it, don't recreate it.
# If you try to create it again Terraform throws EntityAlreadyExists.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scoped to a specific repo and branch - no other repo can assume this role
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.project}-github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json
  description        = "Keyless CI role - GitHub Actions pushes images to ECR via OIDC, no stored AWS keys"

  tags = {
    Name = "${var.project}-github-actions-role"
  }
}

data "aws_iam_policy_document" "github_actions_permissions" {
  # ECR login token - account-scoped, required before any docker push
  statement {
    sid       = "ECRLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Image push - scoped to petclinic ECR repos only, nothing else in the account
  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [
      "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/${var.project}-${var.environment}/*"
    ]
  }
}

# Inline policy - avoids iam:CreatePolicy (blocked by DMI course deny policy)
resource "aws_iam_role_policy" "github_actions" {
  name   = "${var.project}-github-actions-ecr-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}

