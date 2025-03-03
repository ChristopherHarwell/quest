####################################################
# Security Groups module variables.tf
####################################################

variable "vpc_id" {
  type        = string
  description = "ID of the VPC in which to create the security groups"
}

variable "alb_sg_name" {
  type        = string
  description = "Name for the ALB security group"
  default     = "quest-alb-sg"
}

variable "ecs_sg_name" {
  type        = string
  description = "Name for the ECS security group"
  default     = "quest-ecs-sg"
}

variable "ecs_container_port" {
  type        = number
  description = "Inbound port for ECS containers"
  default     = 3000
}
