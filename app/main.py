from fastapi import FastAPI, HTTPException

app = FastAPI(title="Device Inventory API")

devices = [
    {"id": 1, "name": "LAP-001", "os": "Windows 11", "compliant": True},
    {"id": 2, "name": "LAP-002", "os": "Windows 11", "compliant": False},
    {"id": 3, "name": "LAP-003", "os": "Windows 11", "compliant": True},
]

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/devices")
def list_devices():
    return devices

@app.get("/devices/{device_id}")
def get_device(device_id: int):
    for d in devices:
        if d["id"] == device_id:
            return d
    raise HTTPException(status_code=404, detail="Device not found")