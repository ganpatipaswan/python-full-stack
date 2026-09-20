# FastAPI + React AWS ECS Fargate CI/CD Deployment Documentation

## 1. Overview

This document records the complete deployment process for the FastAPI + React full-stack application using:

- GitHub
- GitHub Actions
- GitHub OIDC
- AWS IAM
- Amazon ECR
- Docker
- Amazon ECS Fargate
- Application Load Balancer (ALB)
- AWS CloudFormation
- Amazon CloudWatch Logs

### Final architecture

```text
Developer
   |
   | git push origin main
   v
GitHub Repository
   |
   v
GitHub Actions
   |
   | GitHub OIDC
   v
AWS IAM Role
   |
   +--------------------+
   |                    |
   v                    v
Amazon ECR         CloudFormation
   |                    |
   | Docker image       v
   |               VPC + Subnets
   |                    |
   |                    v
   |              Application LB
   |                    |
   |                    v
   +------------> ECS Fargate
                        |
                        v
                  FastAPI + React
```

Runtime traffic:

```text
Internet
   |
   v
Application Load Balancer :80
   |
   v
ECS Fargate Task :8000
   |
   v
FastAPI + React
```

Nginx is not used.

---

# 2. Project Information

| Item | Value |
|---|---|
| GitHub Repository | `ganpatipaswan/python-full-stack` |
| AWS Account | `797882812918` |
| AWS Region | `ap-south-1` |
| Project | `fastapi-react` |
| CloudFormation Stack | `fastapi-react-production` |
| ECR Repository | `fastapi-react` |
| ECS Cluster | `fastapi-react-cluster` |
| ECS Service | `fastapi-react-service` |
| IAM Role | `GitHubActions-ECS-Deploy-Role` |
| GitHub Environment | `production` |
| Deployment Branch | `main` |
| Application Port | `8000` |
| ALB Port | `80` |
| Health Check | `/api/health` |

---

# 3. Repository Structure

```text
python-full-stack/
│
├── backend/
├── frontend/
├── deploy/
│   └── ecs/
│       ├── cloudformation.yml
│       └── deploy.sh
│
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── cd.yml
│
├── Dockerfile
├── .dockerignore
├── docker-compose.yml
└── README.md
```

Important deployment files:

| File | Purpose |
|---|---|
| `Dockerfile` | Builds the application container |
| `.dockerignore` | Excludes unnecessary files from Docker image |
| `deploy/ecs/deploy.sh` | Builds, pushes, and deploys image |
| `deploy/ecs/cloudformation.yml` | Creates AWS infrastructure |
| `.github/workflows/cd.yml` | Runs automated deployment |
| `.github/workflows/ci.yml` | Runs validation/tests |

---

# 4. Docker and FastAPI Requirements

The application runs on:

```text
0.0.0.0:8000
```

Example:

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

The health endpoint is:

```text
/api/health
```

It must return HTTP `200`.

Listening only on `127.0.0.1:8000` can cause ECS/ALB connectivity problems.

---

# 5. GitHub Actions CD Workflow

The production deployment is triggered by pushes to `main` and can also be started manually.

```yaml
name: CD - AWS ECS Fargate

on:
  push:
    branches:
      - main
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

concurrency:
  group: production
  cancel-in-progress: false

env:
  AWS_REGION: ap-south-1
  ECS_STACK: fastapi-react-production
  ECS_PROJECT: fastapi-react

jobs:
  deploy:
    name: Build and deploy to ECS
    runs-on: ubuntu-latest

    environment:
      name: production

    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v6
        with:
          role-to-assume: arn:aws:iam::797882812918:role/GitHubActions-ECS-Deploy-Role
          aws-region: ap-south-1
          audience: sts.amazonaws.com

      - name: Verify AWS identity
        run: aws sts get-caller-identity

      - name: Deploy
        run: |
          chmod +x deploy/ecs/deploy.sh
          ./deploy/ecs/deploy.sh
```

