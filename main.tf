####################################################
# Root-level main.tf
####################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.86.1"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "default"
}

#
# Call the VPC module
#
module "vpc" {
  source               = "./modules/vpc"
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidr_1 = "10.0.1.0/24"
  public_subnet_cidr_2 = "10.0.2.0/24"
}


module "ecs" {
  source             = "./modules/ecs"
  cluster_name       = "quest-ecs-cluster"
  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [module.security_groups.ecs_sg_id]

  ecr_repository_url = aws_ecr_repository.quest_container_repo.repository_url
  log_group_name     = aws_cloudwatch_log_group.quest_task_logs.name
  aws_region         = var.aws_region

  desired_count = 1
  cpu           = 256
  memory        = 512
  container_port = 3000
}
# -----------------------------
# CloudWatch Log Group
# -----------------------------
resource "aws_cloudwatch_log_group" "quest_task_logs" {
  name = "quest-ecs-task-logs"
}

module "ecr" {
  source                  = "./modules/ecr"
  repo_name              = "quest-container-repository"
  execution_role_arn     = aws_iam_role.ecs_task_execution.arn
  enable_repository_policy = true
}

module "alb" {
  source                = "./modules/alb"
  alb_name             = "quest-alb"
  security_groups      = [module.security_groups.alb_sg_id]
  subnet_ids           = module.vpc.public_subnet_ids
  internal             = false
  vpc_id               = module.vpc.vpc_id
  certificate_body_file = "ssl_cert/wildcard_certificate.pem"
  private_key_file      = "ssl_cert/wildcard_private_key.pem"
  listener_port_https  = 443
  listener_port_http   = 80
  target_group_name    = "quest-target-group"
  target_group_port    = 3000
  health_check_path    = "/"
}

module "security_groups" {
  source             = "./modules/security_groups"
  vpc_id             = module.vpc.vpc_id
  alb_sg_name        = "quest-alb-sg"
  ecs_sg_name        = "quest-ecs-sg"
  ecs_container_port = 3000
}

module "iam_ecs" {
  source        = "./modules/iam"
  iam_role_name = "quest-ecs-task-execution-role"
}

resource "aws_ecs_task_definition" "quest_task" {
  execution_role_arn = module.iam_ecs.iam_role_arn
}

# -----------------------------
# Variables
# -----------------------------
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
}

# -----------------------------
# Outputs
# -----------------------------
output "alb_dns_name" {
  description = "Load Balancer DNS Name"
  value       = aws_lb.quest_alb.dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.quest_container_repo.repository_url
}
