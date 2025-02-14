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

# -----------------------------
# ECS Cluster
# -----------------------------
# An ECS (Elastic Container Service) cluster is a logical grouping of container instances 
# that manage and run containers. In this case, the cluster is created to host the ECS 
# tasks and services needed for the application. The name of the cluster is defined 
# explicitly to ensure it is easily identifiable in the AWS console.

# Creates an Amazon ECS (Elastic Container Service) cluster resource
# An ECS cluster is a logical grouping of container tasks and services
resource "aws_ecs_cluster" "quest_ecs" {
  # Assigns the name "quest-ecs-cluster" to this ECS cluster
  # This name will be visible in the AWS Console and used as an identifier
  # The name must be unique within your AWS account in the region
  name = "quest-ecs-cluster"
}


# -----------------------------
# CloudWatch Log Group
# -----------------------------
# Amazon CloudWatch Log Groups store log data from the ECS containers. This setup allows 
# logs to be collected, monitored, and analyzed for debugging and performance monitoring.
# The CloudWatch Log Group named "quest-ecs-task-logs" is checked for existence before 
# creating a new one to prevent duplicate resource creation.

# DATA SOURCE: Attempts to fetch information about an existing CloudWatch log group
data "aws_cloudwatch_log_group" "existing_log_group" {
  name = "quest-ecs-task-logs" # Looks for a log group with this exact name
}

# RESOURCE: Defines a new CloudWatch log group (if needed)
resource "aws_cloudwatch_log_group" "quest_task_logs" {
  name = "quest-ecs-task-logs" # Name for the log group to be created

  # LIFECYCLE BLOCK: Controls how Terraform handles this resource
  lifecycle {
    prevent_destroy = true # Protects the log group from accidental deletion
    # Even if 'terraform destroy' is run, this resource will remain
  }

  # COUNT CONDITIONAL: Determines if this resource should be created
  count = length(data.aws_cloudwatch_log_group.existing_log_group.name) > 0 ? 0 : 1
  # This creates a conditional:
  # - If existing_log_group.name has length > 0 (log group exists), count = 0 (don't create)
  # - If existing_log_group.name has length = 0 (no log group), count = 1 (create one)
  # This prevents duplicate log groups from being created
}


# -----------------------------
# Elastic Container Registry (ECR)
# -----------------------------
# Amazon ECR (Elastic Container Registry) is a fully managed Docker container registry that 
# allows you to store, manage, and deploy container images securely. This Terraform configuration 
# first checks if the repository already exists before attempting to create a new one.

# First block: Data source to query existing ECR repository
data "aws_ecr_repository" "existing_repo" {
  name = "quest-container-repository" # Looks up an ECR repo with this exact name
}

# Second block: Resource to create a new ECR repository if needed
resource "aws_ecr_repository" "quest_container_repo" {
  name = "quest-container-repository-priv" # Name for the ECR repository

  # Add these parameters to make it public
  force_delete = true

  # Configure repository as public
  image_scanning_configuration {
    scan_on_push = true
  }

  # Lifecycle block to protect against accidental deletion
  lifecycle {
    prevent_destroy = true # If set to true:
    # - Terraform will error if you try to delete this repository
    # - Protects against accidental deletion of images
    # - Repository must be deleted manually outside Terraform
  }

  # Count conditional to determine if this resource should be created
  count = length(data.aws_ecr_repository.existing_repo.repository_url) > 0 ? 0 : 1
  # Breaks down as:
  # 1. Checks length of existing repo's URL
  # 2. If length > 0 (repo exists): count = 0 (don't create new repo)
  # 3. If length = 0 (repo doesn't exist): count = 1 (create new repo)
  # This creates an idempotent setup that won't duplicate existing repositories
}

