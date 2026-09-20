# Deployment Documentation

This document records the deployment journey for the FastAPI + React application and the final repeatable AWS deployment procedure.

## 1. Application Architecture

The application is deployed as one Docker image:

```text
Internet
   |
   v
AWS Application Load Balancer :80
   |
   v
ECS Fargate task :8000
   |
   +-- FastAPI API routes: /api/health, /api/message, /api/items
   +-- React production files served by FastAPI
```

Nginx is not used. FastAPI serves the built React files from `frontend-dist`, and the Application Load Balancer provides the public HTTP endpoint.

## 2. Repository Deployment Files

- `Dockerfile`: multi-stage image build. Node builds React; Python runs FastAPI.
- `.dockerignore`: excludes Git, virtual environments, dependencies, caches, and logs.
- `backend/app/main.py`: serves API routes and the React static build.
- `deploy/ecs/cloudformation.yml`: creates the AWS network and ECS infrastructure.
- `deploy/ecs/deploy.sh`: validates credentials and Docker, creates ECR, builds and pushes the image, deploys CloudFormation, and prints the URL.
- `.github/workflows/ci.yml`: runs backend and frontend validation.
- `.github/workflows/cd.yml`: runs the deployment script from GitHub Actions.

## 3. AWS Resources Created Automatically

The CloudFormation stack is named `fastapi-react-production` and creates:

- VPC `10.0.0.0/16`
- Two public subnets in separate availability zones
- Internet gateway and public routing
- ECR repository `fastapi-react`
- CloudWatch log group `/ecs/fastapi-react`
- ECS cluster `fastapi-react-cluster`
- ECS Fargate task definition and service `fastapi-react-service`
- ECS task execution IAM role
- Application Load Balancer
- ALB target group and HTTP listener on port 80
- Security group for public ALB traffic
- Security group allowing port 8000 only from the ALB

The ECS task uses 0.25 vCPU and 512 MB memory with one desired task.

## 4. Local Prerequisites

Install and configure:

- AWS CLI
- Docker Desktop
- Git
- An AWS account with permissions to create the resources listed above

Configure a region and credentials, then verify authentication:

```bash
aws configure
aws sts get-caller-identity
```

The deployment used region `ap-south-1`.

Start Docker Desktop on macOS if needed:

```bash
open -a Docker
```

## 5. Deploy from the Local Machine

From the repository root:

```bash
chmod +x deploy/ecs/deploy.sh
./deploy/ecs/deploy.sh
```

The script performs these steps:

1. Reads `AWS_REGION`, or the AWS CLI default region.
2. Checks AWS credentials with `aws sts get-caller-identity`.
3. Checks Docker with `docker info`.
4. Gets the AWS account ID.
5. Creates the ECR repository if it does not exist.
6. Logs Docker into ECR.
7. Builds the image for `linux/amd64`, which is required by the ECS Fargate runtime.
8. Pushes the image to ECR.
9. Creates or updates the CloudFormation stack.
10. Prints the ALB application URL.

Optional variables:

```bash
AWS_REGION=ap-south-1 \
ECS_STACK=fastapi-react-production \
ECS_PROJECT=fastapi-react \
IMAGE_TAG=$(git rev-parse --short HEAD) \
./deploy/ecs/deploy.sh
```

## 6. Current Deployment

Deployment status: `CREATE_COMPLETE`

Region: `ap-south-1`

Public application URL:

<http://fastap-LoadB-NbR0kHgMfE8r-1306154633.ap-south-1.elb.amazonaws.com>

Health endpoint:

<http://fastap-LoadB-NbR0kHgMfE8r-1306154633.ap-south-1.elb.amazonaws.com/api/health>

Expected health response:

```json
{"status":"ok","message":"FastAPI is reachable"}
```

The deployed homepage returned HTTP 200 and the health endpoint returned the expected JSON response.

## 7. Verify the Deployment

Get the URL from CloudFormation:

```bash
aws cloudformation describe-stacks \
  --stack-name fastapi-react-production \
  --region ap-south-1 \
  --query 'Stacks[0].Outputs' \
  --output table
```

Check the application:

```bash
APP_URL="http://fastap-LoadB-NbR0kHgMfE8r-1306154633.ap-south-1.elb.amazonaws.com"
curl -i "$APP_URL/"
curl "$APP_URL/api/health"
curl "$APP_URL/api/message"
curl "$APP_URL/api/items"
```

Check ECS:

```bash
aws ecs describe-services \
  --cluster fastapi-react-cluster \
  --services fastapi-react-service \
  --region ap-south-1 \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'
```

View application logs:

```bash
aws logs tail /ecs/fastapi-react \
  --follow \
  --region ap-south-1
```

## 8. GitHub Actions Deployment

The CD workflow runs on pushes to `main` or manual workflow dispatch. Configure these GitHub repository or `production` environment variables:

- `AWS_ROLE_ARN`: GitHub OIDC role ARN
- `AWS_REGION`: for example `ap-south-1`

The AWS role must be allowed to:

- Authenticate with GitHub OIDC
- Push images to ECR
- Create and update the CloudFormation resources
- Pass the ECS task execution role with `iam:PassRole`
- Read CloudFormation outputs

The workflow builds the image with Docker, pushes it to ECR, deploys the stack, and prints `Application URL` in the workflow summary.

## 9. Troubleshooting History

### Python command not found

macOS had `python3` but no `python` command. The backend virtual environment was created with:

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
```

### Vite permission denied

`frontend/node_modules` had been created as `root`, so Vite could not write `.vite`. The dependency directory was recreated as the normal user. npm was also configured to use a user-owned cache:

```bash
npm config set cache /Users/garv/.npm-user-cache
```

### Ruff executable-file errors

Python files had mode `100755` without shebangs. Their permissions were normalized to `644`.

### Pytest could not import `app`

`backend/pytest.ini` was added:

```ini
[pytest]
pythonpath = .
```

### npm lint command missing

The frontend initially had no `lint` script. ESLint was added with:

```json
"lint": "eslint src"
```

### CloudFormation YAML parsing error

The ECS health-check command used a fragile inline YAML sequence. It was changed to a block-style command under `HealthCheck.Command`.

### ECS image platform error

The first image was built on Apple Silicon as ARM64, but Fargate expected `linux/amd64`. The deployment script now uses:

```bash
docker build --platform linux/amd64 --provenance=false ...
```

After rebuilding and pushing the image, ECS started successfully and the ALB became healthy.

## 10. Cleanup and Cost Control

The ECS service, ALB, NAT-free public network, ECR repository, CloudWatch logs, and related resources can incur AWS charges. To delete the CloudFormation-managed infrastructure:

```bash
aws cloudformation delete-stack \
  --stack-name fastapi-react-production \
  --region ap-south-1
```

Wait for deletion:

```bash
aws cloudformation wait stack-delete-complete \
  --stack-name fastapi-react-production \
  --region ap-south-1
```

The ECR repository is created by `deploy.sh`, not CloudFormation, so delete it separately if it is no longer needed:

```bash
aws ecr delete-repository \
  --repository-name fastapi-react \
  --force \
  --region ap-south-1
```

Do not run cleanup commands unless the deployment is no longer needed.
