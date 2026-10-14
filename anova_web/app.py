"""FastAPI web app for controlling an Anova Precision Cooker."""

from __future__ import annotations

import asyncio
import contextlib
import os
from pathlib import Path
from typing import Literal, Optional

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from .cooker import AnovaPrecisionCooker, BleakTransport, CookerError, MockCooker, SousVide

STATIC_DIR = Path(__file__).parent / "static"


class TemperatureRequest(BaseModel):
    value: float
    unit: Literal["c", "f"] = "c"


class TimerRequest(BaseModel):
    minutes: int = Field(ge=1)


def create_cooker_from_env() -> SousVide:
    if os.environ.get("ANOVA_MOCK", "").lower() in ("1", "true", "yes"):
        return MockCooker()
    return AnovaPrecisionCooker(BleakTransport(address=os.environ.get("ANOVA_ADDRESS") or None))


def create_app(cooker: Optional[SousVide] = None) -> FastAPI:
    @contextlib.asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.cooker = cooker or create_cooker_from_env()
        stop_event = asyncio.Event()
        task = asyncio.create_task(app.state.cooker.run(stop_event))
        try:
            yield
        finally:
            stop_event.set()
            await task

    app = FastAPI(title="Anova Sous Vide", lifespan=lifespan)

    def get_cooker() -> SousVide:
        return app.state.cooker

    async def call(coro):
        try:
            await coro
        except ValueError as e:
            raise HTTPException(status_code=422, detail=str(e))
        except CookerError as e:
            raise HTTPException(status_code=503, detail=str(e))
        return get_cooker().state.to_dict()

    @app.get("/api/state")
    async def state():
        return get_cooker().state.to_dict()

    @app.post("/api/start")
    async def start():
        return await call(get_cooker().start())

    @app.post("/api/stop")
    async def stop():
        return await call(get_cooker().stop())

    @app.post("/api/temperature")
    async def set_temperature(req: TemperatureRequest):
        return await call(get_cooker().set_desired_temperature(req.value, req.unit))

    @app.post("/api/timer")
    async def start_timer(req: TimerRequest):
        return await call(get_cooker().start_timer(req.minutes))

    @app.delete("/api/timer")
    async def stop_timer():
        return await call(get_cooker().stop_timer())

    @app.get("/")
    async def index():
        return FileResponse(STATIC_DIR / "index.html")

    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
    return app
