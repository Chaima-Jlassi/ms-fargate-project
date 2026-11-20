variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Prefix used in resource names and tags (max 12 characters: target group names have a 32 character limit)"
  type        = string
  default     = "ms-fargate"

  validation {
    condition     = length(var.project_name) <= 12 && can(regex("^[a-z][a-z0-9-]*$", var.project_name))
    error_message = "project_name must be at most 12 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "github_repo" {
  description = "GitHub repository allowed to push images, as owner/name (for example jane/ecs-fargate-microservices)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to span"
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "true = one shared NAT Gateway (cheaper, demo). false = one per AZ (highly available, production)."
  type        = bool
  default     = true
}

variable "desired_count" {
  description = "Initial number of tasks per service. Use 2 or more for high availability."
  type        = number
  default     = 1
}

variable "container_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "container_memory" {
  description = "Fargate task memory in MiB"
  type        = number
  default     = 512
}

variable "image_tag" {
  description = "Image tag that GitHub Actions pushes and the pipelines deploy"
  type        = string
  default     = "latest"
}

variable "namespace_name" {
  description = "Cloud Map private DNS namespace. Services are reachable as <service>.<namespace>"
  type        = string
  default     = "local"
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.micro"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention"
  type        = number
  default     = 7
}

variable "deployment_config_name" {
  description = "CodeDeploy traffic shifting. Canary 10% for 5 minutes shows the blue/green shift; use CodeDeployDefault.ECSAllAtOnce for fast demos."
  type        = string
  default     = "CodeDeployDefault.ECSCanary10Percent5Minutes"
}

variable "xray_daemon_image" {
  description = "X-Ray daemon sidecar image"
  type        = string
  default     = "public.ecr.aws/xray/aws-xray-daemon:latest"
}

variable "alert_email" {
  description = "Email address for alarm notifications (leave empty to skip). AWS sends a confirmation link."
  type        = string
  default     = ""
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub OIDC identity provider. Set to false if your account already has one (only one per account is allowed)."
  type        = bool
  default     = true
}
