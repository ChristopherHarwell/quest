####################################################
# ALB module variables.tf
####################################################

variable "alb_name" {
  type        = string
  description = "Name of the Application Load Balancer"
  default     = "quest-alb"
}

variable "security_groups" {
  type        = list(string)
  description = "List of security group IDs to attach to the ALB"
  default     = []
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the ALB"
  default     = []
}

variable "internal" {
  type        = bool
  description = "Whether the ALB should be internal (true) or public (false)"
  default     = false
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for the target group"
}

variable "certificate_body_file" {
  type        = string
  description = "Path to the SSL certificate body file"
}

variable "private_key_file" {
  type        = string
  description = "Path to the SSL certificate private key file"
}

variable "listener_port_https" {
  type        = number
  description = "Port for the HTTPS listener"
  default     = 443
}

variable "listener_port_http" {
  type        = number
  description = "Port for the HTTP listener (for redirect)"
  default     = 80
}

variable "target_group_name" {
  type        = string
  description = "Name of the target group"
  default     = "quest-target-group"
}

variable "target_group_port" {
  type        = number
  description = "Target group port"
  default     = 3000
}

variable "health_check_path" {
  type        = string
  description = "Health check path for the target group"
  default     = "/"
}
