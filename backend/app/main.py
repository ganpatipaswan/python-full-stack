from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(
    title="FastAPI React Demo API",
    version="1.0.0",
    description="Database-free FastAPI backend for a React frontend.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",
        "http://127.0.0.1:5173",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/health")
def health():
    return {"status": "ok", "message": "FastAPI is reachable"}


@app.get("/api/message")
def message():
    return {
        "message": "Hello from FastAPI!",
        "source": "backend",
        "database": "not connected",
    }


@app.get("/api/items")
def items():
    # Temporary in-memory data; no database connection.
    return [
        {"id": 1, "name": "React.js", "type": "frontend"},
        {"id": 2, "name": "FastAPI", "type": "backend"},
        {"id": 3, "name": "GitHub Actions", "type": "ci-cd"},
    ]


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
