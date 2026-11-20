# One pipeline per service:
#   Source  : the image GitHub Actions just pushed to ECR  +  the taskdef/appspec bundle in S3
#   Deploy  : CodeDeploy blue/green to ECS
resource "aws_codepipeline" "svc" {
  for_each = local.services

  name     = "${var.project_name}-${each.key}"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Image"
      category         = "Source"
      owner            = "AWS"
      provider         = "ECR"
      version          = "1"
      output_artifacts = ["image"]

      configuration = {
        RepositoryName = aws_ecr_repository.svc[each.key].name
        ImageTag       = var.image_tag
      }
    }

    action {
      name             = "Template"
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      output_artifacts = ["template"]

      configuration = {
        S3Bucket             = aws_s3_bucket.artifacts.bucket
        S3ObjectKey          = "templates/${each.key}/bundle.zip"
        PollForSourceChanges = "false"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "BlueGreen"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      version         = "1"
      input_artifacts = ["image", "template"]

      configuration = {
        ApplicationName                = aws_codedeploy_app.ecs.name
        DeploymentGroupName            = aws_codedeploy_deployment_group.svc[each.key].deployment_group_name
        TaskDefinitionTemplateArtifact = "template"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "template"
        AppSpecTemplatePath            = "appspec.yaml"
        Image1ArtifactName             = "image"
        Image1ContainerName            = "IMAGE1_NAME"
      }
    }
  }

  depends_on = [aws_iam_role_policy.codepipeline, aws_s3_object.bundle]
}

# Start the pipeline when a new image is pushed with the release tag.
resource "aws_cloudwatch_event_rule" "ecr_push" {
  for_each = local.services

  name        = "${var.project_name}-${each.key}-ecr-push"
  description = "Start the ${each.key} pipeline when its image is pushed"

  event_pattern = jsonencode({
    source        = ["aws.ecr"]
    "detail-type" = ["ECR Image Action"]
    detail = {
      "action-type"     = ["PUSH"]
      result            = ["SUCCESS"]
      "repository-name" = [aws_ecr_repository.svc[each.key].name]
      "image-tag"       = [var.image_tag]
    }
  })
}

resource "aws_cloudwatch_event_target" "start_pipeline" {
  for_each = local.services

  rule     = aws_cloudwatch_event_rule.ecr_push[each.key].name
  arn      = aws_codepipeline.svc[each.key].arn
  role_arn = aws_iam_role.events.arn
}
