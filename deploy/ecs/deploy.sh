#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || true)}"

STACK_NAME="${ECS_STACK:-fastapi-react-production}"

PROJECT_NAME="${ECS_PROJECT:-fastapi-react}"

IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD 2>/dev/null || date +%s)}"


# ============================================================
# Validate AWS region
# ============================================================

if [[ -z "$REGION" ]]; then
  echo "ERROR: AWS_REGION is not set and no AWS CLI region is configured."
  exit 1
fi


# ============================================================
# Validate required tools
# ============================================================

command -v aws >/dev/null || {
  echo "ERROR: AWS CLI is required."
  exit 1
}

command -v docker >/dev/null || {
  echo "ERROR: Docker CLI is required."
  exit 1
}


# ============================================================
# Deployment information
# ============================================================

echo
echo "=========================================="
echo "FastAPI + React ECS Deployment"
echo "=========================================="
echo "AWS Region   : $REGION"
echo "Stack Name   : $STACK_NAME"
echo "Project Name : $PROJECT_NAME"
echo "Image Tag    : $IMAGE_TAG"
echo "=========================================="
echo


# ============================================================
# Check AWS credentials
# ============================================================

echo "Checking AWS credentials..."

aws sts get-caller-identity

echo


# ============================================================
# Get AWS Account ID
# ============================================================

ACCOUNT_ID="$(
  aws sts get-caller-identity \
    --query Account \
    --output text
)"

echo "AWS Account ID: $ACCOUNT_ID"


# ============================================================
# Create ECR registry URL
# ============================================================

REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "ECR Registry: $REGISTRY"


# ============================================================
# Create Docker image URI
# ============================================================

IMAGE_URI="${REGISTRY}/${PROJECT_NAME}:${IMAGE_TAG}"

echo "Docker Image URI:"
echo "$IMAGE_URI"

echo


# ============================================================
# Check Docker
# ============================================================

echo "Checking Docker..."

docker info >/dev/null

echo "Docker is ready."

echo


# ============================================================
# Check/Create ECR repository
# ============================================================

echo "Checking ECR repository..."

if aws ecr describe-repositories \
  --repository-names "$PROJECT_NAME" \
  --region "$REGION" \
  >/dev/null 2>&1
then

  echo "ECR repository already exists:"
  echo "$PROJECT_NAME"

else

  echo "ECR repository does not exist."
  echo "Creating ECR repository..."

  aws ecr create-repository \
    --repository-name "$PROJECT_NAME" \
    --image-scanning-configuration scanOnPush=true \
    --region "$REGION"

  echo "ECR repository created."

fi

echo


# ============================================================
# Login to ECR
# ============================================================

echo "Logging into ECR..."

aws ecr get-login-password \
  --region "$REGION" \
  | docker login \
      --username AWS \
      --password-stdin "$REGISTRY"

echo "ECR login successful."

echo


# ============================================================
# Build Docker image
# ============================================================

echo "Building Docker image..."

echo "Image:"
echo "$IMAGE_URI"

docker build \
  --platform linux/amd64 \
  --provenance=false \
  --tag "$IMAGE_URI" \
  .

echo

echo "Docker image build completed."


# ============================================================
# Push Docker image to ECR
# ============================================================

echo
echo "Pushing Docker image to ECR..."

docker push "$IMAGE_URI"

echo

echo "Docker image push completed."


# ============================================================
# Deploy CloudFormation
# ============================================================

echo
echo "=========================================="
echo "Deploying CloudFormation"
echo "=========================================="

echo "Stack:"
echo "$STACK_NAME"

echo "Template:"
echo "deploy/ecs/cloudformation.yml"

echo "Image:"
echo "$IMAGE_URI"

echo


aws cloudformation deploy \
  --stack-name "$STACK_NAME" \
  --template-file deploy/ecs/cloudformation.yml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    ImageUri="$IMAGE_URI" \
    ProjectName="$PROJECT_NAME" \
  --region "$REGION" \
  --no-fail-on-empty-changeset


echo

echo "CloudFormation deployment completed."


# ============================================================
# Get Application URL
# ============================================================

echo
echo "Getting application URL..."


URL="$(
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApplicationUrl`].OutputValue' \
    --output text
)"


# ============================================================
# Validate Application URL
# ============================================================

if [[ -z "$URL" || "$URL" == "None" ]]; then

  echo
  echo "ERROR: ApplicationUrl was not found."
  echo
  echo "CloudFormation stack outputs:"
  
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs'

  exit 1

fi


# ============================================================
# Deployment completed
# ============================================================

echo
echo
echo "=========================================="
echo "DEPLOYMENT SUCCESSFUL"
echo "=========================================="
echo
echo "AWS Account:"
echo "$ACCOUNT_ID"
echo
echo "AWS Region:"
echo "$REGION"
echo
echo "ECR Image:"
echo "$IMAGE_URI"
echo
echo "CloudFormation Stack:"
echo "$STACK_NAME"
echo
echo "Application URL:"
echo "$URL"
echo
echo "=========================================="