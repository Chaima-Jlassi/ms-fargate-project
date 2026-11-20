output "app_url" {
  description = "Public URL of the application (HTTP)"
  value       = "http://${aws_lb.main.dns_name}"
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "ecr_repository_urls" {
  description = "Push the three images here"
  value       = { for name, repo in aws_ecr_repository.svc : name => repo.repository_url }
}

output "github_actions_role_arn" {
  description = "Set this as the AWS_ROLE_ARN variable in your GitHub repository"
  value       = aws_iam_role.github_actions.arn
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "pipeline_names" {
  value = { for name, p in aws_codepipeline.svc : name => p.name }
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "jwt_secret_arn" {
  description = "ARN of the JWT secret (the value is never output)"
  value       = aws_secretsmanager_secret.jwt.arn
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}
