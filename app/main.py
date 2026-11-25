import os
from contextlib import asynccontextmanager

import psycopg
from psycopg.rows import dict_row
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

DATABASE_URL = os.environ["DATABASE_URL"]

SEED_DEVICES = [
    ("LAP-001", "Windows 11", True),
    ("LAP-002", "Windows 11", False),
    ("LAP-003", "Windows 11", True),
]


class DeviceIn(BaseModel):
    name: str
    os: str
    compliant: bool


def get_connection():
    return psycopg.connect(DATABASE_URL, row_factory=dict_row)


@asynccontextmanager
async def lifespan(app: FastAPI):
    with get_connection() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS devices (
                id        SERIAL PRIMARY KEY,
                name      TEXT    NOT NULL,
                os        TEXT    NOT NULL,
                compliant BOOLEAN NOT NULL
            )
        """)
        count = conn.execute("SELECT COUNT(*) AS n FROM devices").fetchone()["n"]
        if count == 0:
            with conn.cursor() as cur:
                cur.executemany(
                    "INSERT INTO devices (name, os, compliant) VALUES (%s, %s, %s)",
                    SEED_DEVICES,
                )
    yield


app = FastAPI(title="Device Inventory API", lifespan=lifespan)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/devices")
def list_devices():
    with get_connection() as conn:
        return conn.execute(
            "SELECT id, name, os, compliant FROM devices ORDER BY id"
        ).fetchall()


@app.get("/devices/{device_id}")
def get_device(device_id: int):
    with get_connection() as conn:
        device = conn.execute(
            "SELECT id, name, os, compliant FROM devices WHERE id = %s",
            (device_id,),
        ).fetchone()
    if device is None:
        raise HTTPException(status_code=404, detail="Device not found")
    return device


@app.post("/devices", status_code=201)
def create_device(device: DeviceIn):
    with get_connection() as conn:
        return conn.execute(
            "INSERT INTO devices (name, os, compliant) VALUES (%s, %s, %s) "
            "RETURNING id, name, os, compliant",
            (device.name, device.os, device.compliant),
        ).fetchone()