# Holds two things: CodePipeline's working artifacts, and the per-service
# "template bundle" (taskdef.json + appspec.yaml) that Terraform generates.
resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.project_name}-artifacts-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  force_destroy = true # lets `terraform destroy` empty the bucket
}

# CodePipeline's S3 source action requires versioning.
resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# taskdef.json holds everything about the container except the image, which
# CodePipeline fills in (<IMAGE1_NAME>) from the image that was just pushed.
# appspec.yaml tells CodeDeploy which container receives the load balancer traffic.
data "archive_file" "bundle" {
  for_each = local.services

  type        = "zip"
  output_path = "${path.module}/.build/${each.key}-bundle.zip"

  source {
    content  = local.taskdef_template[each.key]
    filename = "taskdef.json"
  }

  source {
    content  = local.appspec[each.key]
    filename = "appspec.yaml"
  }
}

resource "aws_s3_object" "bundle" {
  for_each = local.services

  bucket = aws_s3_bucket.artifacts.id
  key    = "templates/${each.key}/bundle.zip"
  source = data.archive_file.bundle[each.key].output_path
  etag   = data.archive_file.bundle[each.key].output_md5

  depends_on = [aws_s3_bucket_versioning.artifacts]
}
