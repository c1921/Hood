"""
RunningHub API 客户端
提供向 RunningHub 平台提交任务、轮询结果、下载文件的完整封装。
"""
import http.client
import json
import os
import time

import requests

API_HOST = "www.runninghub.cn"


def get_node_info(webapp_id: str, api_key: str) -> list:
    """获取应用的节点信息列表"""
    try:
        conn = http.client.HTTPSConnection(API_HOST, timeout=30)
        payload = ""
        headers = {}
        conn.request(
            "GET",
            f"/api/webapp/apiCallDemo?apiKey={api_key}&webappId={webapp_id}",
            payload,
            headers,
        )
        res = conn.getresponse()
        data = json.loads(res.read().decode("utf-8"))
        node_data = data.get("data")
        if node_data is None:
            print("[Error] API 返回异常:", json.dumps(data, indent=2, ensure_ascii=False))
            return []
        node_info_list = node_data.get("nodeInfoList", [])
        print("[OK] 提取的 nodeInfoList:")
        print(json.dumps(node_info_list, indent=2, ensure_ascii=False))
        return node_info_list
    except Exception as e:
        print(f"[Error] 获取节点信息失败: {e}")
        return []


def upload_file(api_key: str, file_path: str) -> dict:
    """上传文件到 RunningHub 平台"""
    url = "https://www.runninghub.cn/task/openapi/upload"
    headers = {"Host": "www.runninghub.cn"}
    data = {"apiKey": api_key, "fileType": "input"}
    with open(file_path, "rb") as f:
        files = {"file": f}
        response = requests.post(url, headers=headers, files=files, data=data)
    return response.json()


def submit_task(webapp_id: str, node_info_list: list, api_key: str) -> dict:
    """提交任务到 RunningHub"""
    try:
        conn = http.client.HTTPSConnection(API_HOST, timeout=30)
        payload = json.dumps(
            {
                "webappId": webapp_id,
                "apiKey": api_key,
                "nodeInfoList": node_info_list,
            }
        )
        headers = {"Host": API_HOST, "Content-Type": "application/json"}
        conn.request("POST", "/task/openapi/ai-app/run", payload, headers)
        res = conn.getresponse()
        data = json.loads(res.read().decode("utf-8"))
        conn.close()
        return data
    except Exception as e:
        print(f"[Error] 提交任务失败: {e}")
        return {"code": -1, "message": str(e)}


def query_task_outputs(task_id: str, api_key: str) -> dict:
    """查询任务输出"""
    try:
        conn = http.client.HTTPSConnection(API_HOST, timeout=30)
        payload = json.dumps({"apiKey": api_key, "taskId": task_id})
        headers = {"Host": API_HOST, "Content-Type": "application/json"}
        conn.request("POST", "/task/openapi/outputs", payload, headers)
        res = conn.getresponse()
        data = json.loads(res.read().decode("utf-8"))
        conn.close()
        return data
    except Exception as e:
        print(f"[Error] 查询任务输出失败: {e}")
        return {"code": -1, "message": str(e)}


def print_node_errors(submit_result: dict) -> None:
    """解析并打印提交结果中的节点错误信息"""
    prompt_tips_str = submit_result.get("data", {}).get("promptTips")
    if prompt_tips_str:
        try:
            prompt_tips = json.loads(prompt_tips_str)
            node_errors = prompt_tips.get("node_errors", {})
            if node_errors:
                print("[!] 节点错误信息如下：")
                for node_id, err in node_errors.items():
                    print(f"  节点 {node_id} 错误: {err}")
            else:
                print("[OK] 无节点错误，任务提交成功。")
        except Exception as e:
            print("[!] 无法解析 promptTips:", e)
    else:
        print("[!] 未返回 promptTips 字段。")


def poll_until_complete(task_id: str, api_key: str, timeout: int = 600) -> list | None:
    """轮询任务结果，直到完成、失败或超时，返回输出文件列表"""
    start_time = time.time()
    while True:
        outputs_result = query_task_outputs(task_id, api_key)
        code = outputs_result.get("code")
        data = outputs_result.get("data")
        if code == 0 and data:  # 成功
            print("[完成] 生成结果完成！")
            return data
        elif code == -1:  # 网络错误（超时/断连等）
            print("[!] 网络请求异常，稍后重试...")
        elif code == 805:  # 任务失败
            failed_reason = data.get("failedReason") if data else None
            print("[Error] 任务失败！")
            if failed_reason:
                print(f"节点 {failed_reason.get('node_name')} 失败原因: {failed_reason.get('exception_message')}")
                print("Traceback:", failed_reason.get("traceback"))
            else:
                print(outputs_result)
            return None
        elif code in (804, 813):  # 运行中或排队中
            status_text = "运行中" if code == 804 else "排队中"
            print(f"[等待] 任务{status_text}...")
        else:
            print("[!] 未知状态:", outputs_result)
        if time.time() - start_time > timeout:
            print("[超时] 等待超时（超过10分钟），任务未完成。")
            break
        time.sleep(5)
    return None


def download_files(data_list: list, output_dir: str) -> list[str]:
    """下载输出结果中所有 latent 文件到指定目录，返回本地的文件路径列表"""
    latent_items = [item for item in data_list if item.get("fileType") == "latent"]
    if not latent_items:
        print("[!] 没有 latent 文件可供下载")
        return []

    os.makedirs(output_dir, exist_ok=True)
    print(f"[下载] 开始下载 {len(latent_items)} 个 latent 文件到 {output_dir}")

    saved_files = []
    for item in latent_items:
        file_url = item.get("fileUrl")
        if not file_url:
            print("[!]  跳过：缺少 fileUrl")
            continue
        file_name = os.path.basename(file_url.split("?")[0])
        save_path = os.path.join(output_dir, file_name)
        try:
            resp = requests.get(file_url, stream=True, timeout=60)
            resp.raise_for_status()
            with open(save_path, "wb") as f:
                for chunk in resp.iter_content(chunk_size=8192):
                    f.write(chunk)
            print(f"  [OK] {file_name} 已保存")
            saved_files.append(save_path)
        except Exception as e:
            print(f"  [Error] {file_name} 下载失败: {e}")
    return saved_files
