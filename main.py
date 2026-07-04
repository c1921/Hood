import http.client
import json
import mimetypes
from codecs import encode
import sys
import time
import os
import requests

API_HOST = "www.runninghub.cn"


def get_nodo(webappId, Api_Key):
    conn = http.client.HTTPSConnection(API_HOST)
    payload = ""
    headers = {}
    conn.request(
        "GET",
        f"/api/webapp/apiCallDemo?apiKey={Api_Key}&webappId={webappId}",
        payload,
        headers,
    )
    res = conn.getresponse()
    # 读取响应内容
    data = res.read()
    # 转成 Python 字典
    data_json = json.loads(data.decode("utf-8"))
    # 取出 nodeInfoList
    node_data = data_json.get("data")
    if node_data is None:
        print("[Error] API 返回异常:", json.dumps(data_json, indent=2, ensure_ascii=False))
        return []
    node_info_list = node_data.get("nodeInfoList", [])
    print("[OK] 提取的 nodeInfoList:")
    print(json.dumps(node_info_list, indent=2, ensure_ascii=False))
    return node_info_list


def upload_file(API_KEY, file_path):
    """
    上传文件到 RunningHub 平台
    """
    url = "https://www.runninghub.cn/task/openapi/upload"
    headers = {"Host": "www.runninghub.cn"}
    data = {"apiKey": API_KEY, "fileType": "input"}
    with open(file_path, "rb") as f:
        files = {"file": f}
        response = requests.post(url, headers=headers, files=files, data=data)
    return response.json()


# 1️⃣ 提交任务
def submit_task(webapp_id, node_info_list, API_KEY):
    conn = http.client.HTTPSConnection(API_HOST)
    payload = json.dumps(
        {
            "webappId": webapp_id,
            "apiKey": API_KEY,
            # "quickCreateCode": quick_create_code,
            "nodeInfoList": node_info_list,
        }
    )
    headers = {"Host": API_HOST, "Content-Type": "application/json"}
    conn.request("POST", "/task/openapi/ai-app/run", payload, headers)
    res = conn.getresponse()
    data = json.loads(res.read().decode("utf-8"))
    conn.close()
    return data


def query_task_outputs(task_id, API_KEY):
    conn = http.client.HTTPSConnection(API_HOST)
    payload = json.dumps({"apiKey": API_KEY, "taskId": task_id})
    headers = {"Host": API_HOST, "Content-Type": "application/json"}
    conn.request("POST", "/task/openapi/outputs", payload, headers)
    res = conn.getresponse()
    data = json.loads(res.read().decode("utf-8"))
    conn.close()
    return data


def print_node_errors(submit_result):
    """解析并打印提交结果中的节点错误信息"""
    prompt_tips_str = submit_result["data"].get("promptTips")
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


def poll_until_complete(task_id, API_KEY, timeout=600):
    """轮询任务结果，直到完成、失败或超时"""
    start_time = time.time()
    while True:
        outputs_result = query_task_outputs(task_id, API_KEY)
        code = outputs_result.get("code")
        data = outputs_result.get("data")
        if code == 0 and data:  # 成功
            print("[完成] 生成结果完成！")
            print(data)
            return data
        elif code == 805:  # 任务失败
            failed_reason = data.get("failedReason") if data else None
            print("[Error] 任务失败！")
            if failed_reason:
                print(f"节点 {failed_reason.get('node_name')} 失败原因: {failed_reason.get('exception_message')}")
                print("Traceback:", failed_reason.get("traceback"))
            else:
                print(outputs_result)
            return None
        elif code == 804 or code == 813:  # 运行中或排队中
            status_text = "运行中" if code == 804 else "排队中"
            print(f"[等待] 任务{status_text}...")
        else:
            print("[!] 未知状态:", outputs_result)
        if time.time() - start_time > timeout:
            print("[超时] 等待超时（超过10分钟），任务未完成。")
            break
        time.sleep(5)
    return None


def cmd_info(webapp_id, api_key):
    """info 子命令：获取并打印节点信息"""
    print(f"[信息] 正在获取 webappId={webapp_id} 的节点信息...")
    node_info_list = get_nodo(webapp_id, api_key)
    return node_info_list


def cmd_run(config_path, api_key):
    """主流程：从 JSON 文件读取配置 -> 修改节点 -> 提交任务 -> 轮询结果"""
    with open(config_path, "r", encoding="utf-8") as f:
        config = json.load(f)

    webapp_id = config["webappId"].strip()
    modifications = config.get("modifications", [])

    print(f"[信息] 正在获取 webappId={webapp_id} 的节点信息...")
    node_info_list = get_nodo(webapp_id, api_key)

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

        print(f"[修改]  修改节点: nodeId={node_id}, fieldName={field_name}")

        if target_node["fieldType"] in ["IMAGE", "AUDIO", "VIDEO"]:
            # 文件上传模式
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
                    print(f"[OK] 已更新 {target_node['fieldType']} fieldValue: {uploaded_file_name}")
            else:
                print(f"[Error] 上传失败或返回格式异常: {upload_result}")
        else:
            # 文本模式
            field_value = mod.get("fieldValue", "")
            target_node["fieldValue"] = field_value
            print(f"[OK] 已更新 fieldValue: {field_value}")

    print("[启动] 提交任务...")
    submit_result = submit_task(webapp_id, node_info_list, api_key)
    print("[结果] 提交任务返回:", submit_result)

    if submit_result.get("code") != 0:
        print("[Error] 提交任务失败:", submit_result)
        sys.exit(1)

    task_id = submit_result["data"]["taskId"]
    print(f"[任务ID] taskId: {task_id}")

    print_node_errors(submit_result)
    poll_until_complete(task_id, api_key)
    print("[OK] 任务完成！")


def _load_api_key():
    """从 .env 文件或环境变量读取 RUNNINGHUB_API_KEY"""
    # 优先从 .env 文件读取（与 main.py 同目录）
    script_dir = os.path.dirname(os.path.abspath(__file__))
    dotenv_path = os.path.join(script_dir, ".env")
    if os.path.isfile(dotenv_path):
        with open(dotenv_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    key, _, val = line.partition("=")
                    if key.strip() == "RUNNINGHUB_API_KEY":
                        return val.strip().strip("\"'")
    # 回退到系统环境变量
    return os.environ.get("RUNNINGHUB_API_KEY")


if __name__ == "__main__":
    api_key = _load_api_key()
    if not api_key:
        print("[Error] 未找到 API 密钥。")
        print("   方式一：在项目根目录创建 .env 文件，写入：")
        print("         RUNNINGHUB_API_KEY=你的密钥")
        print()
        print("   方式二：设置系统环境变量（见上一步的输出提示）")
        sys.exit(1)
    api_key = api_key.strip()

    if len(sys.argv) >= 2 and sys.argv[1] == "info":
        if len(sys.argv) < 3:
            print("[Error] 缺少 webappId。用法: python main.py info <webappId>")
            sys.exit(1)
        cmd_info(sys.argv[2], api_key)
    else:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        task_json = os.path.join(script_dir, "task.json")
        if not os.path.isfile(task_json):
            print(f"[Error] 未找到 {task_json}")
            print("用法:")
            print("  python main.py info <webappId>      # 查看应用节点信息")
            print("  python main.py                      # 自动读取 task.json 提交任务")
            sys.exit(1)
        cmd_run(task_json, api_key)
