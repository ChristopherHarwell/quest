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

# -----------------------------
# ECS Cluster
# -----------------------------
resource "aws_ecs_cluster" "quest_ecs" {
  name = "quest-ecs-cluster"
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


# -----------------------------
# ECS Task Definition
# -----------------------------
resource "aws_ecs_task_definition" "quest_task" {
  family                   = "quest-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  cpu                      = 256
  memory                   = 512

  container_definitions = jsonencode([
    {
      name      = "quest-container"
      image     = "${aws_ecr_repository.quest_container_repo.repository_url}:latest"
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
          awslogs-group         = aws_cloudwatch_log_group.quest_task_logs.name
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
resource "aws_lb" "quest_alb" {
  name               = "quest-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.quest_subnet_1.id, aws_subnet.quest_subnet_2.id]
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
  load_balancer_arn = aws_lb.quest_alb.arn
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
  vpc_id                  = aws_vpc.quest_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

}

resource "aws_subnet" "quest_subnet_2" {
  vpc_id                  = aws_vpc.quest_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

}

resource "aws_route_table_association" "quest_assoc_1" {
  subnet_id      = aws_subnet.quest_subnet_1.id
  route_table_id = aws_route_table.quest_rt.id
}

resource "aws_route_table_association" "quest_assoc_2" {
  subnet_id      = aws_subnet.quest_subnet_2.id
  route_table_id = aws_route_table.quest_rt.id
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
  value       = aws_lb.quest_alb.dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.quest_container_repo.repository_url
}
