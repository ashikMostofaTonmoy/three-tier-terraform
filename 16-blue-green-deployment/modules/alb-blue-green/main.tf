# Blue/green at the load balancer: TWO backend target groups, and a single
# listener rule that splits /api/* traffic between them by weight.
#
#   live   = weight 100  → every user request
#   idle   = weight 0    → no user requests, but reachable for testing via
#                          the X-Color header rules below
#
# A release is switched by changing two numbers on one rule — one API call,
# effective for new requests within seconds, and reversible the same way.

locals {
  colors = ["blue", "green"]
}

resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = var.security_group_ids

  tags = { Name = "${var.name}-alb" }
}

resource "aws_lb_target_group" "frontend" {
  name                 = "${var.name}-fe"
  port                 = 80
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "backend" {
  for_each             = toset(local.colors)
  name                 = "${var.name}-be-${each.key}"
  port                 = 3000
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Color = each.key }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# --- Test door: "X-Color: green" reaches the green fleet directly, whatever
# the weights say. Lets the pipeline (or you, with curl) test the idle
# color through the REAL load balancer before any user is switched.
resource "aws_lb_listener_rule" "by_header" {
  for_each     = { blue = 1, green = 2 }
  listener_arn = aws_lb_listener.http.arn
  priority     = each.value

  condition {
    path_pattern {
      values = var.backend_paths
    }
  }

  condition {
    http_header {
      http_header_name = "X-Color"
      values           = [each.key]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend[each.key].arn
  }
}

# --- The switch: weighted forward to both colors.
resource "aws_lb_listener_rule" "backend_weighted" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  condition {
    path_pattern {
      values = var.backend_paths
    }
  }

  action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.backend["blue"].arn
        weight = var.initial_live_color == "blue" ? 100 : 0
      }
      target_group {
        arn    = aws_lb_target_group.backend["green"].arn
        weight = var.initial_live_color == "green" ? 100 : 0
      }
    }
  }

  # Terraform creates the rule; the deploy workflow moves the weights.
  # Without this, the next `terraform apply` would silently switch users
  # back to whatever color the code above says.
  lifecycle {
    ignore_changes = [action]
  }
}