A temporary OIDC debugging step was used during troubleshooting. It should be removed after authentication is confirmed.

---

# 6. Why GitHub OIDC Was Used

The workflow needs AWS permissions.

Instead of storing long-lived AWS access keys in GitHub, GitHub OIDC is used:

```text
GitHub Actions
      |
      | OIDC token
      v
AWS STS
      |
      v
IAM Role
      |
      v
Temporary AWS credentials
```

Benefits:

- No long-lived AWS access key in GitHub
- Temporary credentials
- Repository/environment restriction
- Better security for CI/CD

---

# 7. GitHub OIDC Configuration

OIDC provider:

```text
arn:aws:iam::797882812918:oidc-provider/token.actions.githubusercontent.com
```

Provider URL:

```text
https://token.actions.githubusercontent.com
```

Audience:

```text
sts.amazonaws.com
```

The final trust relationship restricts access to the repository and production environment.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::797882812918:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:ganpatipaswan@32195368/python-full-stack@1373553868:environment:production"
        }
      }
    }
  ]
}
```

---

# 8. Issue 1 — GitHub OIDC Authentication Failed

## Error

The workflow initially failed with:

```text
Not authorized to perform sts:AssumeRoleWithWebIdentity
```

## Why it happened

GitHub Actions was trying to assume:

```text
GitHubActions-ECS-Deploy-Role
```

but AWS IAM did not accept the GitHub OIDC token.

The IAM trust policy did not match the exact GitHub identity claims.

The important claims were:

```text
aud = sts.amazonaws.com
```

and the repository/environment-specific `sub`.

The required repository identity was:

```text
repo:ganpatipaswan@32195368/python-full-stack@1373553868:environment:production
```

## Fix

The IAM trust policy was updated to match:

```json
"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
```

and:

```json
"token.actions.githubusercontent.com:sub":
"repo:ganpatipaswan@32195368/python-full-stack@1373553868:environment:production"
```

## Result

Authentication succeeded:

```text
GitHub Actions
       |
       v
OIDC
       |
       v
AWS STS
       |
       v
GitHubActions-ECS-Deploy-Role
```

---

# 9. Important OIDC Lesson

Separate these two IAM concepts.

### Trust policy

Answers:

```text
Who is allowed to assume this role?
```

### Permissions policy

Answers:

```text
What can the role do after it is assumed?
```

For an `AssumeRoleWithWebIdentity` error, inspect the trust relationship first.

---

# 10. AWS Identity Verification

The workflow runs:

```bash
aws sts get-caller-identity
```

This confirms the AWS identity being used.

Expected identity type:

```text
arn:aws:sts::797882812918:assumed-role/GitHubActions-ECS-Deploy-Role/...
```

This is a useful first diagnostic step in AWS CI/CD troubleshooting.

---

# 11. ECR Process

Amazon ECR stores the Docker image.

```text
Source Code
    |
    v
Docker Build
    |
    v
Docker Image
    |
    v
Amazon ECR
    |
    v
ECS Task Definition
    |
    v
ECS Fargate
```

Registry:

```text
797882812918.dkr.ecr.ap-south-1.amazonaws.com
```

Image format:

```text
797882812918.dkr.ecr.ap-south-1.amazonaws.com/fastapi-react:<tag>
```

---

# 12. Issue 2 — `IMAGE_URI: unbound variable`

## Error

After AWS authentication and ECR login succeeded, deployment failed with:

```text
./deploy/ecs/deploy.sh: line 40: IMAGE_URI: unbound variable
```

## Why it happened

The script used:

```bash
set -u
```

`set -u` causes Bash to fail if an unset variable is referenced.

`IMAGE_URI` was referenced before it had been assigned.

Conceptually:

```bash
echo "$IMAGE_URI"
```

was executed before:

```bash
IMAGE_URI="..."
```

## Fix

Initialize the variables before using them:

```bash
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

