# Security Group for ALB
resource "aws_security_group" "alb" {
  name        = "ciot-alb-sg-${var.environment}"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from Internet (for ESP32)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Optional: HTTPS ingress (uncomment if using HTTPS)
  # ingress {
  #   description = "HTTPS from Internet"
  #   from_port   = 443
  #   to_port     = 443
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ciot-alb-sg-${var.environment}"
    Environment = var.environment
  }
}

# Application Load Balancer for ESP32 access
resource "aws_lb" "backend" {
  name               = "ciot-backend-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false
  enable_http2              = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name        = "ciot-backend-alb-${var.environment}"
    Environment = var.environment
  }
}

# Target Group for ECS Tasks
resource "aws_lb_target_group" "backend" {
  name        = "ciot-backend-tg-${var.environment}"
  port        = var.backend_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name        = "ciot-backend-tg-${var.environment}"
    Environment = var.environment
  }
}

# Target Group for Frontend ECS Tasks
resource "aws_lb_target_group" "frontend" {
  name        = "ciot-frontend-tg-${var.environment}"
  port        = var.frontend_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = {
    Name        = "ciot-frontend-tg-${var.environment}"
    Environment = var.environment
  }
}

# ALB Listener (HTTP) - Path-based routing
resource "aws_lb_listener" "backend" {
  load_balancer_arn = aws_lb.backend.arn
  port              = "80"
  protocol          = "HTTP"

  # Default: route to frontend (catch-all)
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# ALB Listener Rule: Backend API (higher priority - checked first)
resource "aws_lb_listener_rule" "backend_api" {
  listener_arn = aws_lb_listener.backend.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/health", "/db-health", "/readings-latest*"]
    }
  }
}

# Optional: HTTPS Listener (requires ACM certificate)
# Uncomment and configure if you have an SSL certificate
# resource "aws_lb_listener" "backend_https" {
#   load_balancer_arn = aws_lb.backend.arn
#   port              = "443"
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
#   certificate_arn   = var.ssl_certificate_arn
#
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.backend.arn
#   }
# }

