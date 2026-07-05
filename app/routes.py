"""
API 路由定义 — 完整的 REST 端点实现
"""
from __future__ import annotations

import threading
import time
import uuid
from fastapi import APIRouter, HTTPException
from app.models import (
    RunRequest,
    InfoRequest,
    DecodeRequest,
    TaskInfo,
    TaskStatus,
    HealthResponse,
)
from app.services import (
    get_app_node_info,
    run_pipeline,
    decode_latent,
    HoodError,
    ConfigError,
    APIError,
    ComfyUIError,
)

router = APIRouter(prefix="/api", tags=["api"])

# ── 任务存储（内存） ──────────────────────────────────
# 重启后丢失，适合轻量场景；生产可用 Redis 替代

_tasks: dict[str, TaskInfo] = {}
_tasks_lock = threading.Lock()


def _register_task(task_id: str, info: TaskInfo):
    with _tasks_lock:
        _tasks[task_id] = info


def _update_task(task_id: str, status: TaskStatus, message: str = "", output_files: list[str] | None = None):
    with _tasks_lock:
        if task_id in _tasks:
            t = _tasks[task_id]
            t.status = status
            t.message = message
            t.updated_at = time.time()
            if output_files is not None:
                t.output_files = output_files


def _task_callback(task_id: str):
    """创建回调函数，供后台线程更新任务状态"""
    def cb(status: str, message: str, progress: float | None = None):
        s = TaskStatus(status) if status in ("pending", "running", "done", "failed") else TaskStatus.running
        _update_task(task_id, s, message)
    return cb


# ── 健康检查 ──────────────────────────────────────────


@router.get("/health", response_model=HealthResponse)
async def health():
    """健康检查端点"""
    return HealthResponse()


# ── 节点信息 ──────────────────────────────────────────


@router.post("/info")
async def info(req: InfoRequest):
    """获取 RunningHub 应用的节点信息

    返回 RunningHub 返回的原始 nodeInfoList
    """
    try:
        nodes = get_app_node_info(req.webapp_id)
        return {"code": 0, "data": nodes}
    except ConfigError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except APIError as e:
        raise HTTPException(status_code=502, detail=str(e))
    except HoodError as e:
        raise HTTPException(status_code=500, detail=str(e))


# ── 完整流水线 ────────────────────────────────────────


@router.post("/run", response_model=TaskInfo, status_code=202)
async def run(req: RunRequest):
    """提交完整流水线：修改节点 → 提交 RunningHub → 下载 latent → VAE 解码

    异步任务，返回 task_id，客户端通过 GET /api/tasks/{task_id} 轮询状态。
    """
    task_id = str(uuid.uuid4())
    task_info = TaskInfo(
        task_id=task_id,
        status=TaskStatus.pending,
        created_at=time.time(),
        updated_at=time.time(),
        message="任务已创建，等待执行",
    )
    _register_task(task_id, task_info)

    # 后台执行
    thread = threading.Thread(
        target=_run_background,
        args=(task_id, req),
        daemon=True,
    )
    thread.start()

    return task_info


def _run_background(task_id: str, req: RunRequest):
    """后台执行完整流水线"""
    try:
        modifications = [
            {
                "nodeId": m.node_id,
                "fieldName": m.field_name,
                "fieldValue": m.field_value,
                "filePath": m.file_path,
            }
            for m in req.modifications
        ]
        result = run_pipeline(
            webapp_id=req.webapp_id,
            modifications=modifications,
            task_callback=_task_callback(task_id),
        )
        _update_task(
            task_id,
            TaskStatus.done,
            result.get("message", "完成"),
            result.get("output_files", []),
        )
    except (ConfigError, APIError, ComfyUIError) as e:
        _update_task(task_id, TaskStatus.failed, f"{e.message}: {e.detail}" if e.detail else e.message)
    except Exception as e:
        _update_task(task_id, TaskStatus.failed, f"未知错误: {e}")


# ── 独立 VAE 解码 ─────────────────────────────────────


@router.post("/decode", response_model=TaskInfo, status_code=202)
async def decode(req: DecodeRequest):
    """独立的本地 VAE 解码

    异步任务，返回 task_id，客户端通过 GET /api/tasks/{task_id} 轮询状态。
    """
    task_id = str(uuid.uuid4())
    task_info = TaskInfo(
        task_id=task_id,
        status=TaskStatus.pending,
        created_at=time.time(),
        updated_at=time.time(),
        message="任务已创建，等待执行",
    )
    _register_task(task_id, task_info)

    thread = threading.Thread(
        target=_decode_background,
        args=(task_id, req),
        daemon=True,
    )
    thread.start()

    return task_info


def _decode_background(task_id: str, req: DecodeRequest):
    """后台执行独立解码"""
    try:
        result = decode_latent(
            latent_file=req.latent_file,
            output_dir=req.output_dir,
            task_callback=_task_callback(task_id),
        )
        _update_task(
            task_id,
            TaskStatus.done,
            result.get("message", "完成"),
            result.get("output_files", []),
        )
    except (ConfigError, APIError, ComfyUIError) as e:
        _update_task(task_id, TaskStatus.failed, f"{e.message}: {e.detail}" if e.detail else e.message)
    except Exception as e:
        _update_task(task_id, TaskStatus.failed, f"未知错误: {e}")


# ── 任务状态查询 ──────────────────────────────────────


@router.get("/tasks/{task_id}", response_model=TaskInfo)
async def get_task(task_id: str):
    """查询异步任务的状态和结果

    可能的状态：pending → running → done / failed
    """
    with _tasks_lock:
        task = _tasks.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")
    return task