IMAGE_URI="${REGISTRY}/${PROJECT_NAME}:${IMAGE_TAG}"
```

Then use:

```bash
"${IMAGE_URI}"
```

The deployment script keeps:

```bash
set -euo pipefail
```

which is useful for CI/CD, provided all required variables are initialized.

---

# 13. Docker Architecture

The deployment build uses:

```bash
docker build   --platform linux/amd64   --provenance=false   -t "${IMAGE_URI}" .
```

This helps avoid CPU architecture incompatibility between the development machine and the ECS runtime.

---

# 14. ECR Login and Push

ECR authentication:

```bash
aws ecr get-login-password --region "${REGION}"   | docker login       --username AWS       --password-stdin "${REGISTRY}"
```

Push:

```bash
docker push "${IMAGE_URI}"
```

---

# 15. CloudFormation Deployment

Infrastructure is defined in:

```text
deploy/ecs/cloudformation.yml
```

The deployment process passes the new Docker image URI to CloudFormation.

Conceptually:

```bash
aws cloudformation deploy   --stack-name "${STACK_NAME}"   --template-file deploy/ecs/cloudformation.yml   --parameter-overrides     ImageUri="${IMAGE_URI}"     ProjectName="${PROJECT_NAME}"
```

CloudFormation manages:

- VPC
- Subnets
- Internet Gateway
- Route table
- Security groups
- ALB
- Target group
- ECS cluster
- ECS task definition
- ECS service
- CloudWatch log group

---

# 16. AWS Infrastructure

## Network

```text
VPC
├── Public Subnet A
├── Public Subnet B
├── Internet Gateway
└── Public Route Table
```

## Security

```text
ALB Security Group
└── TCP 80 from 0.0.0.0/0

Task Security Group
└── TCP 8000 only from ALB Security Group
```

## Compute

```text
ECS Cluster
└── ECS Service
    └── Fargate Task
        └── Application Container
```

## Load Balancing

```text
ALB
└── Listener :80
    └── Target Group :8000
```

## Logging

```text
CloudWatch
└── /ecs/fastapi-react
```

---

# 17. Why Two Public Subnets Were Used

The ALB uses two public subnets in different Availability Zones.

This provides the base for a more resilient ALB configuration.

Current service capacity is:

```yaml
DesiredCount: 1
```

This can later be increased, for example:

```yaml
DesiredCount: 2
```

---

# 18. Security Group Design

The intended traffic flow is:

```text
Internet
   |
   | TCP 80
   v
ALB
   |
   | TCP 8000
   v
ECS Task
```

The task security group does not need to allow port 8000 from the entire internet.

This is preferable to:

```text
0.0.0.0/0 -> ECS :8000
```

---

# 19. ECS and ALB Health Checks

The container health endpoint is:

```text
/api/health
```

The ECS health check executes a request against:

```text
127.0.0.1:8000/api/health
```

The ALB target group checks:

```text
ECS Task:8000/api/health
```

Expected result:

```text
HTTP 200
```

Two health layers therefore exist:

```text
ECS Container Health
        |
        v
127.0.0.1:8000/api/health

ALB Target Health
        |
        v
ECS Task:8000/api/health
```

---

# 20. Common Health Check Failure Causes

If the task or target is unhealthy, check:

### FastAPI is not running

Check CloudWatch logs.

### Wrong host binding

Incorrect:

```text
127.0.0.1:8000
```

Correct:

```text
0.0.0.0:8000
```

### Missing health endpoint

Make sure:

```text
/api/health
```

exists.

### Health endpoint returns an error

It should return:

```text
HTTP 200
```

### Application starts slowly

The ECS service currently has a health grace period and the container has a health-check start period. Increase these values if the application genuinely needs more startup time.

---

# 21. Why Nginx Is Not Used

The final architecture intentionally does not use Nginx.

```text
Internet
   |
   v
AWS ALB
   |
   v
