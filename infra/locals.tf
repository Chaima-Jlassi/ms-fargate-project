data "aws_caller_identity" "current" {}

locals {
  container_port = 3000

  # One entry per microservice. `paths` are the ALB path patterns that route to
  # it; `priority` orders the listener rules.
  services = {
    auth = {
      paths    = ["/auth/*"]
      priority = 10
    }
    orders = {
      paths    = ["/orders*"]
      priority = 20
    }
    notifications = {
      paths    = ["/notify*", "/notifications*"]
      priority = 30
    }
  }

  # rediss:// = Redis over TLS (the cluster has in-transit encryption enabled)
  redis_url = "rediss://${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379"

  # The X-Ray daemon runs as a sidecar in every task and listens on localhost.
  xray_env = [
    { name = "AWS_XRAY_DAEMON_ADDRESS", value = "127.0.0.1:2000" },
    { name = "AWS_XRAY_CONTEXT_MISSING", value = "LOG_ERROR" },
  ]

  service_env = {
    auth = concat([
      { name = "PORT", value = tostring(local.container_port) },
      { name = "REDIS_URL", value = local.redis_url },
    ], local.xray_env)

    orders = concat([
      { name = "PORT", value = tostring(local.container_port) },
      { name = "AUTH_SERVICE_URL", value = "http://auth.${var.namespace_name}:${local.container_port}" },
      { name = "NOTIFICATIONS_SERVICE_URL", value = "http://notifications.${var.namespace_name}:${local.container_port}" },
    ], local.xray_env)

    notifications = concat([
      { name = "PORT", value = tostring(local.container_port) },
    ], local.xray_env)
  }

  # Injected by ECS from Secrets Manager at task start; never stored in the
  # task definition, the image or Git.
  service_secrets = {
    auth = [
      { name = "JWT_SECRET", valueFrom = aws_secretsmanager_secret.jwt.arn },
    ]
    orders        = []
    notifications = []
  }

  # The container definitions. "__IMAGE__" is replaced with the real image URI
  # (initial task definition) or with <IMAGE1_NAME> (the template that
  # CodePipeline fills in on each release).
  container_defs = {
    for name, svc in local.services : name => [
      {
        name         = name
        image        = "__IMAGE__"
        essential    = true
        portMappings = [{ containerPort = local.container_port, protocol = "tcp" }]
        environment  = local.service_env[name]
        secrets      = local.service_secrets[name]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.svc[name].name
            "awslogs-region"        = var.aws_region
            "awslogs-stream-prefix" = "app"
          }
        }
      },
      {
        name              = "xray-daemon"
        image             = var.xray_daemon_image
        essential         = false
        cpu               = 32
        memoryReservation = 64
        portMappings      = [{ containerPort = 2000, protocol = "udp" }]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.svc[name].name
            "awslogs-region"        = var.aws_region
            "awslogs-stream-prefix" = "xray"
          }
        }
      },
    ]
  }

  # Files bundled into the S3 template zip that CodePipeline reads.
  taskdef_template = {
    for name, svc in local.services : name => replace(jsonencode({
      family                  = "${var.project_name}-${name}"
      networkMode             = "awsvpc"
      requiresCompatibilities = ["FARGATE"]
      cpu                     = tostring(var.container_cpu)
      memory                  = tostring(var.container_memory)
      executionRoleArn        = aws_iam_role.task_execution.arn
      taskRoleArn             = aws_iam_role.task.arn
      runtimePlatform         = { operatingSystemFamily = "LINUX", cpuArchitecture = "X86_64" }
      containerDefinitions    = local.container_defs[name]
    }), "__IMAGE__", "<IMAGE1_NAME>")
  }

  # AppSpec is JSON, which is valid YAML, so it can live in appspec.yaml.
  appspec = {
    for name, svc in local.services : name => replace(jsonencode({
      version = "0.0"
      Resources = [{
        TargetService = {
          Type = "AWS::ECS::Service"
          Properties = {
            TaskDefinition = "__TASKDEF__"
            LoadBalancerInfo = {
              ContainerName = name
              ContainerPort = local.container_port
            }
          }
        }
      }]
    }), "__TASKDEF__", "<TASK_DEFINITION>")
  }
}
