"""
ComfyUI 本地客户端
提供通过 WebSocket API 向本地 ComfyUI 提交工作流并获取结果的功能。
"""
import json
import os
import shlex
import subprocess
import uuid
import urllib.request
import urllib.parse

import websocket

# 默认工作流模板路径（与本模块同目录）
_DEFAULT_WORKFLOW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "VAE_Decoder.json")


class ComfyUIClient:
    """本地 ComfyUI WebSocket 客户端"""

    def __init__(self, server_address: str = "127.0.0.1:8188", input_dir: str | None = None):
        self.server_address = server_address
        self.input_dir = input_dir
        self._client_id = str(uuid.uuid4())

    # ── 底层 API ──────────────────────────────────────────

    def _queue_prompt(self, prompt: dict, prompt_id: str) -> None:
        p = {"prompt": prompt, "client_id": self._client_id, "prompt_id": prompt_id}
        data = json.dumps(p).encode("utf-8")
        req = urllib.request.Request(f"http://{self.server_address}/prompt", data=data)
        urllib.request.urlopen(req).read()

    def _get_image(self, filename: str, subfolder: str, folder_type: str) -> bytes:
        params = {"filename": filename, "subfolder": subfolder, "type": folder_type}
        url = f"http://{self.server_address}/view?{urllib.parse.urlencode(params)}"
        with urllib.request.urlopen(url) as resp:
            return resp.read()

    def _get_history(self, prompt_id: str) -> dict:
        with urllib.request.urlopen(f"http://{self.server_address}/history/{prompt_id}") as resp:
            return json.loads(resp.read())

    # ── 提交工作流并等待 ────────────────────────────────────

    def submit_workflow(self, workflow: dict, output_dir: str = "output") -> dict[str, list[bytes]]:
        """
        提交工作流到 ComfyUI，等待执行完毕，下载所有输出图片。

        参数
        - workflow: ComfyUI 工作流字典
        - output_dir: 图片保存目录

        返回 { node_id: [image_bytes, ...] }
        """
        prompt_id = str(uuid.uuid4())

        # 提交
        self._queue_prompt(workflow, prompt_id)

        # 通过 WebSocket 等待执行完成
        ws = websocket.WebSocket()
        try:
            ws.connect(f"ws://{self.server_address}/ws?clientId={self._client_id}")
            while True:
                out = ws.recv()
                if isinstance(out, str):
                    message = json.loads(out)
                    if message["type"] == "executing":
                        data = message["data"]
                        if data["node"] is None and data["prompt_id"] == prompt_id:
                            break  # 执行完成
                else:
                    # 二进制预览数据，忽略
                    continue
        finally:
            ws.close()

        # 获取历史记录并下载图片
        history = self._get_history(prompt_id)[prompt_id]
        os.makedirs(output_dir, exist_ok=True)

        output_images: dict[str, list[bytes]] = {}
        for node_id, node_output in history["outputs"].items():
            images_output: list[bytes] = []
            if "images" in node_output:
                for image_info in node_output["images"]:
                    image_data = self._get_image(
                        image_info["filename"],
                        image_info["subfolder"],
                        image_info["type"],
                    )
                    # 保存到磁盘
                    filepath = os.path.join(output_dir, image_info["filename"])
                    with open(filepath, "wb") as f:
                        f.write(image_data)
                    print(f"  [OK] 已保存: {filepath} ({len(image_data)} bytes)")
                    images_output.append(image_data)
            output_images[node_id] = images_output

        return output_images

    # ── 便捷方法：解码 latent ──────────────────────────────

    def decode_latent(
        self,
        latent_filename: str,
        output_dir: str = "output",
        workflow_path: str | None = None,
    ) -> dict[str, list[bytes]]:
        """
        将 latent 文件复制到 ComfyUI input/ 目录，提交 VAE 解码工作流。

        参数
        - latent_filename: .latent 文件路径（将复制到 input_dir 下）
        - output_dir: 解码结果图片保存目录
        - workflow_path: 工作流模板 JSON 路径，默认使用 VAE_Decoder.json

        返回 submit_workflow 的结果
        """
        # 1. 确保 latent 文件在 ComfyUI input/ 中
        if self.input_dir:
            latent_src = latent_filename
            latent_basename = os.path.basename(latent_src)
            latent_dst = os.path.join(self.input_dir, latent_basename)

            if os.path.abspath(latent_src) != os.path.abspath(latent_dst):
                import shutil
                os.makedirs(self.input_dir, exist_ok=True)
                shutil.copy2(latent_src, latent_dst)
                print(f"[信息] latent 已复制到: {latent_dst}")
        else:
            # 没有配置 input_dir 时，直接使用文件名（假设已在 ComfyUI input/ 中）
            latent_basename = os.path.basename(latent_filename)
            print(f"[信息] input_dir 未配置，假设 latent 已在 ComfyUI input/ 中: {latent_basename}")

        # 2. 加载工作流模板
        wf_path = workflow_path or _DEFAULT_WORKFLOW
        with open(wf_path, "r", encoding="utf-8") as f:
            workflow = json.load(f)

        # 3. 替换 latent 文件名
        #    约定：VAE_Decoder.json 中 node "3" 的 inputs.latent 为占位符
        workflow["3"]["inputs"]["latent"] = latent_basename

        print(f"[信息] 解码工作流: latent={latent_basename}")
        return self.submit_workflow(workflow, output_dir)
