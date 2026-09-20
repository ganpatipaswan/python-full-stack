#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || true)}"
STACK_NAME="${ECS_STACK:-fastapi-react-production}"
PROJECT_NAME="${ECS_PROJECT:-fastapi-react}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD 2>/dev/null || date +%s)}"

if [[ -z "$REGION" ]]; then
  echo "AWS_REGION is not set and no AWS CLI region is configured." >&2
  exit 1
fi

command -v aws >/dev/null || { echo "AWS CLI is required." >&2; exit 1; }
command -v docker >/dev/null || { echo "Docker CLI is required." >&2; exit 1; }

echo "Checking AWS credentials..."
aws sts get-caller-identity >/dev/null

echo "Checking Docker..."
docker info >/dev/null

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE_URI="${REGISTRY}/${PROJECT_NAME}:${IMAGE_TAG}"

aws ecr describe-repositories \
  --repository-names "$PROJECT_NAME" \
  --region "$REGION" >/dev/null 2>&1 || \
  aws ecr create-repository \
    --repository-name "$PROJECT_NAME" \
    --image-scanning-configuration scanOnPush=true \
    --region "$REGION" >/dev/null

echo "Logging into ECR..."
aws ecr get-login-password --region "$REGION" | docker login \
  --username AWS \
  --password-stdin "$REGISTRY"

echo "Building $IMAGE_URI..."
docker build --platform linux/amd64 --provenance=false --tag "$IMAGE_URI" .
docker push "$IMAGE_URI"

echo "Deploying CloudFormation stack $STACK_NAME..."
aws cloudformation deploy \
  --stack-name "$STACK_NAME" \
  --template-file deploy/ecs/cloudformation.yml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    ImageUri="$IMAGE_URI" \
    ProjectName="$PROJECT_NAME" \
  --region "$REGION" \
  --no-fail-on-empty-changeset

URL="$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`ApplicationUrl`].OutputValue' \
  --output text)"

echo
echo "Deployment complete. Application URL: $URL"
