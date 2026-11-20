resource "aws_cloudwatch_log_group" "svc" {
  for_each = local.services

  name              = "/ecs/${var.project_name}/${each.key}"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled" # standard AWS/ECS metrics are enough and cost nothing extra
  }
}

# The first task definition revision. After this, every release registers a new
# revision through CodePipeline/CodeDeploy, so Terraform ignores later changes.
resource "aws_ecs_task_definition" "svc" {
  for_each = local.services

  family                   = "${var.project_name}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.container_cpu
  memory                   = var.container_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = replace(
    jsonencode(local.container_defs[each.key]),
    "__IMAGE__",
    "${aws_ecr_repository.svc[each.key].repository_url}:${var.image_tag}",
  )
}

resource "aws_ecs_service" "svc" {
  for_each = local.services

  name                              = each.key
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.svc[each.key].arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 60

  # Releases are done by CodeDeploy (blue/green), not by ECS rolling updates.
  deployment_controller {
    type = "CODE_DEPLOY"
  }

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue[each.key].arn
    container_name   = each.key
    container_port   = local.container_port
  }

  service_registries {
    registry_arn = aws_service_discovery_service.svc[each.key].arn
  }

  depends_on = [aws_lb_listener_rule.svc]

  # CodeDeploy owns these after the first deployment.
  lifecycle {
    ignore_changes = [task_definition, load_balancer, desired_count]
  }
}