resource "aws_ecrpublic_repository" "quest_container_repo_public" {
  repository_name = "quest-container-repository-pub"

  catalog_data {
    about_text        = "Public container repository for Quest application"
    architectures     = ["x86-64"]
    operating_systems = ["Linux"]
    description       = "Quest application container repository"
  }

  count = length(data.aws_ecr_repository.existing_repo.repository_url) > 0 ? 0 : 1
}

output "ecr_public_url" {
  value = "public.ecr.aws/{your_registry_alias}/{your_repository_name}"
}
# -----------------------------
# ECS Task Definition
# -----------------------------
# A task definition is required to define how the ECS tasks should run, including which 
# Docker image to use, the amount of CPU and memory to allocate, and which network mode 
# to apply. This task definition is configured to use AWS Fargate, a serverless container 
# compute engine that eliminates the need to manage EC2 instances.

resource "aws_ecs_task_definition" "quest_task" {
  # Defines a unique name/identifier for the task family
  family = "quest-task"

  # Uses AWS VPC networking mode - required for Fargate
  # This enables tasks to have their own elastic network interface
  network_mode = "awsvpc"

  # Specifies this task must run on Fargate (serverless) instead of EC2
  requires_compatibilities = ["FARGATE"]

  # Sets the IAM execution role using coalesce() to pick the first non-null value:
  # 1. Tries to use a newly created role if it exists
  # 2. Falls back to an existing role if no new role was created
  execution_role_arn = coalesce(
    try(aws_iam_role.ecs_task_execution[0].arn, ""),
    data.aws_iam_role.existing_execution_role.arn
  )

  # Allocates 256 CPU units (0.25 vCPU) to the task
  cpu = 256
  # Allocates 512MB of memory to the task
  memory = 512

  # Defines the container(s) that will run in the task using JSON encoding
  container_definitions = jsonencode([
    {
      # Container name for reference
      name = "quest-container"

      # Sets container image location:
      # If ECR repo was created, uses that URL
      # Otherwise uses hardcoded fallback URL
      # image = length(aws_ecr_repository.quest_container_repo) > 0 ? "${aws_ecr_repository.quest_container_repo[0].repository_url}:latest" : "418272762224.dkr.ecr.us-east-1.amazonaws.com/quest-container-repository"
      image = "${aws_ecr_repository.quest_container_repo[0].repository_url}:latest"

      # Marks this container as required for the task
      essential = true

      # Sets container-specific memory limit
      memory = 128

      # Configures network ports
      portMappings = [
        {
          containerPort = 3000  # Application port inside container
          hostPort      = 3000  # Mapped port on host
          protocol      = "tcp" # Network protocol
        }
      ]

      # Sets up CloudWatch logging configuration
      logConfiguration = {
        logDriver = "awslogs" # Uses AWS CloudWatch logs
        options = {
          # Sets log group name (using first non-null between new/existing groups)
          awslogs-group = coalesce(
            try(aws_cloudwatch_log_group.quest_task_logs[0].name, ""),
            data.aws_cloudwatch_log_group.existing_log_group.name
          )
          awslogs-region        = var.aws_region # AWS region for logs
          awslogs-stream-prefix = "ecs"          # Log stream prefix
        }
      }
    }
  ])

  # Ensures log group exists before creating task definition
  depends_on = [aws_cloudwatch_log_group.quest_task_logs]
}


# -----------------------------
# ECS Service
# -----------------------------
# The ECS service ensures that a specified number of tasks (containers) are always running. 
# It also integrates with the load balancer to distribute traffic evenly across tasks.

