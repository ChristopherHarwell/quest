####################################################
# Security Groups module outputs.tf
####################################################

output "alb_sg_id" {
  description = "The ID of the ALB security group"
  value       = aws_security_group.alb_sg.id
}

output "ecs_sg_id" {
  description = "The ID of the ECS security group"
  value       = aws_security_group.ecs_sg.id
}
