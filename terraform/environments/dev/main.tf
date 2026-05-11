data "aws_caller_identity" "current" {}

module "vpc" {
  source = "../../modules/vpc"

  project      = var.project
  environment  = var.environment
  cluster_name = "${var.project}-${var.environment}"

  vpc_cidr = "10.0.0.0/16"

  availability_zones = [
    "us-east-1a",
    "us-east-1b"
  ]

  public_subnet_cidrs = [
    "10.0.1.0/24",
    "10.0.2.0/24"
  ]
}

module "eks" {
  source = "../../modules/eks"

  project      = var.project
  environment  = var.environment
  cluster_name = "${var.project}-${var.environment}"

  cluster_version = "1.33"

  subnet_ids = module.vpc.public_subnet_ids

  cluster_security_group_id = module.vpc.eks_cluster_security_group_id
  node_security_group_id    = module.vpc.eks_node_security_group_id

  node_instance_types = ["t4g.small"]
  node_ami_type       = "AL2023_ARM_64_STANDARD"
  node_capacity_type  = "ON_DEMAND"
  node_disk_size      = 20

  node_desired_size = 2
  node_min_size     = 2
  node_max_size     = 4
}

module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment

  service_names = [
    "config-server",
    "discovery-server",
    "api-gateway",
    "customers-service",
    "visits-service",
    "vets-service",
    "genai-service",
    "admin-server"
  ]

  image_tag_mutability          = "MUTABLE"
  scan_on_push                  = true
  untagged_image_retention_days = 7
  tagged_image_retention_count  = 20
}