resource "aws_ecs_service" "quest_service" {
  # Defines the name of the ECS service that will run our containers
  name = "quest-service"

  # Links this service to our previously created ECS cluster
  cluster = aws_ecs_cluster.quest_ecs.id

  # Specifies which task definition (container config) to use
  task_definition = aws_ecs_task_definition.quest_task.arn

  # Uses AWS Fargate - a serverless compute engine (no EC2 instances to manage)
  launch_type = "FARGATE"

  # Sets how many copies of the task should run simultaneously
  # Here we only want 1 container running at a time
  desired_count = 1

  # Network configuration block defines how the containers will be networked
  network_configuration {
    # Places containers in these two subnets for high availability
    subnets = [aws_subnet.quest_subnet_1.id, aws_subnet.quest_subnet_2.id]

    # Applies security group rules to control container traffic
    security_groups = [aws_security_group.ecs_sg.id]

    # Gives the container a public IP address so it can access the internet
    # Required for pulling container images and external API calls
    assign_public_ip = true
  }

  # Load balancer configuration to distribute traffic
  load_balancer {
    # Links to a target group that defines where traffic should be routed
    target_group_arn = aws_lb_target_group.quest_tg.arn

    # Specifies which container should receive the traffic
    container_name = "quest-container"

    # Defines which port on the container should receive traffic
    container_port = 3000
  }
}


# -----------------------------
# Application Load Balancer (ALB)
# -----------------------------
# The ALB acts as the entry point for external traffic and routes it to the ECS tasks.

# Retrieves information about an existing Application Load Balancer (ALB) 
# with the name "quest-alb" if it exists in AWS
data "aws_lb" "existing_lb" {
  name = "quest-alb"
}

# Creates a new Application Load Balancer if one doesn't already exist
resource "aws_lb" "quest_alb" {
  name               = "quest-alb"                                                  # Name of the ALB
  internal           = false                                                        # External facing ALB (public)
  load_balancer_type = "application"                                                # Specifies ALB type (vs Network LB)
  security_groups    = [aws_security_group.alb_sg.id]                               # Attaches security group
  subnets            = [aws_subnet.quest_subnet_1.id, aws_subnet.quest_subnet_2.id] # Places ALB in these subnets

  lifecycle {
    prevent_destroy = true # Prevents terraform destroy from removing this ALB
  }

  # Conditional creation:
  # - If existing_lb.arn has length > 0 (ALB exists), count = 0 (don't create)
  # - If existing_lb.arn is empty (no ALB), count = 1 (create new ALB)
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
# Security groups are used to define which inbound and outbound traffic is allowed.

# Creates an AWS Security Group specifically for an Application Load Balancer (ALB)
resource "aws_security_group" "alb_sg" {
  name   = "quest-alb-sg"       # Assigns name "quest-alb-sg" to the security group
  vpc_id = aws_vpc.quest_vpc.id # Associates this security group with the specified VPC

  # First ingress rule - HTTP traffic
  ingress {
    from_port   = 80            # Allows incoming traffic on port 80
    to_port     = 80            # Same as from_port since we only want port 80
    protocol    = "tcp"         # Uses TCP protocol for HTTP traffic
    cidr_blocks = ["0.0.0.0/0"] # Allows access from any IP address (0.0.0.0/0 means worldwide access)
  }

  # Second ingress rule - HTTPS traffic
  ingress {
    from_port   = 443           # Allows incoming traffic on port 443
    to_port     = 443           # Same as from_port since we only want port 443
    protocol    = "tcp"         # Uses TCP protocol for HTTPS traffic
    cidr_blocks = ["0.0.0.0/0"] # Allows access from any IP address (0.0.0.0/0 means worldwide access)
  }
}

# Security Group for ECS Task Networking (Ensures ECR connectivity)
resource "aws_security_group" "ecs_sg" {
  name   = "quest-ecs-sg"
  vpc_id = aws_vpc.quest_vpc.id

  # Allow inbound connections on port 3000 (application traffic)
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Open to public access (not ideal for security)
  }

  # Allow all outbound traffic (Ensures ECS can pull images from ECR)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # Allows all protocols
    cidr_blocks = ["0.0.0.0/0"] # Open to all destinations
  }

  # Allow outbound traffic to AWS ECR, S3, and CloudWatch Logs explicitly
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Open access for HTTPS traffic (needed for AWS APIs)
  }
}


# -----------------------------
# Application Load Balancer (ALB)
# -----------------------------
# IAM roles are required to grant permissions to the ECS tasks.

