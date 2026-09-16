from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_message():
    response = client.get("/api/message")
    assert response.status_code == 200
    assert response.json()["database"] == "not connected"


def test_items():
    response = client.get("/api/items")
    assert response.status_code == 200
    assert len(response.json()) == 3