FastAPI/React Container
```

The ALB already provides:

- Load balancing
- Health checks
- Public endpoint
- Future HTTPS termination
- Future multi-task routing

---

# 22. CloudWatch Logs

Application logs are sent to:

```text
/ecs/fastapi-react
```

Retention:

```text
14 days
```

The ECS task uses the AWS CloudWatch Logs driver.

This allows application startup/runtime errors to be investigated without logging into a server.

---

# 23. Deployment URL

CloudFormation creates an output:

```text
ApplicationUrl
```

It is generated from:

```text
http://${LoadBalancer.DNSName}
```

The public endpoint therefore looks like:

```text
http://<load-balancer-dns-name>
```

The ALB endpoint is preferred over an individual ECS task public IP because the task IP can change.

---

# 24. Complete End-to-End Deployment

```text
1. Developer changes code
        |
        v
2. git add .
        |
        v
3. git commit
        |
        v
4. git push origin main
        |
        v
5. GitHub Actions starts
        |
        v
6. GitHub OIDC token generated
        |
        v
7. AWS STS validates token
        |
        v
8. GitHubActions-ECS-Deploy-Role assumed
        |
        v
9. AWS identity verified
        |
        v
10. Docker image built
        |
        v
11. ECR login
        |
        v
12. Docker image pushed
        |
        v
13. CloudFormation deployed
        |
        v
14. ECS task definition updated
        |
        v
15. ECS starts new task
        |
        v
16. ECS health check
        |
        v
17. ALB health check
        |
        v
18. ALB sends traffic to ECS
        |
        v
19. Application available
```

---

# 25. Useful Git Commands

```bash
git status
```

```bash
git add .
```

```bash
git commit -m "update application"
```

```bash
git push origin main
```

A push to `main` automatically starts the CD workflow.

The workflow also supports:

```yaml
workflow_dispatch:
```

for manual execution.

---

# 26. Useful AWS Troubleshooting Commands

## Verify AWS identity

```bash
aws sts get-caller-identity
```

## Check ECR repositories

```bash
aws ecr describe-repositories   --region ap-south-1
```

## Check CloudFormation

```bash
aws cloudformation describe-stacks   --stack-name fastapi-react-production   --region ap-south-1
```

## Get application URL

```bash
aws cloudformation describe-stacks   --stack-name fastapi-react-production   --query "Stacks[0].Outputs[?OutputKey=='ApplicationUrl'].OutputValue"   --output text   --region ap-south-1
```

## Check ECS service

```bash
aws ecs describe-services   --cluster fastapi-react-cluster   --services fastapi-react-service   --region ap-south-1
```

## List ECS tasks

```bash
aws ecs list-tasks   --cluster fastapi-react-cluster   --service-name fastapi-react-service   --region ap-south-1
```

## Check CloudWatch streams

```bash
aws logs describe-log-streams   --log-group-name /ecs/fastapi-react   --region ap-south-1
```

---

# 27. Completed Items

The following deployment components are completed:

- GitHub repository
- GitHub Actions
- GitHub OIDC
- AWS IAM role
- OIDC trust policy
- GitHub production environment
- AWS authentication
- ECR
- Docker build
- Docker push
- CloudFormation deployment
- VPC
- Public subnets
- Internet Gateway
- ALB
- ECS Fargate cluster
- ECS service
- ECS task definition
- Security groups
- ECS health check
- ALB health check
- CloudWatch logging
- Public application URL
- Full application deployment

---

# 28. Temporary OIDC Debugging Step

A temporary GitHub OIDC debug step was used while diagnosing the authentication failure.

Now that OIDC authentication is working, remove that step.

Keep:

```yaml
permissions:
  id-token: write
  contents: read
```

Do not remove the `id-token: write` permission because GitHub needs it to request the OIDC token.

---

# 29. Production Hardening Still Pending

The core deployment is complete. The following are recommended next steps.

## 1. AWS Secrets Manager

Sensitive values should not be stored in:

```text
.env
GitHub workflow
Dockerfile
source code
plain configuration
```

Recommended flow:

```text
AWS Secrets Manager
        |
        v
