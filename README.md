# Hood — RunningHub AI 应用 CLI 工具

通过命令行调用 [RunningHub](https://www.runninghub.cn) AI 应用的 API，自动修改节点参数、提交任务并轮询结果。

## 快速开始

### 1. 安装依赖

```bash
pip install requests
```

### 2. 配置 API 密钥

在项目根目录创建 `.env` 文件（参考 `.env.example`）：

```
RUNNINGHUB_API_KEY=从RunningHub控制台获取的密钥
```

> `.env` 已在 `.gitignore` 中，不会误提交到 Git。

也可以设置系统环境变量（`.env` 不存在时作为回退）：

```cmd
set RUNNINGHUB_API_KEY=你的密钥
```

### 3. 使用

#### 查看应用节点信息

先获取指定 AI 应用的节点列表，方便编写 JSON：

```bash
python main.py info <webappId>
```

`webappId` 是 AI 应用详情页 URL 末尾的数字，例如 `https://www.runninghub.cn/ai-detail/1937084629516193794` 中的 `1937084629516193794`。

#### 提交任务

编写 `task.json` 放到项目根目录（参考 `task.json.example`），然后直接运行：

```bash
python main.py
```

程序会自动读取根目录下的 `task.json` 并提交任务。

## JSON 配置说明

```json
{
  "webappId": "1937084629516193794",
  "modifications": [
    {
      "nodeId": "node_xxx",
      "fieldName": "prompt",
      "fieldValue": "一只可爱的猫"
    },
    {
      "nodeId": "node_yyy",
      "fieldName": "image",
      "filePath": "D:/images/cat.jpg"
    }
  ]
}
```

- **webappId**: 必填，AI 应用的 ID
- **modifications**: 必填，要修改的节点列表
  - **nodeId**: 节点 ID
  - **fieldName**: 字段名称
  - **fieldValue**: 文本节点的值（文本/下拉选择等类型使用）
  - **filePath**: 文件路径（图片/音频/视频节点使用，自动上传到 RunningHub）

> 先用 `info` 命令查看节点列表，就能知道有哪些 `nodeId`、`fieldName` 和 `fieldType` 可以修改。

## 命令参考

| 命令 | 说明 |
|------|------|
| `python main.py info <webappId>` | 查看应用的节点信息 |
| `python main.py` | 自动读取 `task.json` 并提交任务 |

## 工作流程

```
.env (密钥) ──> 读取节点信息 ──> 应用修改（文本/文件上传）──> 提交任务 ──> 轮询结果
```

## 项目结构

```
D:\Github\Hood\
├── main.py              # 主程序
├── .env                 # API 密钥（本地文件，不提交 Git）
├── .env.example         # 密钥模板（可提交 Git）
├── task.json.example    # 任务配置模板
├── .gitignore
├── pyproject.toml
└── README.md
```
