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