ECS Task Definition
        |
        v
FastAPI Application
```

Examples:

```text
DATABASE_URL
JWT_SECRET
OPENAI_API_KEY
OTHER_API_KEYS
```

---

# 30. ECS Execution Role vs Task Role

These roles have different responsibilities.

### ECS Execution Role

Used by ECS for infrastructure operations such as:

- Pulling ECR images
- Writing CloudWatch logs

### ECS Task Role

Used by the application itself for AWS API access.

For example:

```text
FastAPI
   |
   v
AWS Secrets Manager
```

A dedicated Task Role should be added when Secrets Manager is integrated.

---

# 31. HTTPS / ACM

Current endpoint:

```text
HTTP :80
```

Recommended production architecture:

```text
Internet
   |
   | HTTPS :443
   v
ALB
   |
   | HTTP :8000
   v
ECS
```

AWS Certificate Manager (ACM) can provide the TLS certificate.

Recommended final flow:

```text
HTTP :80
   |
   | redirect
   v
HTTPS :443
   |
   v
ALB
   |
   v
ECS :8000
```

---

# 32. Custom Domain

The AWS ALB DNS name is appropriate for testing.

For production, a custom domain can be configured:

```text
Route 53
    |
    v
Custom Domain
    |
    v
ALB
```

Example:

```text
https://app.example.com
```

---

# 33. IAM Least Privilege

The GitHub deployment role should eventually be reviewed so it has only the permissions required for:

- ECR
- CloudFormation
- ECS deployment
- Required read operations

Avoid broad:

```text
AdministratorAccess
```

for the final production configuration.

---

# 34. Database Architecture

If the FastAPI application uses a database, a production database should normally be external to the application container.

Recommended:

```text
ECS Fargate
     |
     v
RDS PostgreSQL/MySQL
```

Database credentials should be stored in:

```text
AWS Secrets Manager
```

---

# 35. Rollback Strategy

A production deployment should support rollback.

Prefer immutable image tags such as Git commit SHA:

```text
fastapi-react:8f32c1a
```

instead of relying only on:

```text
latest
```

Example:

```text
Commit A
   |
   v
image: abc123

Commit B
   |
   v
image: def456
```

If B fails, version A can be redeployed.

---

# 36. Recommended Future CI/CD Pipeline

```text
Pull Request
    |
    v
CI
    |
    +--> Lint
    |
    +--> Unit Tests
    |
    +--> Build
    |
    v
Merge to main
    |
    v
Docker Build
    |
    v
Security Scan
    |
    v
ECR
    |
    v
ECS Deployment
    |
    v
Health Check
    |
    v
Smoke Test
    |
    v
Deployment Success
```

For production, an approval step can be inserted before deployment.

---

# 37. Monitoring

Recommended CloudWatch alarms:

- ECS task count
- ECS CPU utilization
- ECS memory utilization
- ALB 5xx responses
- Target health
- Request count
- Application errors

Architecture:

```text
CloudWatch
    |
    +--> Metrics
    |
    +--> Logs
    |
    +--> Alarms
             |
             v
        Notifications
