variable "project" {
  description = "Project name — used in role naming"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be 'dev' or 'prod'."
  }
}

variable "aws_account_id" {
  description = "AWS account ID — passed from data.aws_caller_identity in the environment root"
  type        = string
}

variable "aws_region" {
  description = "AWS region where resources live"
  type        = string
  default     = "us-east-1"
}

# ---------------------------------------------------------------------------
# EKS OIDC — values come from module.eks outputs
# ---------------------------------------------------------------------------

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN (module.eks.oidc_provider_arn)"
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL including https:// prefix (module.eks.oidc_provider_url) — the module strips the prefix internally"
  type        = string
}

# ---------------------------------------------------------------------------
# RDS secret — passed from module.rds.master_user_secret_arn
# Required so ESO gets the exact Secrets Manager ARN to read
# ---------------------------------------------------------------------------

variable "rds_secret_arn" {
  description = "Secrets Manager ARN of the AWS-managed RDS master user password (module.rds.master_user_secret_arn)"
  type        = string
  sensitive   = true
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC — scopes the CI role to one repo and branch
# ---------------------------------------------------------------------------

variable "github_org" {
  description = "GitHub organisation or user name that owns the application repository"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without the org prefix)"
  type        = string
}

variable "github_branch" {
  description = "Branch that is allowed to assume the GitHub Actions CI role"
  type        = string
  default     = "main"
}
