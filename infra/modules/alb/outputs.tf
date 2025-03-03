####################################################
# ALB module outputs.tf
####################################################

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.this.dns_name
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.this.arn
}

output "certificate_arn" {
  description = "ARN of the IAM server certificate"
  value       = aws_iam_server_certificate.this.arn
}
