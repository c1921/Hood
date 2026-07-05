/// 节点修改项
class Modification {
  final String nodeId;
  final String fieldName;
  final String? fieldValue;
  final String? filePath;

  const Modification({
    required this.nodeId,
    required this.fieldName,
    this.fieldValue,
    this.filePath,
  });

  Map<String, dynamic> toJson() => {
        'node_id': nodeId,
        'field_name': fieldName,
        'field_value': fieldValue,
        'file_path': filePath,
      };
}

/// 节点信息（来自 RunningHub）
class NodeInfo {
  final String nodeId;
  final String fieldName;
  final String fieldType;
  final String? fieldValue;

  const NodeInfo({
    required this.nodeId,
    required this.fieldName,
    required this.fieldType,
    this.fieldValue,
  });

  factory NodeInfo.fromJson(Map<String, dynamic> json) => NodeInfo(
        nodeId: json['nodeId'] as String? ?? '',
        fieldName: json['fieldName'] as String? ?? '',
        fieldType: json['fieldType'] as String? ?? '',
        fieldValue: json['fieldValue'] as String?,
      );
}

/// 任务状态枚举
enum TaskStatus {
  pending,
  running,
  done,
  failed,
  unknown;

  String get label {
    switch (this) {
      case TaskStatus.pending:
        return '等待中';
      case TaskStatus.running:
        return '运行中';
      case TaskStatus.done:
        return '已完成';
      case TaskStatus.failed:
        return '失败';
      case TaskStatus.unknown:
        return '未知';
    }
  }

  static TaskStatus fromString(String s) {
    switch (s) {
      case 'pending':
        return TaskStatus.pending;
      case 'running':
        return TaskStatus.running;
      case 'done':
        return TaskStatus.done;
      case 'failed':
        return TaskStatus.failed;
      default:
        return TaskStatus.unknown;
    }
  }
}

/// 任务信息
class TaskInfo {
  final String taskId;
  final TaskStatus status;
  final double createdAt;
  final double updatedAt;
  final String message;
  final List<String> outputFiles;

  const TaskInfo({
    required this.taskId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.message = '',
    this.outputFiles = const [],
  });

  factory TaskInfo.fromJson(Map<String, dynamic> json) => TaskInfo(
        taskId: json['task_id'] as String? ?? '',
        status: TaskStatus.fromString(json['status'] as String? ?? 'unknown'),
        createdAt: (json['created_at'] as num?)?.toDouble() ?? 0,
        updatedAt: (json['updated_at'] as num?)?.toDouble() ?? 0,
        message: json['message'] as String? ?? '',
        outputFiles: (json['output_files'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );
}

/// 健康检查响应
class HealthResponse {
  final String status;
  final String version;

  const HealthResponse({this.status = 'ok', this.version = '0.1.0'});

  factory HealthResponse.fromJson(Map<String, dynamic> json) => HealthResponse(
        status: json['status'] as String? ?? '',
        version: json['version'] as String? ?? '',
      );
}

/// 节点信息响应
class InfoResponse {
  final int code;
  final List<NodeInfo> data;

  const InfoResponse({required this.code, required this.data});

  factory InfoResponse.fromJson(Map<String, dynamic> json) => InfoResponse(
        code: json['code'] as int? ?? -1,
        data: (json['data'] as List<dynamic>?)
                ?.map((e) => NodeInfo.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

/// 错误响应
class ErrorDetail {
  final String error;
  final String? detail;

  const ErrorDetail({required this.error, this.detail});

  factory ErrorDetail.fromJson(Map<String, dynamic> json) => ErrorDetail(
        error: json['error'] as String? ?? '未知错误',
        detail: json['detail'] as String?,
      );
}
