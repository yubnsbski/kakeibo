"""FastAPI entry point.

Single uvicorn process serves the API at /api/* and (in production) the
built frontend dist/ at /. CORS is enabled only for the Vite dev server
during development (localhost:5173).

Run: `uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000`
"""
from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .database import create_db_and_tables


@asynccontextmanager
async def lifespan(app: FastAPI):
    create_db_and_tables()
    yield


app = FastAPI(
    title="kakeibo API",
    version="0.1.0",
    description="Family-shared household budget app backend",
    lifespan=lifespan,
)

# Dev only: Vite dev server on localhost:5173. Production serves frontend
# from the same origin (no CORS needed).
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",
        "http://127.0.0.1:5173",
    ],
    allow_credentials=False,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
