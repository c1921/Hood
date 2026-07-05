"""
Hood FastAPI 后端入口
"""
from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routes import router

app = FastAPI(
    title="Hood API",
    description="AI 工作流编排后端 — 将 RunningHub 云端推理与本地 ComfyUI VAE 解码串联",
    version="0.1.0",
)

# CORS — 允许局域网 / Flutter 客户端访问
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
