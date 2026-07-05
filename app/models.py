"""
Pydantic 模型定义 — 请求 / 响应 / 任务状态
"""
from __future__ import annotations

from enum import Enum
from pydantic import BaseModel, Field


# ── 请求模型 ────────────────────────────────────────────


class Modification(BaseModel):
    """节点修改项"""
    node_id: str = Field(..., description="节点 ID")
    field_name: str = Field(..., description="字段名称")
    field_value: str | None = Field(None, description="文本/下拉等字段的值")
    file_path: str | None = Field(None, description="IMAGE/AUDIO/VIDEO 类型节点的文件路径")


class RunRequest(BaseModel):
    """提交完整流水线的请求体"""
    webapp_id: str = Field(..., description="RunningHub AI 应用的 webappId")
    modifications: list[Modification] = Field(default_factory=list, description="要修改的节点列表")


class InfoRequest(BaseModel):
    """查看节点信息的请求体"""
    webapp_id: str = Field(..., description="RunningHub AI 应用的 webappId")


class DecodeRequest(BaseModel):
    """独立 VAE 解码的请求体"""
    latent_file: str = Field(..., description=".latent 文件路径")
    output_dir: str | None = Field(None, description="输出目录（默认 output/）")


# ── 响应模型 ────────────────────────────────────────────


class TaskStatus(str, Enum):
    pending = "pending"
    running = "running"
    done = "done"
    failed = "failed"


class TaskInfo(BaseModel):
    """任务基本信息"""
    task_id: str
    status: TaskStatus
    created_at: float
    updated_at: float
    message: str = ""
    output_files: list[str] = Field(default_factory=list, description="输出文件路径列表")


class HealthResponse(BaseModel):
    status: str = "ok"
    version: str = "0.1.0"


class ErrorResponse(BaseModel):
    error: str
    detail: str | None = None
