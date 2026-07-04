#This is an example that uses the websockets api to know when a prompt execution is done
#Once the prompt execution is done it downloads the images using the /history endpoint

import argparse
import os
import websocket  # NOTE: websocket-client (https://github.com/websocket-client/websocket-client)
import uuid
import json
import urllib.request
import urllib.parse

server_address = os.environ.get("COMFYUI_SERVER", "127.0.0.1:8188")
client_id = str(uuid.uuid4())

def queue_prompt(prompt, prompt_id):
    p = {"prompt": prompt, "client_id": client_id, "prompt_id": prompt_id}
    data = json.dumps(p).encode('utf-8')
    req = urllib.request.Request("http://{}/prompt".format(server_address), data=data)
    urllib.request.urlopen(req).read()

def get_image(filename, subfolder, folder_type):
    data = {"filename": filename, "subfolder": subfolder, "type": folder_type}
    url_values = urllib.parse.urlencode(data)
    with urllib.request.urlopen("http://{}/view?{}".format(server_address, url_values)) as response:
        return response.read()

def get_history(prompt_id):
    with urllib.request.urlopen("http://{}/history/{}".format(server_address, prompt_id)) as response:
        return json.loads(response.read())

def get_images(ws, prompt):
    prompt_id = str(uuid.uuid4())
    queue_prompt(prompt, prompt_id)
    output_images = {}
    while True:
        out = ws.recv()
        if isinstance(out, str):
            message = json.loads(out)
            if message['type'] == 'executing':
                data = message['data']
                if data['node'] is None and data['prompt_id'] == prompt_id:
                    break #Execution is done
        else:
            # If you want to be able to decode the binary stream for latent previews, here is how you can do it:
            # bytesIO = BytesIO(out[8:])
            # preview_image = Image.open(bytesIO) # This is your preview in PIL image format, store it in a global
            continue #previews are binary data

    history = get_history(prompt_id)[prompt_id]
    for node_id in history['outputs']:
        node_output = history['outputs'][node_id]
        images_output = []
        if 'images' in node_output:
            for image in node_output['images']:
                image_data = get_image(image['filename'], image['subfolder'], image['type'])
                images_output.append(image_data)
        output_images[node_id] = images_output

    return output_images

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Submit a workflow to local ComfyUI via WebSocket API")
    parser.add_argument(
        "workflow_json",
        nargs="?",
        default=None,
        help="Path to a ComfyUI workflow JSON file. If omitted, uses the built-in example prompt.",
    )
    args = parser.parse_args()

    if args.workflow_json:
        with open(args.workflow_json, "r", encoding="utf-8") as f:
            prompt = json.load(f)
        print(f"[信息] 已加载工作流: {args.workflow_json}")
        print(f"[信息] 服务器地址: {server_address}")
    else:
        # 内置默认工作流 (txt2img)
        DEFAULT_WORKFLOW = {
            "3": {
                "class_type": "KSampler",
                "inputs": {
                    "cfg": 8,
                    "denoise": 1,
                    "latent_image": ["5", 0],
                    "model": ["4", 0],
                    "negative": ["7", 0],
                    "positive": ["6", 0],
                    "sampler_name": "euler",
                    "scheduler": "normal",
                    "seed": 8566257,
                    "steps": 20,
                },
            },
            "4": {
                "class_type": "CheckpointLoaderSimple",
                "inputs": {"ckpt_name": "v1-5-pruned-emaonly.safetensors"},
            },
            "5": {
                "class_type": "EmptyLatentImage",
                "inputs": {"batch_size": 1, "height": 512, "width": 512},
            },
            "6": {
                "class_type": "CLIPTextEncode",
                "inputs": {"clip": ["4", 1], "text": "masterpiece best quality girl"},
            },
            "7": {
                "class_type": "CLIPTextEncode",
                "inputs": {"clip": ["4", 1], "text": "bad hands"},
            },
            "8": {
                "class_type": "VAEDecode",
                "inputs": {"samples": ["3", 0], "vae": ["4", 2]},
            },
            "9": {
                "class_type": "SaveImage",
                "inputs": {"filename_prefix": "ComfyUI", "images": ["8", 0]},
            },
        }
        prompt = DEFAULT_WORKFLOW
        prompt["6"]["inputs"]["text"] = "masterpiece best quality man"
        prompt["3"]["inputs"]["seed"] = 5
        print("[信息] 使用内置示例工作流")

    ws = websocket.WebSocket()
    ws.connect("ws://{}/ws?clientId={}".format(server_address, client_id))
    print("[信息] WebSocket 已连接，等待执行完成...")
    images = get_images(ws, prompt)
    ws.close()

    # 保存图片到 download/ 目录
    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.join(script_dir, "download")
    os.makedirs(out_dir, exist_ok=True)

    total_images = sum(len(img_list) for img_list in images.values())
    print(f"[完成] 共获取 {total_images} 张图片，来自 {len(images)} 个节点")
    for node_id, img_list in images.items():
        for i, img_data in enumerate(img_list):
            filename = f"node_{node_id}_{i}.png"
            filepath = os.path.join(out_dir, filename)
            with open(filepath, "wb") as f:
                f.write(img_data)
            print(f"  [OK] 已保存: {filepath} ({len(img_data)} bytes)")