# Look up an existing IAM role by name that is used for ECS task execution
# This allows referencing a pre-existing role rather than creating a new one
data "aws_iam_role" "existing_execution_role" {
  name = "quest-ecs-task-execution-role"
}

# Creates an IAM role specifically for ECS task execution
# This role is crucial for ECS tasks to interact with AWS services securely
resource "aws_iam_role" "ecs_task_execution" {
  name = "quest-ecs-task-execution-role" # Defines a specific name for the IAM role

  # The assume role policy is a trust relationship that defines who can use this role
  # It's encoded in JSON format using jsonencode function
  assume_role_policy = jsonencode({
    Version = "2012-10-17" # Standard IAM policy version number
    Statement = [
      {
        Effect = "Allow" # Grants permission for the specified actions
        Principal = {
          # Only ECS tasks can assume this role
          # ecs-tasks.amazonaws.com is the AWS service principal for ECS
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole" # Allows the role to be assumed using AWS STS service
      }
    ]
  })

  # Lifecycle rule to prevent accidental deletion of this role
  lifecycle {
    prevent_destroy = true
  }

  # Conditional creation: only creates this role if an existing execution role is not found
  # Uses count parameter to control resource creation
  count = length(data.aws_iam_role.existing_execution_role.arn) > 0 ? 0 : 1
}

# Creates an IAM policy and attaches it to the ECS execution role
resource "aws_iam_role_policy" "ecs_execution_policy" {
  # Attaches to the created role only if it exists
  role = length(aws_iam_role.ecs_task_execution) > 0 ? one(aws_iam_role.ecs_task_execution[*].name) : null

  # Defines the actual permissions the role will have
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        # Grants permissions for:
        # - ECR operations (pulling container images)
        # - CloudWatch Logs operations (creating log groups/streams and sending logs)
        # - ECS execution permissions
        Action = [
          "ecr:GetAuthorizationToken",       # Authenticate with ECR
          "ecr:BatchCheckLayerAvailability", # Check if image layers exist
          "ecr:GetDownloadUrlForLayer",      # Get URLs to download layers
          "ecr:BatchGetImage",               # Pull container images
          "ecr-public:CreateRepository",
          "ecr-public:DescribeRepositories",
          "ecr-public:DescribeRegistries",
          "ecr-public:PutRepositoryCatalogData",
          "logs:CreateLogGroup",            # Create CloudWatch log groups
          "logs:CreateLogStream",           # Create log streams
          "logs:PutLogEvents",              # Send logs to CloudWatch
          "ecs:RunTask",                    # Run ECS tasks
          "ecs:StopTask",                   # Stop ECS tasks
          "ecs:DescribeTasks",              # Describe ECS tasks
          "ecs:DescribeClusters",           # Describe ECS clusters
          "ecs:DescribeContainerInstances", # Describe ECS container instances
          "ecs:ListTasks",                  # List running ECS tasks
          "ecs:RegisterTaskDefinition",     # Register new ECS task definitions
          "ecs:UpdateService",              # Update ECS services
          "ecs:DescribeServices",           # Describe ECS services
          "ecs:ListClusters",               # List ECS clusters
          "iam:PassRole"                    # Allows ECS to assume roles it needs
        ]
        Resource = "*" # These permissions apply to all resources
      }
    ]
  })
}

