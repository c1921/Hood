"""
Hood — AI 工作流编排工具

将 RunningHub 云端任务与本地 ComfyUI 解码串联为一条完整流水线。

子命令:
  info <webappId>      查看 RunningHub 应用的节点信息
  run  [task.json]     完整流水线：提交云端 → 下载 latent → 本地 ComfyUI 解码
  decode <latent_file>  独立的本地解码（将 latent 送入 ComfyUI 解码为图片）
"""
import argparse
import json
import os
import sys
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


# ── 配置加载 ──────────────────────────────────────────────


def _load_env_key(key: str) -> str | None:
    """从 .env 文件或环境变量读取指定 key 的值"""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    dotenv_path = os.path.join(script_dir, ".env")
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
    return os.environ.get(key)


def _load_api_key() -> str:
    """加载 RunningHub API 密钥"""
    key = _load_env_key("RUNNINGHUB_API_KEY")
    if not key:
        print("[Error] 未找到 API 密钥。")
        print("   在项目根目录创建 .env 文件，写入：")
        print("         RUNNINGHUB_API_KEY=你的密钥")
        sys.exit(1)
    return key.strip()


def _load_comfyui_config() -> tuple[str, str | None]:
    """加载 ComfyUI 配置：(server_address, input_dir)"""
    server = _load_env_key("COMFYUI_SERVER") or "127.0.0.1:8188"
    input_dir = _load_env_key("COMFYUI_INPUT_DIR") or None
    return server, input_dir


