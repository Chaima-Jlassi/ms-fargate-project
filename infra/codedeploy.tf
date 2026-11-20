resource "aws_codedeploy_app" "ecs" {
  name             = "${var.project_name}-app"
  compute_platform = "ECS"
}

# One deployment group per service. Each performs a blue/green release:
#   1. start the new tasks (green) next to the current ones (blue)
#   2. shift traffic gradually (canary/linear/all-at-once, see deployment_config_name)
#   3. roll back automatically if the deployment fails or the 5xx alarm fires
#   4. stop the old tasks after a short wait
resource "aws_codedeploy_deployment_group" "svc" {
  for_each = local.services

  app_name               = aws_codedeploy_app.ecs.name
  deployment_group_name  = "${each.key}-dg"
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = var.deployment_config_name

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  alarm_configuration {
    enabled = true
    alarms  = [aws_cloudwatch_metric_alarm.alb_5xx.alarm_name]
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 1
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.main.name
    service_name = aws_ecs_service.svc[each.key].name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.http.arn]
      }

      target_group {
        name = aws_lb_target_group.blue[each.key].name
      }

      target_group {
        name = aws_lb_target_group.green[each.key].name
      }
    }
  }
}
