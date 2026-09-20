# FastAPI + React Full-Stack Demo

A database-free full-stack starter project focused on API integration and GitHub Actions CI/CD.

## Stack
- Backend: Python 3.12, FastAPI, Uvicorn, Pytest
- Frontend: React 18, Vite, JavaScript
- CI/CD: GitHub Actions
- Database: None

## Project structure

```text
fastapi-react-fullstack/
├── backend/
│   ├── app/
│   │   ├── __init__.py
│   │   └── main.py
│   ├── tests/
│   │   └── test_main.py
│   ├── requirements.txt
│   └── requirements-dev.txt
├── frontend/
│   ├── src/
│   │   ├── App.jsx
│   │   ├── App.css
│   │   └── main.jsx
│   ├── index.html
│   ├── package.json
│   └── vite.config.js
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── cd.yml
├── .gitignore
└── README.md
```

## Run backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate       # macOS/Linux
# .venv\Scripts\activate      # Windows

pip install -r requirements.txt
pip install -r requirements-dev.txt
uvicorn app.main:app --reload --port 8000
```

API: http://localhost:8000  
Swagger: http://localhost:8000/docs

## Run frontend

Open another terminal:

```bash
cd frontend
npm install
npm run dev
```

Frontend: http://localhost:5173

The Vite development server proxies `/api` requests to FastAPI.

## Test backend

```bash
cd backend
pytest
```

## GitHub Actions

- `ci.yml`: runs backend tests and frontend build on pushes and pull requests.
- `cd.yml`: demonstrates a deployment workflow using GitHub Pages for the frontend after CI. Set the repository Pages source to GitHub Actions if you use this workflow.

For a real backend deployment, replace the placeholder deployment job with your cloud/container deployment step.


cd backend
source .venv/bin/activate
python --version

## Deploy with Docker and ECS

For the complete deployment history, AWS architecture, commands, troubleshooting,
verification, and cleanup instructions, see [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

The production image contains both applications. FastAPI serves the React build
and handles `/api` requests, so the deployment does not require Nginx. ECS
Fargate runs the container behind an internet-facing Application Load Balancer.

Build and run locally:

```bash
docker build -t fastapi-react .
docker run --rm -p 8000:8000 fastapi-react
```

Open http://localhost:8000. The API health check is available at
http://localhost:8000/api/health.

### GitHub Actions deployment setup

The `CD - AWS ECS Fargate` workflow creates the AWS infrastructure, deploys the
image, and prints the public ALB URL. Configure these repository or `production`
environment variables:

- `AWS_ROLE_ARN`: GitHub OIDC role allowed to push to ECR and deploy the stack
- `AWS_REGION`: AWS region, for example `ap-south-1`

The AWS role needs ECR push access, `iam:PassRole`, and permission to manage the
CloudFormation resources in `deploy/ecs/cloudformation.yml`. The stack creates
the VPC, public subnets, internet gateway, ECS cluster, Fargate service,
security groups, logs, and ALB. The deployment script also creates the ECR
repository before pushing the image. After a push to `main`, the workflow
prints `Application URL` in its output.

For a local deployment after authenticating the AWS CLI and starting Docker:

```bash
aws sts get-caller-identity
open -a Docker
./deploy/ecs/deploy.sh
```