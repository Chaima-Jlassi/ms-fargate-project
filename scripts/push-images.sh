#!/usr/bin/env bash
# Build the three images and push them to ECR by hand.
# Use this for the very first deployment, or whenever GitHub Actions is not set up yet.
#
#   ./scripts/push-images.sh
#
# Optional environment variables: AWS_REGION (eu-north-1), PROJECT_NAME (ms-fargate), IMAGE_TAG (latest)
set -euo pipefail
cd "$(dirname "$0")/.."

REGION="${AWS_REGION:-eu-north-1}"
PROJECT="${PROJECT_NAME:-ms-fargate}"
TAG="${IMAGE_TAG:-latest}"

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

echo "Logging in to $REGISTRY"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

for svc in auth orders notifications; do
  IMAGE="$REGISTRY/$PROJECT/$svc:$TAG"
  echo "Building and pushing $IMAGE"
  # Fargate tasks are defined as linux/amd64, so build for that even on ARM laptops.
  docker build --platform linux/amd64 -t "$IMAGE" "services/$svc"
  docker push "$IMAGE"
done

echo "Done. Pushing the '$TAG' tag starts the CodePipeline blue/green deployment for each service."
