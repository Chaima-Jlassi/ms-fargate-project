# One private repository per microservice. Images are scanned on every push.
resource "aws_ecr_repository" "svc" {
  for_each = local.services

  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = "MUTABLE" # the moving `latest` tag triggers the pipeline
  force_delete         = true      # lets `terraform destroy` remove repos that still hold images

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "svc" {
  for_each   = local.services
  repository = aws_ecr_repository.svc[each.key].name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 10 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
