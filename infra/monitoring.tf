resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Any burst of server errors. This alarm is also wired into CodeDeploy: if it
# fires during a deployment, the deployment stops and rolls back to blue.
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project_name}-alb-5xx"
  alarm_description   = "Target 5xx errors behind the ALB. Also triggers CodeDeploy rollback."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = local.services

  alarm_name          = "${var.project_name}-${each.key}-cpu-high"
  alarm_description   = "${each.key} average CPU above 80% for 2 minutes"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = each.key
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "alarm", x = 0, y = 0, width = 24, height = 3
        properties = {
          title = "Alarms"
          alarms = concat(
            [aws_cloudwatch_metric_alarm.alb_5xx.arn],
            [for a in aws_cloudwatch_metric_alarm.cpu_high : a.arn],
          )
        }
      },
      {
        type = "metric", x = 0, y = 3, width = 8, height = 6
        properties = {
          title   = "ALB requests", region = var.aws_region, stat = "Sum", period = 60, view = "timeSeries"
          metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix]]
        }
      },
      {
        type = "metric", x = 8, y = 3, width = 8, height = 6
        properties = {
          title   = "5xx errors", region = var.aws_region, stat = "Sum", period = 60, view = "timeSeries"
          metrics = [["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.main.arn_suffix]]
        }
      },
      {
        type = "metric", x = 16, y = 3, width = 8, height = 6
        properties = {
          title   = "Response time (seconds)", region = var.aws_region, stat = "Average", period = 60, view = "timeSeries"
          metrics = [["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.main.arn_suffix]]
        }
      },
      {
        type = "metric", x = 0, y = 9, width = 8, height = 6
        properties = {
          title   = "CPU by service (%)", region = var.aws_region, stat = "Average", period = 60, view = "timeSeries"
          metrics = [for name in keys(local.services) : ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", name]]
        }
      },
      {
        type = "metric", x = 8, y = 9, width = 8, height = 6
        properties = {
          title   = "Memory by service (%)", region = var.aws_region, stat = "Average", period = 60, view = "timeSeries"
          metrics = [for name in keys(local.services) : ["AWS/ECS", "MemoryUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", name]]
        }
      },
      {
        type = "metric", x = 16, y = 9, width = 8, height = 6
        properties = {
          title   = "Redis CPU (%)", region = var.aws_region, stat = "Average", period = 60, view = "timeSeries"
          metrics = [["AWS/ElastiCache", "CPUUtilization", "CacheClusterId", "${aws_elasticache_replication_group.redis.replication_group_id}-001"]]
        }
      },
    ]
  })
}
