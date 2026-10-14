from fastapi.testclient import TestClient

from anova_web.app import create_app
from anova_web.cooker import MockCooker


def make_client():
    return TestClient(create_app(MockCooker()))


def test_state_and_controls():
    with make_client() as client:
        assert client.get("/").status_code == 200
        state = client.get("/api/state").json()
        assert state["mock"] and state["desired_temp_f"] is not None

        assert client.post("/api/start").json()["is_running"] is True
        assert client.post("/api/stop").json()["is_running"] is False

        state = client.post("/api/temperature", json={"value": 140, "unit": "f"}).json()
        assert state["desired_temp_c"] == 60.0

        state = client.post("/api/timer", json={"minutes": 45}).json()
        assert state["timer_running"] and state["timer_minutes"] == 45
        assert client.delete("/api/timer").json()["timer_running"] is False


def test_validation_errors():
    with make_client() as client:
        assert client.post("/api/temperature", json={"value": 500, "unit": "c"}).status_code == 422
        assert client.post("/api/temperature", json={"value": 50, "unit": "k"}).status_code == 422
        assert client.post("/api/timer", json={"minutes": 0}).status_code == 422
