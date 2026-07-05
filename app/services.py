"""
业务服务层 — 将 CLI 逻辑抽取为纯函数，供 routes 和 CLI 共用
"""
from __future__ import annotations

from collections.abc import Callable
import json
import os
import time

from comfyui import ComfyUIClient
from runninghub import (
    download_files,
    get_node_info,
    poll_until_complete,
    print_node_errors,
    submit_task,
    upload_file,
)

# ── 异常定义 ──────────────────────────────────────────


class HoodError(Exception):
    """所有业务异常的基类"""
    def __init__(self, message: str, detail: str | None = None):
        self.message = message
        self.detail = detail
        super().__init__(message)


class ConfigError(HoodError):
    """配置缺失或错误"""


class APIError(HoodError):
    """RunningHub API 调用失败"""


class ComfyUIError(HoodError):
    """本地 ComfyUI 操作失败"""


# ── 配置加载 ──────────────────────────────────────────


def _load_env_key(key: str) -> str | None:
    """从 .env 文件或环境变量读取指定 key 的值"""
    # 优先从环境变量读取
    env_val = os.environ.get(key)
    if env_val:
        return env_val.strip().strip("\"'")

    # 回退到 .env 文件
    script_dir = os.path.dirname(os.path.abspath(__file__))
    dotenv_path = os.path.join(os.path.dirname(script_dir), ".env")  # 项目根目录
    if os.path.isfile(dotenv_path):
        with open(dotenv_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    k, _, v = line.partition("=")
                    if k.strip() == key:
                        return v.strip().strip("\"'")
    return None


def load_api_key() -> str:
    """加载 RunningHub API 密钥，失败抛 ConfigError"""
    key = _load_env_key("RUNNINGHUB_API_KEY")
    if not key:
        raise ConfigError(
            "未找到 API 密钥",
            "在项目根目录创建 .env 文件，写入 RUNNINGHUB_API_KEY=你的密钥",
        )
    return key


def load_comfyui_config() -> tuple[str, str | None]:
    """加载 ComfyUI 配置：(server_address, input_dir)"""
    server = _load_env_key("COMFYUI_SERVER") or "127.0.0.1:8188"
    input_dir = _load_env_key("COMFYUI_INPUT_DIR") or None
    return server, input_dir


# ── 格式化工具 ─────────────────────────────────────────


def _format_duration(seconds: float) -> str:
    if seconds < 60:
        return f"{seconds:.1f}s"
    minutes = int(seconds // 60)
    secs = seconds % 60
    return f"{minutes}min{secs:.0f}s"


# ── 业务服务 1: 获取节点信息 ──────────────────────────


def get_app_node_info(webapp_id: str, api_key: str | None = None) -> list:
    """获取 RunningHub 应用的节点信息列表

    返回 node_info_list，成功时 length>0；失败抛 APIError
    """
    api_key = api_key or load_api_key()
    node_list = get_node_info(webapp_id, api_key)
    if not node_list:
        raise APIError(
            "未获取到节点信息",
            "请检查 webappId 是否正确",
        )
    return node_list


# ── 业务服务 2: 完整流水线 ──────────────────────────


def run_pipeline(
    webapp_id: str,
    modifications: list[dict],
    api_key: str | None = None,
    comfy_server: str | None = None,
    comfy_input_dir: str | None = None,
    output_dir: str | None = None,
    task_callback: Callable | None = None,
) -> dict:
    """
    完整流水线：
      1. 获取节点信息 → 修改参数
      2. 提交 RunningHub → 轮询完成
      3. 下载 latent 到 ComfyUI input/
      4. 本地 ComfyUI VAE 解码 → 保存图片

    参数
    - webapp_id: RunningHub AI 应用 ID
    - modifications: [{"nodeId","fieldName","fieldValue","filePath"}, ...]
    - api_key: API 密钥（不传则从环境加载）
    - comfy_server: ComfyUI 地址（不传则从环境加载）
    - comfy_input_dir: ComfyUI input 目录（不传则从环境加载）
    - output_dir: 最终图片输出目录（默认 <项目根>/output）
    - task_callback: 状态回调 function(status, message, progress)

    返回 dict {
        "status": "done" | "failed",
        "message": ...,
        "output_files": [...],
        "duration": 秒,
    }
    """
    t_total = time.time()
    api_key = api_key or load_api_key()
    if comfy_server is None or comfy_input_dir is None:
        _s, _d = load_comfyui_config()
        comfy_server = comfy_server or _s
        comfy_input_dir = comfy_input_dir or _d
    if output_dir is None:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        output_dir = os.path.join(os.path.dirname(script_dir), "output")

    # ── 1. 获取节点信息并修改 ──
    _callback(task_callback, "running", "正在获取节点信息...")
    t1 = time.time()
    node_info_list = get_node_info(webapp_id, api_key)
    if not node_info_list:
        raise APIError("未获取到节点信息", "请检查 webappId 是否正确")

    uploaded_files = []
    for mod in modifications:
        node_id = mod["nodeId"]
        field_name = mod["fieldName"]
        target_node = next(
            (n for n in node_info_list if n["nodeId"] == node_id and n["fieldName"] == field_name),
            None,
        )
        if not target_node:
            print(f"[跳过] 未找到节点 nodeId={node_id}, fieldName={field_name}")
            continue

        if target_node.get("fieldType") in ("IMAGE", "AUDIO", "VIDEO"):
            file_path = mod.get("filePath")
            if not file_path:
                print(f"[跳过] 节点 {node_id} 类型为 {target_node['fieldType']}，但未提供 filePath")
                continue
            print(f"[上传] {file_path}")
            upload_result = upload_file(api_key, file_path)
            if upload_result and upload_result.get("msg") == "success":
                uploaded_file_name = upload_result.get("data", {}).get("fileName")
                if uploaded_file_name:
                    target_node["fieldValue"] = uploaded_file_name
                    uploaded_files.append(uploaded_file_name)
                    print(f"[OK] 已更新 fieldValue: {uploaded_file_name}")
            else:
                print(f"[上传异常] {upload_result}")
        else:
            target_node["fieldValue"] = mod.get("fieldValue", "")
            print(f"[修改] {node_id}.{field_name} = {mod.get('fieldValue', '')}")

    print(f"[耗时] 节点信息 & 修改: {_format_duration(time.time() - t1)}")

    # ── 2. 提交任务到 RunningHub ──
    _callback(task_callback, "running", "提交任务到 RunningHub...")
    t2 = time.time()
    submit_result = submit_task(webapp_id, node_info_list, api_key)
    if submit_result.get("code") != 0:
        raise APIError("提交任务失败", json.dumps(submit_result, ensure_ascii=False))

    task_id = submit_result["data"]["taskId"]
    print(f"[任务ID] {task_id}")
    print_node_errors(submit_result)

    # ── 3. 轮询等待完成 ──
    _callback(task_callback, "running", f"任务 {task_id} 执行中...")
    output_data = poll_until_complete(task_id, api_key)
    if not output_data:
        raise APIError("任务未成功完成", f"task_id={task_id}")

    print(f"[耗时] 云端推理: {_format_duration(time.time() - t2)}")

    # ── 4. 下载 latent ──
    if not comfy_input_dir:
        raise ConfigError("未配置 COMFYUI_INPUT_DIR，无法自动解码")

    _callback(task_callback, "running", "下载 latent 文件...")
    t3 = time.time()
    latent_files = download_files(output_data, comfy_input_dir)
    if not latent_files:
        print("[!] 没有下载到 latent 文件，跳过本地解码")
        return {
            "status": "done",
            "message": "任务完成，但没有 latent 文件需要解码",
            "output_files": [],
            "duration": time.time() - t_total,
        }
    print(f"[耗时] 下载 latent: {_format_duration(time.time() - t3)}")

    # ── 5. 本地 ComfyUI 解码 ──
    _callback(task_callback, "running", "正在进行 VAE 解码...")
    t4 = time.time()
    client = ComfyUIClient(server_address=comfy_server, input_dir=comfy_input_dir)
    decode_failed = False
    all_output_files = []

    for latent_path in latent_files:
        print(f"\n{'='*60}")
        print(f"[解码] {latent_path}")
        try:
            result = client.decode_latent(latent_path, output_dir=output_dir)
            # 收集输出文件
            for node_id, images in result.items():
                for img_data in images:
                    all_output_files.append(f"{output_dir}/node_{node_id}")
        except Exception as e:
            print(f"[Error] 解码失败: {e}")
            decode_failed = True

    print(f"[耗时] VAE 解码: {_format_duration(time.time() - t4)}")

    duration = time.time() - t_total
    if decode_failed:
        raise ComfyUIError("部分 latent 解码失败", "最终图片可能不完整")

    _callback(task_callback, "done", "流水线完成")
    return {
        "status": "done",
        "message": "流水线全部完成",
        "output_files": all_output_files,
        "duration": duration,
    }


# ── 业务服务 3: 独立 VAE 解码 ────────────────────────


def decode_latent(
    latent_file: str,
    output_dir: str | None = None,
    comfy_server: str | None = None,
    comfy_input_dir: str | None = None,
    task_callback: Callable | None = None,
) -> dict:
    """
    独立的本地 VAE 解码

    返回 dict {
        "status": "done" | "failed",
        "message": ...,
        "output_files": [...],
        "duration": 秒,
    }
    """
    t0 = time.time()
    if comfy_server is None or comfy_input_dir is None:
        _s, _d = load_comfyui_config()
        comfy_server = comfy_server or _s
        comfy_input_dir = comfy_input_dir or _d
    if output_dir is None:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        output_dir = os.path.join(os.path.dirname(script_dir), "output")

    if not comfy_input_dir:
        raise ConfigError("未配置 COMFYUI_INPUT_DIR", "请在 .env 中添加")

    _callback(task_callback, "running", f"正在解码 {latent_file}...")
    client = ComfyUIClient(server_address=comfy_server, input_dir=comfy_input_dir)
    result = client.decode_latent(latent_file, output_dir=output_dir)

    # 收集输出文件路径
    output_files = []
    for node_id, images in result.items():
        for img_data in images:
            output_files.append(f"{output_dir}/node_{node_id}")

    _callback(task_callback, "done", "解码完成")
    return {
        "status": "done",
        "message": f"解码完成，共 {sum(len(v) for v in result.values())} 张图片",
        "output_files": output_files,
        "duration": time.time() - t0,
    }


# ── 回调辅助 ──────────────────────────────────────────


def _callback(cb: Callable | None, status: str, message: str, progress: float | None = None):
    """安全调用回调函数"""
    if cb:
        try:
            cb(status, message, progress)
        except Exception:
            pass
