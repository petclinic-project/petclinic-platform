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
