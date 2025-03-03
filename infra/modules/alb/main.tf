####################################################
# ALB module main.tf
####################################################

resource "aws_iam_server_certificate" "this" {
  # If you already have a certificate ARN, you could make that a variable
  # instead of uploading a new cert to IAM. Adjust as needed.
  name             = "${var.alb_name}-ssl-cert"
  certificate_body = file(var.certificate_body_file)
  private_key      = file(var.private_key_file)
}

resource "aws_lb" "this" {
  name               = var.alb_name
  internal           = var.internal
  load_balancer_type = "application"
  security_groups    = var.security_groups
  subnets            = var.subnet_ids
}

resource "aws_lb_target_group" "this" {
  name        = var.target_group_name
  port        = var.target_group_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = var.health_check_path
    healthy_threshold   = 3
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.listener_port_https
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_iam_server_certificate.this.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.listener_port_http
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "${var.listener_port_https}"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
