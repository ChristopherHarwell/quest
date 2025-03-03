####################################################
# ECS module variables.tf
####################################################

variable "cluster_name" {
  type        = string
  description = "Name of the ECS cluster"
  default     = "quest-ecs-cluster"
}

variable "execution_role_arn" {
  type        = string
  description = "IAM execution role ARN for ECS tasks"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs where the ECS tasks should run"
  default     = []
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs for the ECS tasks"
  default     = []
}

variable "ecr_repository_url" {
  type        = string
  description = "ECR repository URL to pull container images from"
}

variable "log_group_name" {
  type        = string
  description = "Name of the CloudWatch Log Group"
  default     = "quest-ecs-task-logs"
}

variable "aws_region" {
  type        = string
  description = "AWS Region"
  default     = "us-east-2"
}

variable "desired_count" {
  type        = number
  description = "Number of tasks to run in the ECS service"
  default     = 1
}

variable "cpu" {
  type        = number
  description = "CPU units for the Task Definition"
  default     = 256
}

variable "memory" {
  type        = number
  description = "Memory (MB) for the Task Definition"
  default     = 512
}

variable "container_port" {
  type        = number
  description = "Port on the container to receive traffic"
  default     = 3000
}
