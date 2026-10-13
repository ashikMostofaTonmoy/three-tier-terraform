# A CloudWatch dashboard that makes the cutover visible: requests per color,
# healthy instances per color, errors. During a deploy the blue and green
# request lines cross; during a switch-back they cross back.
# Console: CloudWatch → Dashboards → three-tier-terraform-16-blue-green.

locals {
  alb_dim = module.alb.alb_arn_suffix
  tg_dim  = module.alb.backend_target_group_arn_suffixes

  # One series per color, colored to match.
  per_color = {
    blue  = "#1d4ed8"
    green = "#15803d"
  }
}

resource "aws_cloudwatch_dashboard" "blue_green" {
  dashboard_name = "three-tier-terraform-16-blue-green"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "## Blue/green — which color serves users?\nThe color with requests is **live**; the other is **idle** (healthy, running the other release, serving nobody). A deploy or switch-back shows up as the two request lines crossing."
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 16
        height = 8
        properties = {
          title   = "Requests per color (users' traffic)"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Sum"
          metrics = [
            for c, color in local.per_color :
            ["AWS/ApplicationELB", "RequestCount", "TargetGroup", local.tg_dim[c], "LoadBalancer", local.alb_dim, { label = c, color = color }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 2
        width  = 8
        height = 8
        properties = {
          title   = "Healthy instances per color"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Minimum"
          metrics = [
            for c, color in local.per_color :
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", local.tg_dim[c], "LoadBalancer", local.alb_dim, { label = c, color = color }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 10
        width  = 24
        height = 6
        properties = {
          title   = "Backend errors (5xx) per color — should stay at zero through a switch"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Sum"
          metrics = [
            for c, color in local.per_color :
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "TargetGroup", local.tg_dim[c], "LoadBalancer", local.alb_dim, { label = c, color = color }]
          ]
        }
      },
    ]
  })
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.blue_green.dashboard_name}"
}
