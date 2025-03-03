####################################################
# ECS module main.tf
####################################################

# ECS Cluster
resource "aws_ecs_cluster" "this" {
  name = var.cluster_name
}

# ECS Task Definition
resource "aws_ecs_task_definition" "this" {
  family                   = "${var.cluster_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = var.execution_role_arn
  cpu                      = var.cpu
  memory                   = var.memory

  container_definitions = jsonencode([
    {
      name      = "quest-container"
      image     = "${var.ecr_repository_url}:latest"
      essential = true
      memory    = 128
      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

# ECS Service
resource "aws_ecs_service" "this" {
  name            = "${var.cluster_name}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  launch_type     = "FARGATE"
  desired_count   = var.desired_count

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = true
  }

  # Because many ECS services also integrate with a Load Balancer,
  # you can optionally define LB details as variables or move them to a separate ALB module.
  # For example:
  #
  # load_balancer {
  #   target_group_arn = var.target_group_arn
  #   container_name   = "quest-container"
  #   container_port   = var.container_port
  # }
}
