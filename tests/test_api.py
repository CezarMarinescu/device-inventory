import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_list_devices_has_starter_devices(client):
    response = client.get("/devices")
    assert response.status_code == 200
    names = [d["name"] for d in response.json()]
    assert "LAP-001" in names


def test_create_and_get_device(client):
    new_device = {"name": "TEST-001", "os": "Ubuntu 24.04", "compliant": False}
    created = client.post("/devices", json=new_device)
    assert created.status_code == 201
    device_id = created.json()["id"]

    fetched = client.get(f"/devices/{device_id}")
    assert fetched.status_code == 200
    assert fetched.json()["name"] == "TEST-001"


def test_unknown_device_returns_404(client):
    response = client.get("/devices/999999")
    assert response.status_code == 404


def test_invalid_id_returns_422(client):
    response = client.get("/devices/abc")
    assert response.status_code == 422


def test_create_device_with_missing_field_returns_422(client):
    response = client.post("/devices", json={"name": "BROKEN"})
    assert response.status_code == 422