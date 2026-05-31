"""FastAPI entry point — kakeibo API."""

from __future__ import annotations

from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .database import create_db_and_tables
from .routers import (
    crypto_config,
    csv_import,
    encrypted_tx,
    receipts,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize database tables on application startup."""
    create_db_and_tables()
    yield


app = FastAPI(
    title="kakeibo API",
    version="0.4.0",
    lifespan=lifespan,
)


app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",
        "http://127.0.0.1:5173",
    ],
    allow_credentials=False,
    allow_methods=[
        "GET",
        "POST",
        "PATCH",
        "DELETE",
        "OPTIONS",
    ],
    allow_headers=["*"],
)


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


# API routers must be registered before StaticFiles.
app.include_router(receipts.router)
app.include_router(csv_import.router)

# E2E encryption routers.
app.include_router(crypto_config.router)
app.include_router(encrypted_tx.router)


# Static frontend files must be mounted last.
# If mounted before API routers, /api/* can be intercepted by StaticFiles,
# causing GET 404 and POST 405.
_STATIC_DIR = Path(__file__).resolve().parent / "static"

if _STATIC_DIR.exists():
    app.mount(
        "/",
        StaticFiles(directory=str(_STATIC_DIR), html=True),
        name="static",
    )
