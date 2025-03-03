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
  source               = "./infra/modules/vpc"
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidr_1 = "10.0.1.0/24"
  public_subnet_cidr_2 = "10.0.2.0/24"
}


module "ecs" {
  source             = "./modules/ecs"
  cluster_name       = "quest-ecs-cluster"
  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [aws_security_group.ecs_sg.id]

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

# -----------------------------
# Elastic Container Registry (ECR)
# -----------------------------
resource "aws_ecr_repository" "quest_container_repo" {
  name = "quest-container-repository"
}

resource "aws_ecr_repository_policy" "quest_ecr_policy" {
  repository = aws_ecr_repository.quest_container_repo.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { "AWS" : aws_iam_role.ecs_task_execution.arn }
        Action    = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeRepositories",
          "ecr:GetRepositoryPolicy"
        ]
      }
    ]
  })
}


# ALB

# -----------------------------
# Application Load Balancer (ALB)
# -----------------------------
resource "aws_lb" "quest_alb" {
  name               = "quest-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  # Use the module outputs for subnets
  subnets            = module.vpc.public_subnet_ids
}

# Target Group for Load Balancer
resource "aws_lb_target_group" "quest_tg" {
  name        = "quest-target-group"
  port        = 3000
  protocol    = "HTTP"
  # Use the module output for the VPC ID
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 3
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
}




# SSL
resource "aws_iam_server_certificate" "quest_ssl_cert" {
  name             = "quest_ssl_cert"
  certificate_body = file("ssl_cert/wildcard_certificate.pem")
  private_key      = file("ssl_cert/wildcard_private_key.pem")
}

# HTTPS Listener
resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.quest_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_iam_server_certificate.quest_ssl_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.quest_tg.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.quest_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# -----------------------------
# Security Groups
# -----------------------------
resource "aws_security_group" "alb_sg" {
  name   = "quest-alb-sg"
  # Use the module output for the VPC ID
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_sg" {
  name   = "quest-ecs-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------
# IAM Roles & Policies for ECS
# -----------------------------
resource "aws_iam_role" "ecs_task_execution" {
  name = "quest-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_execution_policy" {
  role = aws_iam_role.ecs_task_execution.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
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