```

---

# 38. Cost Considerations

The deployment uses resources that can incur AWS charges:

- ECS Fargate
- Application Load Balancer
- ECR
- CloudWatch Logs
- Networking resources

Review AWS costs after testing.

Do not manually delete individual CloudFormation-managed resources unless you understand the dependency chain.

If the entire environment is no longer required, use the CloudFormation stack lifecycle rather than deleting random resources manually.

---

# 39. Final Issue Summary

| Issue | Root Cause | Resolution |
|---|---|---|
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | GitHub OIDC token did not match IAM trust relationship | Corrected OIDC provider/trust policy and exact `sub` claim |
| AWS credentials unavailable | OIDC role assumption failed | Fixed IAM trust policy |
| `IMAGE_URI: unbound variable` | Variable referenced before assignment while `set -u` was enabled | Initialize `IMAGE_URI` before use |
| Possible ECS/ALB unhealthy target | App must listen on `0.0.0.0:8000` and expose `/api/health` | Configure FastAPI/container and health endpoint correctly |
| Architecture mismatch risk | Developer and ECS image architecture can differ | Build with `--platform linux/amd64` |
| Unstable task endpoint | Individual ECS task IP can change | Use ALB as public endpoint |
| Secret exposure risk | Secrets should not be embedded in source/image | Use AWS Secrets Manager |

---

# 40. Final Production Checklist

```text
[✓] GitHub repository
[✓] GitHub Actions
[✓] GitHub OIDC
[✓] AWS IAM role
[✓] IAM trust policy
[✓] GitHub production environment
[✓] ECR
[✓] Docker build
[✓] Docker push
[✓] CloudFormation
[✓] VPC
[✓] Public subnets
[✓] Internet Gateway
[✓] ALB
[✓] ECS Fargate
[✓] ECS service
[✓] Security groups
[✓] ECS health check
[✓] ALB health check
[✓] CloudWatch logs
[✓] Application deployment

[ ] Remove temporary OIDC debug step
[ ] Verify automatic deployment with another push
[ ] AWS Secrets Manager
[ ] ECS Task Role
[ ] HTTPS / ACM
[ ] Custom domain
[ ] IAM least-privilege review
[ ] Monitoring/alarms
[ ] Immutable image tags
[ ] Rollback procedure
[ ] Cost optimization
```

---

# 41. Key Lessons Learned

### Lesson 1 — OIDC

For:

```text
AssumeRoleWithWebIdentity
```

errors, check the IAM trust policy and GitHub OIDC claims before changing deployment permissions.

### Lesson 2 — Bash strict mode

With:

```bash
set -u
```

every variable must be initialized before it is referenced.

### Lesson 3 — ECS networking

FastAPI must listen on:

```text
0.0.0.0
```

when accessed through ECS networking/ALB.

### Lesson 4 — Health checks

Use a lightweight endpoint:

```text
/api/health
```

and make sure it returns HTTP 200.

### Lesson 5 — Role separation

Use separate roles for:

```text
GitHub Actions
      |
      +--> Deployment permissions

ECS Execution Role
      |
      +--> ECR + CloudWatch

ECS Task Role
      |
      +--> Application AWS permissions
```

### Lesson 6 — Infrastructure as Code

CloudFormation makes AWS infrastructure reproducible and version-controlled.

### Lesson 7 — Secrets

Secrets belong in a secret-management system, not source code or Docker images.

### Lesson 8 — Stable endpoint

Use an ALB instead of depending on an individual ECS task public IP.

---

# 42. Final Status

## Core CI/CD Deployment

**COMPLETED**

```text
GitHub
   |
   v
GitHub Actions
   |
   v
GitHub OIDC
   |
   v
AWS IAM
   |
   v
ECR
   |
   v
CloudFormation
   |
   v
ECS Fargate
   |
   v
Application Load Balancer
   |
   v
FastAPI + React
```

The two main deployment issues encountered were:

1. **GitHub OIDC trust-policy mismatch**
   - Prevented AWS role assumption.
   - Fixed by matching the exact OIDC audience and repository/environment `sub`.

2. **`IMAGE_URI` unbound variable**
   - Caused by referencing the variable before initialization with Bash `set -u`.
   - Fixed by calculating `ACCOUNT_ID`, `REGISTRY`, and `IMAGE_URI` before using them.

The deployment subsequently completed successfully.

The next production-hardening priorities are:

1. Remove temporary OIDC debug code.
2. Verify another automatic deployment from `main`.
3. Verify ECS and ALB health.
4. Integrate AWS Secrets Manager.
5. Add an ECS Task Role.
6. Add HTTPS with ACM.
7. Add custom domain if required.
8. Review IAM permissions.
9. Add monitoring and alarms.
10. Implement immutable image tags and rollback.
11. Review AWS costs.
