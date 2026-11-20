resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  drop_invalid_header_fields = true
  enable_deletion_protection = false # demo: allows terraform destroy
}

# Each service has TWO target groups. CodeDeploy points the listener rule at
# the "blue" group (current version) and sends the new version to the "green"
# group, then swaps them when the deployment succeeds.
resource "aws_lb_target_group" "blue" {
  for_each = local.services

  name                 = "${var.project_name}-${each.key}-blue"
  port                 = local.container_port
  protocol             = "HTTP"
  target_type          = "ip" # required for Fargate (awsvpc)
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "green" {
  for_each = local.services

  name                 = "${var.project_name}-${each.key}-green"
  port                 = local.container_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# Production listener. Anything that matches no service rule gets a 404.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\":\"not found\"}"
      status_code  = "404"
    }
  }
}

# Path-based routing: /auth/* -> auth, /orders* -> orders,
# /notify* and /notifications* -> notifications.
resource "aws_lb_listener_rule" "svc" {
  for_each = local.services

  listener_arn = aws_lb_listener.http.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue[each.key].arn
  }

  condition {
    path_pattern {
      values = each.value.paths
    }
  }

  # CodeDeploy rewrites the target group during a deployment. Terraform must
  # not "correct" it back.
  lifecycle {
    ignore_changes = [action]
  }
}
