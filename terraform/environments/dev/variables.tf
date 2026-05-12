variable "aws_region" {
  description = "AWS region for the PetClinic platform"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

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

