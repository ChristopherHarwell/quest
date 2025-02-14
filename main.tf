terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.86.1"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------
# ECS Cluster
# -----------------------------
resource "aws_ecs_cluster" "quest_ecs" {
  name = "quest-ecs-cluster"
}

# -----------------------------
# CloudWatch Log Group
# -----------------------------
data "aws_cloudwatch_log_group" "existing_log_group" {
  name = "quest-ecs-task-logs"
}

resource "aws_cloudwatch_log_group" "quest_task_logs" {
  name = "quest-ecs-task-logs"

  lifecycle {
    prevent_destroy = true
  }

  count = length(data.aws_cloudwatch_log_group.existing_log_group.name) > 0 ? 0 : 1
}

# -----------------------------
# Elastic Container Registry (ECR)
# -----------------------------
data "aws_ecr_repository" "existing_repo" {
  name = "quest-container-repository"
}

resource "aws_ecr_repository" "quest_container_repo" {
  name = "quest-container-repository"

  lifecycle {
    prevent_destroy = true
  }
  count = length(data.aws_ecr_repository.existing_repo.repository_url) > 0 ? 0 : 1
}

# -----------------------------
# ECS Task Definition
# -----------------------------
resource "aws_ecs_task_definition" "quest_task" {
  family                   = "quest-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = length(aws_iam_role.ecs_task_execution) > 0 ? aws_iam_role.ecs_task_execution[0].arn : ""
  cpu                      = 256
  memory                   = 512

  container_definitions = jsonencode([
    {
      name      = "quest-container"
      image     = length(aws_ecr_repository.quest_container_repo) > 0 ? "${aws_ecr_repository.quest_container_repo[0].repository_url}:latest" : "418272762224.dkr.ecr.us-east-1.amazonaws.com/quest-container-repository"
      essential = true
      memory    = 128
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = length(aws_cloudwatch_log_group.quest_task_logs) > 0 ? aws_cloudwatch_log_group.quest_task_logs[0].name : ""
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

# -----------------------------
# ECS Service
# -----------------------------
resource "aws_ecs_service" "quest_service" {
  name            = "quest-service"
  cluster         = aws_ecs_cluster.quest_ecs.id
  task_definition = aws_ecs_task_definition.quest_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.quest_subnet_1.id, aws_subnet.quest_subnet_2.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.quest_tg.arn
    container_name   = "quest-container"
    container_port   = 3000
  }
}

# -----------------------------
# Application Load Balancer (ALB)
# -----------------------------
data "aws_lb" "existing_lb" {
  name = "quest-alb"
}

resource "aws_lb" "quest_alb" {
  name               = "quest-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.quest_subnet_1.id, aws_subnet.quest_subnet_2.id]

  lifecycle {
    prevent_destroy = true
  }

  count = length(data.aws_lb.existing_lb.arn) > 0 ? 0 : 1
}

# Target Group for Load Balancer
resource "aws_lb_target_group" "quest_tg" {
  name        = "quest-target-group"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.quest_vpc.id
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

# HTTP Listener
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = length(aws_lb.quest_alb) > 0 ? aws_lb.quest_alb[0].arn : ""
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.quest_tg.arn
  }
}

# -----------------------------
# Security Groups
# -----------------------------
resource "aws_security_group" "alb_sg" {
  name   = "quest-alb-sg"
  vpc_id = aws_vpc.quest_vpc.id

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
  vpc_id = aws_vpc.quest_vpc.id

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
data "aws_iam_role" "existing_execution_role" {
  name = "quest-ecs-task-execution-role"
}

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


  lifecycle {
    prevent_destroy = true
  }

  count = length(data.aws_iam_role.existing_execution_role.arn) > 0 ? 0 : 1
}

resource "aws_iam_role_policy" "ecs_execution_policy" {
  role = length(aws_iam_role.ecs_task_execution) > 0 ? one(aws_iam_role.ecs_task_execution[*].name) : null

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------
# VPC & Subnets
# -----------------------------
resource "aws_vpc" "quest_vpc" {
  cidr_block = "10.0.0.0/16"
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "quest_subnet_1" {
  vpc_id            = aws_vpc.quest_vpc.id
  cidr_block        = "10.0.0.0/20"
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_subnet" "quest_subnet_2" {
  vpc_id            = aws_vpc.quest_vpc.id
  cidr_block        = "10.0.16.0/20"
  availability_zone = data.aws_availability_zones.available.names[1]
}

resource "aws_internet_gateway" "quest_gw" {
  vpc_id = aws_vpc.quest_vpc.id
}

resource "aws_route_table" "quest_rt" {
  vpc_id = aws_vpc.quest_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.quest_gw.id
  }
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
  value       = length(aws_lb.quest_alb) > 0 ? aws_lb.quest_alb[0].dns_name : ""
}
