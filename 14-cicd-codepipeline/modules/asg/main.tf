# A launch template is the "how to build one instance" recipe (AMI, type,
# SGs, IAM role, boot script). The ASG is the "keep N of them alive"
# controller. Every change to the template creates a new numbered version.
resource "aws_launch_template" "this" {
  name_prefix            = "${var.name}-"
  image_id               = var.ami_id
  instance_type          = var.instance_type
  vpc_security_group_ids = var.security_group_ids
  user_data              = base64encode(var.user_data)
  update_default_version = true

  iam_instance_profile {
    name = var.iam_instance_profile
  }

  # 1-minute CloudWatch metrics instead of 5-minute — scaling alarms react
  # in ~3 minutes instead of ~15. Costs a few cents per instance-month.
  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
}

resource "aws_autoscaling_group" "this" {
  name                = var.name
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = var.subnet_ids
  target_group_arns   = var.target_group_arns

  # "ELB" = an instance is unhealthy if EITHER EC2 status checks fail OR
  # the load balancer's health check fails. The default ("EC2") only
  # notices a dead machine — not a live machine with a crashed app.
  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period
  default_instance_warmup   = 60

  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  # A new launch template version (new AMI, new user_data, new instance
  # type) triggers a rolling replacement, never dropping below half capacity.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  dynamic "tag" {
    for_each = merge({ Name = var.name, ManagedBy = "terraform" }, var.extra_tags)
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  # Scaling policies change desired_capacity at runtime. Without this, the
  # next `terraform apply` would "correct" it back to the starting value —
  # silently undoing a scale-out in the middle of a traffic spike.
  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

# --- Target tracking: name a metric and a target, AWS creates and manages
# the CloudWatch alarms itself (both directions).
resource "aws_autoscaling_policy" "target_cpu" {
  count                  = var.target_cpu == null ? 0 : 1
  name                   = "${var.name}-target-cpu"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.target_cpu
  }
}

# --- Step scaling: you own the alarms and decide how big each step is.
# Step bounds are relative to the alarm threshold (60%): 0-20 above it
# (60-80% CPU) adds 1 instance, 20+ above it (>80%) adds 2.
resource "aws_autoscaling_policy" "step_out" {
  count                     = var.step_scaling ? 1 : 0
  name                      = "${var.name}-step-out"
  autoscaling_group_name    = aws_autoscaling_group.this.name
  policy_type               = "StepScaling"
  adjustment_type           = "ChangeInCapacity"
  metric_aggregation_type   = "Average"
  estimated_instance_warmup = 60

  step_adjustment {
    scaling_adjustment          = 1
    metric_interval_lower_bound = 0
    metric_interval_upper_bound = 20
  }

  step_adjustment {
    scaling_adjustment          = 2
    metric_interval_lower_bound = 20
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count               = var.step_scaling ? 1 : 0
  alarm_name          = "${var.name}-cpu-high"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = 60
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_autoscaling_policy.step_out[0].arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this.name
  }
}

resource "aws_autoscaling_policy" "step_in" {
  count                   = var.step_scaling ? 1 : 0
  name                    = "${var.name}-step-in"
  autoscaling_group_name  = aws_autoscaling_group.this.name
  policy_type             = "StepScaling"
  adjustment_type         = "ChangeInCapacity"
  metric_aggregation_type = "Average"

  step_adjustment {
    scaling_adjustment          = -1
    metric_interval_upper_bound = 0
  }
}

# Scale-in waits longer (5 min) than scale-out (2 min) on purpose: adding
# capacity late hurts users, removing it late only costs a few cents.
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  count               = var.step_scaling ? 1 : 0
  alarm_name          = "${var.name}-cpu-low"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = 20
  comparison_operator = "LessThanThreshold"
  alarm_actions       = [aws_autoscaling_policy.step_in[0].arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this.name
  }
}