def _format_duration(seconds: float) -> str:
    """将秒数格式化为可读的耗时字符串"""
    if seconds < 60:
        return f"{seconds:.1f}s"
    minutes = int(seconds // 60)
    secs = seconds % 60
    return f"{minutes}min{secs:.0f}s"


# ── 子命令实现 ────────────────────────────────────────────


def cmd_info(webapp_id: str) -> None:
    """查看应用节点信息"""
    t0 = time.time()
    api_key = _load_api_key()
    print(f"[信息] 正在获取 webappId={webapp_id} 的节点信息...")
    nodes = get_node_info(webapp_id, api_key)
    if not nodes:
        print("[!] 未获取到节点信息，请检查 webappId 是否正确。")
    print(f"[耗时] 总耗时 {_format_duration(time.time() - t0)}")


def cmd_run(task_json_path: str) -> None:
    """
    完整流水线：
      1. 读取 task.json → 修改节点
      2. 提交 RunningHub → 轮询完成
      3. 下载 latent 到 ComfyUI input/
      4. 本地 ComfyUI VAE 解码 → 保存图片
    """
    t_total = time.time()
    api_key = _load_api_key()

    # 读取配置
    with open(task_json_path, "r", encoding="utf-8") as f:
        config = json.load(f)

    webapp_id = config["webappId"].strip()
    modifications = config.get("modifications", [])

    # ── 1. 获取节点信息并修改 ──
    t1 = time.time()
    print(f"[信息] 正在获取 webappId={webapp_id} 的节点信息...")
    node_info_list = get_node_info(webapp_id, api_key)

    for mod in modifications:
        node_id = mod["nodeId"]
        field_name = mod["fieldName"]
        target_node = next(
            (n for n in node_info_list if n["nodeId"] == node_id and n["fieldName"] == field_name),
            None,
        )
        if not target_node:
            print(f"[Error] 未找到节点 nodeId={node_id}, fieldName={field_name}，跳过")
            continue

        print(f"[修改] 节点: nodeId={node_id}, fieldName={field_name}")

        if target_node["fieldType"] in ("IMAGE", "AUDIO", "VIDEO"):
            file_path = mod.get("filePath")
            if not file_path:
                print(f"[Error] 节点 {node_id} 类型为 {target_node['fieldType']}，但未提供 filePath，跳过")
                continue
            print(f"[上传] 上传文件: {file_path}")
            upload_result = upload_file(api_key, file_path)
            print("上传结果:", upload_result)
            if upload_result and upload_result.get("msg") == "success":
                uploaded_file_name = upload_result.get("data", {}).get("fileName")
                if uploaded_file_name:
                    target_node["fieldValue"] = uploaded_file_name
                    print(f"[OK] 已更新 fieldValue: {uploaded_file_name}")
            else:
                print(f"[Error] 上传失败或返回格式异常: {upload_result}")
        else:
            field_value = mod.get("fieldValue", "")
            target_node["fieldValue"] = field_value
            print(f"[OK] 已更新 fieldValue: {field_value}")
    print(f"[耗时] 获取节点信息 & 修改: {_format_duration(time.time() - t1)}")

    # ── 2. 提交任务到 RunningHub ──
    t2 = time.time()
    print("[启动] 提交任务到 RunningHub...")
    submit_result = submit_task(webapp_id, node_info_list, api_key)
    print("[结果] 提交任务返回:", json.dumps(submit_result, ensure_ascii=False, indent=2))

    if submit_result.get("code") != 0:
        print("[Error] 提交任务失败")
        sys.exit(1)

    task_id = submit_result["data"]["taskId"]
    print(f"[任务ID] taskId: {task_id}")

    print_node_errors(submit_result)

    output_data = poll_until_complete(task_id, api_key)
    if not output_data:
        print("[Error] 任务未成功完成")
        sys.exit(1)
    print(f"[耗时] 云端推理 (提交+轮询): {_format_duration(time.time() - t2)}")

    # ── 3. 下载 latent 到 ComfyUI input/ ──
    t3 = time.time()
    comfy_server, comfy_input_dir = _load_comfyui_config()

    if not comfy_input_dir:
        print("[Error] 未配置 COMFYUI_INPUT_DIR，无法自动解码。")
        print("   请在 .env 中添加：COMFYUI_INPUT_DIR=D:/path/to/ComfyUI/input")
        sys.exit(1)

    print(f"[信息] 下载 latent 到 ComfyUI input/: {comfy_input_dir}")
    latent_files = download_files(output_data, comfy_input_dir)
    if not latent_files:
        print("[!] 没有下载到 latent 文件，跳过本地解码。")
        print(f"[耗时] 下载 latent: {_format_duration(time.time() - t3)}")
        print(f"\n[耗时] 流水线总耗时 {_format_duration(time.time() - t_total)}")
        return
    print(f"[耗时] 下载 latent: {_format_duration(time.time() - t3)}")

    # ── 4. 本地 ComfyUI 解码 ──
    t4 = time.time()
    client = ComfyUIClient(server_address=comfy_server, input_dir=comfy_input_dir)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = os.path.join(script_dir, "output")

    for latent_path in latent_files:
        print(f"\n{'='*60}")
        print(f"[解码] 处理 latent: {latent_path}")
        try:
            result = client.decode_latent(latent_path, output_dir=output_dir)
            total = sum(len(v) for v in result.values())
            print(f"[完成] 解码完成，共 {total} 张图片 -> {output_dir}")
        except Exception as e:
            print(f"[Error] 解码失败: {e}")
    print(f"[耗时] 本地 VAE 解码: {_format_duration(time.time() - t4)}")

    print(f"\n[OK] 流水线全部完成！最终图片在: {output_dir}")
    print(f"[耗时] 流水线总耗时 {_format_duration(time.time() - t_total)}")


def cmd_decode(latent_file: str) -> None:
    """独立的本地解码：将 latent 文件送入 ComfyUI VAE 解码"""
    t0 = time.time()
    comfy_server, comfy_input_dir = _load_comfyui_config()

    if not comfy_input_dir:
        print("[Error] 未配置 COMFYUI_INPUT_DIR。")
        print("   请在 .env 中添加：COMFYUI_INPUT_DIR=D:/path/to/ComfyUI/input")
        sys.exit(1)

    client = ComfyUIClient(server_address=comfy_server, input_dir=comfy_input_dir)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = os.path.join(script_dir, "output")

    print(f"[解码] 处理 latent: {latent_file}")
    result = client.decode_latent(latent_file, output_dir=output_dir)
    total = sum(len(v) for v in result.values())
    print(f"[完成] 解码完成，共 {total} 张图片 -> {output_dir}")
    print(f"[耗时] 总耗时 {_format_duration(time.time() - t0)}")


# ── CLI 入口 ──────────────────────────────────────────────


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Hood — AI 工作流编排工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    subparsers = parser.add_subparsers(dest="command", help="子命令")

    # info
    info_parser = subparsers.add_parser("info", help="查看 RunningHub 应用的节点信息")
    info_parser.add_argument("webapp_id", help="RunningHub 应用的 webappId")

    # run
    run_parser = subparsers.add_parser("run", help="完整流水线：提交云端 → 下载 latent → 本地解码")
    run_parser.add_argument(
        "task_json",
        nargs="?",
        default="task.json",
        help="任务配置文件路径（默认 task.json）",
    )

    # decode
    decode_parser = subparsers.add_parser("decode", help="独立的本地 ComfyUI 解码")
    decode_parser.add_argument("latent_file", help=".latent 文件路径")

    args = parser.parse_args()

    if args.command == "info":
        cmd_info(args.webapp_id)
    elif args.command == "run":
        cmd_run(args.task_json)
    elif args.command == "decode":
        cmd_decode(args.latent_file)
    else:
        # 无子命令时默认执行完整流水线
        cmd_run("task.json")


if __name__ == "__main__":
    main()