# Retrieves the AWS-managed AdministratorAccess policy
data "aws_iam_policy" "administrator_access" {
  arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Attaches the AdministratorAccess policy to the ECS execution role
resource "aws_iam_role_policy_attachment" "ecs_admin_access" {
  role       = length(aws_iam_role.ecs_task_execution) > 0 ? one(aws_iam_role.ecs_task_execution[*].name) : null
  policy_arn = data.aws_iam_policy.administrator_access.arn
}


# -----------------------------
# VPC & Subnets
# -----------------------------
# Creates a VPC (Virtual Private Cloud) with the CIDR block 10.0.0.0/16
# This gives us a private network with 65,536 available IP addresses (10.0.0.0 - 10.0.255.255)
resource "aws_vpc" "quest_vpc" {
  cidr_block = "10.0.0.0/16"
}

# Fetches information about AWS Availability Zones in the current region
# This data source allows us to reference AZ names dynamically
data "aws_availability_zones" "available" {}

# Creates the first subnet in the VPC
# Uses CIDR 10.0.0.0/20 providing 4,096 IP addresses (10.0.0.0 - 10.0.15.255)
# Placed in the first available Availability Zone ([0] index)
resource "aws_subnet" "quest_subnet_1" {
  vpc_id            = aws_vpc.quest_vpc.id
  cidr_block        = "10.0.0.0/20"
  availability_zone = data.aws_availability_zones.available.names[0]
}

# Creates the second subnet in the VPC
# Uses CIDR 10.0.16.0/20 providing another 4,096 IP addresses (10.0.16.0 - 10.0.31.255)
# Placed in the second available Availability Zone ([1] index)
resource "aws_subnet" "quest_subnet_2" {
  vpc_id            = aws_vpc.quest_vpc.id
  cidr_block        = "10.0.16.0/20"
  availability_zone = data.aws_availability_zones.available.names[1]
}

# Creates an Internet Gateway and attaches it to the VPC
# This allows resources in the VPC to communicate with the internet
resource "aws_internet_gateway" "quest_gw" {
  vpc_id = aws_vpc.quest_vpc.id
}

# Creates a route table for the VPC
# Includes a route that directs all external traffic (0.0.0.0/0) to the Internet Gateway
# This enables outbound internet access for resources using this route table
resource "aws_route_table" "quest_rt" {
  vpc_id = aws_vpc.quest_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.quest_gw.id
  }
}



# This block creates a VPC Endpoint for Amazon ECR API service
# - Allows private communication with ECR API for operations like authentication and image manifest retrieval
# - Uses Interface endpoint type which creates an ENI (Elastic Network Interface) in the specified subnets
# - Attaches to specified VPC using vpc_id
# - Associates with ECS security group to control access
# - Deploys across two subnets for high availability
# - Enables private DNS to allow using default ECR endpoints instead of VPC endpoint URLs
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.quest_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ecs_sg.id]
  subnet_ids          = [aws_subnet.quest_subnet_1.id, aws_subnet.quest_subnet_2.id]
  private_dns_enabled = true
}

# This block creates a VPC Endpoint for ECR Docker Registry service
# - Enables private Docker image pulls from ECR
# - Also uses Interface endpoint type with ENI
# - Same VPC, security group, and subnet configuration as ECR API endpoint
# - Private DNS enabled for seamless Docker operations
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.quest_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ecs_sg.id]
  subnet_ids          = [aws_subnet.quest_subnet_1.id, aws_subnet.quest_subnet_2.id]
  private_dns_enabled = true
}

# This block creates a VPC Endpoint for S3
# - Required because ECR stores Docker images in S3
# - Uses Gateway endpoint type (different from Interface type)
# - Gateway endpoints are AWS-managed and don't require ENIs
# - Associates with specified route table to route S3 traffic through the endpoint
# - No security groups needed as access is controlled via endpoint policies
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
# The output variable allows retrieving the ALB's DNS name, which is needed to access 
# the application externally.

output "alb_dns_name" {
  # Defines an output variable that will display the DNS name of the Application Load Balancer (ALB)
  description = "Load Balancer DNS Name"

  # Uses coalesce() function to return the first non-empty value from the given arguments
  # try() attempts to safely access aws_lb.quest_alb[0].dns_name without erroring if it doesn't exist
  # If the first option fails, falls back to data.aws_lb.existing_lb.dns_name
  value = coalesce(try(aws_lb.quest_alb[0].dns_name, ""), data.aws_lb.existing_lb.dns_name)
}
