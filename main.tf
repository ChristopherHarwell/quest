terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.86.1" # Pinning the AWS provider version ensures compatibility and prevents unexpected behavior due to provider updates.
    }
  }
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1" # The AWS provider configuration ensures all Terraform resources are deployed in the specified AWS region.
}


resource "aws_ecs_cluster" "quest_ecs" {
  name = "quest-ecs-cluster"
}


# -----------------------------
# CloudWatch Log Group
# -----------------------------
data "aws_cloudwatch_log_group" "existing_log_group" {
  name = "quest-ecs-task-logs" # Looks for a log group with this exact name
}

resource "aws_cloudwatch_log_group" "quest_task_logs" {
  name = "quest-ecs-task-logs" # Name for the log group to be created

  lifecycle {
    prevent_destroy = false # Protects the log group from accidental deletion
  }

  count = length(data.aws_cloudwatch_log_group.existing_log_group.name) > 0 ? 0 : 1
}


# -----------------------------
# Elastic Container Registry (ECR)
# -----------------------------
data "aws_ecr_repository" "existing_repo" {
  name = "quest-container-repository" # Looks up an ECR repo with this exact name
}

resource "aws_ecr_repository" "quest_container_repo" {
  name = "quest-container-repository-priv" # Name for the ECR repository

  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  lifecycle {
    prevent_destroy = false # If set to true:
  }

  count = length(data.aws_ecr_repository.existing_repo.repository_url) > 0 ? 0 : 1
}

resource "aws_ecr_repository_policy" "ecr_repo_policy" {
  repository = aws_ecr_repository.quest_container_repo.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.ecs_task_execution.arn
        }
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
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
  task_role_arn            = aws_iam_role.ecs_task_execution.arn
  cpu                      = 256
  memory                   = 512

  container_definitions = jsonencode([
    {
      name  = "quest-container"
      image = "${aws_ecr_repository.quest_container_repo.repository_url}:latest"
      essential = true
      memory = 128
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
          awslogs-group = aws_cloudwatch_log_group.quest_task_logs.name
          awslogs-region = var.aws_region
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
  name = "quest-service"

  cluster = aws_ecs_cluster.quest_ecs.id

  task_definition = aws_ecs_task_definition.quest_task.arn

  launch_type = "FARGATE"

  desired_count = 1

  network_configuration {
    subnets = [aws_subnet.quest_subnet_1.id, aws_subnet.quest_subnet_2.id]

    security_groups = [aws_security_group.ecs_sg.id]

    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.quest_tg.arn

    container_name = "quest-container"

    container_port = 3000
  }
}


# -----------------------------
# Application Load Balancer (ALB)
# -----------------------------
data "aws_lb" "existing_lb" {
  name = "quest-alb"
}

resource "aws_lb" "quest_alb" {
  name               = "quest-alb"                                                  # Name of the ALB
  internal           = false                                                        # External facing ALB (public)
  load_balancer_type = "application"                                                # Specifies ALB type (vs Network LB)
  security_groups    = [aws_security_group.alb_sg.id]                               # Attaches security group
  subnets            = [aws_subnet.quest_subnet_1.id, aws_subnet.quest_subnet_2.id] # Places ALB in these subnets

  lifecycle {
    prevent_destroy = false # Prevents terraform destroy from removing this ALB
  }
  count = length(data.aws_lb.existing_lb.arn) > 0 ? 0 : 1
}

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

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = coalesce(try(aws_lb.quest_alb[0].arn, ""), data.aws_lb.existing_lb.arn)
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
  name   = "quest-alb-sg"       # Assigns name "quest-alb-sg" to the security group
  vpc_id = aws_vpc.quest_vpc.id # Associates this security group with the specified VPC

  ingress {
    from_port   = 80            # Allows incoming traffic on port 80
    to_port     = 80            # Same as from_port since we only want port 80
    protocol    = "tcp"         # Uses TCP protocol for HTTP traffic
    cidr_blocks = ["0.0.0.0/0"] # Allows access from any IP address (0.0.0.0/0 means worldwide access)
  }

  ingress {
    from_port   = 443           # Allows incoming traffic on port 443
    to_port     = 443           # Same as from_port since we only want port 443
    protocol    = "tcp"         # Uses TCP protocol for HTTPS traffic
    cidr_blocks = ["0.0.0.0/0"] # Allows access from any IP address (0.0.0.0/0 means worldwide access)
  }
}

resource "aws_security_group" "ecs_sg" {
  name   = "quest-ecs-sg"
  vpc_id = aws_vpc.quest_vpc.id

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Open to public access (not ideal for security)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # Allows all protocols
    cidr_blocks = ["0.0.0.0/0"] # Open to all destinations
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }
}


# -----------------------------
# Application Load Balancer (ALB)
# -----------------------------
data "aws_iam_role" "existing_execution_role" {
  name = "quest-ecs-task-execution-role"
}

resource "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_execution_policy" {
  role = aws_iam_role.ecs_task_execution.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

data "aws_iam_policy" "administrator_access" {
  arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy_attachment" "ecs_admin_access" {
  role       = length(aws_iam_role.ecs_task_execution) > 0 ? one(aws_iam_role.ecs_task_execution[*].name) : null
  policy_arn = data.aws_iam_policy.administrator_access.arn
}

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

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.quest_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ecs_sg.id]
  subnet_ids          = [aws_subnet.quest_subnet_1.id, aws_subnet.quest_subnet_2.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.quest_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ecs_sg.id]
  subnet_ids          = [aws_subnet.quest_subnet_1.id, aws_subnet.quest_subnet_2.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.quest_vpc.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.quest_rt.id]
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
  value = coalesce(try(aws_lb.quest_alb[0].dns_name, ""), data.aws_lb.existing_lb.dns_name)
}
