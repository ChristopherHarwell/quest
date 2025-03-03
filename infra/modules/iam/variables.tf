####################################################
# IAM module variables.tf
####################################################

variable "iam_role_name" {
  type        = string
  description = "Name of the ECS task execution IAM role"
  default     = "quest-ecs-task-execution-role"
}
