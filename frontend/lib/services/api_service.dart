import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/api_models.dart';

/// Hood API 服务 — 封装所有后端 REST 调用
class ApiService {
  String _baseUrl;

  ApiService({this._baseUrl = 'http://localhost:8000'});

  /// 更新服务器地址
  void updateBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// 当前服务器地址
  String get baseUrl => _baseUrl;

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  // ── 通用错误处理 ───────────────────────────────────

  /// 从响应中提取错误信息
  String _parseError(http.Response resp) {
    try {
      final body = jsonDecode(resp.body);
      if (body is Map) {
        final detail = body['detail'];
        if (detail is String) return detail;
        if (detail is Map) {
          return (detail['error'] ?? detail['message'] ?? resp.reasonPhrase)
              .toString();
        }
        return detail.toString();
      }
    } catch (_) {}
    return resp.reasonPhrase ?? 'HTTP ${resp.statusCode}';
  }

  /// 抛出格式化的 API 异常
  Never _throwError(http.Response resp) {
    throw ApiException(statusCode: resp.statusCode, message: _parseError(resp));
  }

  // ── 1. 健康检查 ───────────────────────────────────

  Future<HealthResponse> health() async {
    final resp = await http.get(_uri('/api/health')).timeout(const Duration(seconds: 10));
    if (resp.statusCode == 200) {
      return HealthResponse.fromJson(jsonDecode(resp.body));
    }
    _throwError(resp);
  }

  // ── 2. 获取节点信息 ───────────────────────────────

  Future<InfoResponse> getNodeInfo(String webappId) async {
    final resp = await http
        .post(
          _uri('/api/info'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'webapp_id': webappId}),
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode == 200) {
      return InfoResponse.fromJson(jsonDecode(resp.body));
    }
    _throwError(resp);
  }

  // ── 3. 提交完整流水线 ─────────────────────────────

  Future<TaskInfo> runPipeline({
    required String webappId,
    required List<Modification> modifications,
  }) async {
    final resp = await http
        .post(
          _uri('/api/run'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'webapp_id': webappId,
            'modifications': modifications.map((m) => m.toJson()).toList(),
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode == 202) {
      return TaskInfo.fromJson(jsonDecode(resp.body));
    }
    _throwError(resp);
  }

  // ── 4. 独立 VAE 解码 ─────────────────────────────

  Future<TaskInfo> decodeLatent({
    required String latentFile,
    String? outputDir,
  }) async {
    final resp = await http
        .post(
          _uri('/api/decode'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'latent_file': latentFile,
            'output_dir': outputDir,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode == 202) {
      return TaskInfo.fromJson(jsonDecode(resp.body));
    }
    _throwError(resp);
  }

  // ── 5. 查询任务状态 ─────────────────────────────

  Future<TaskInfo> getTaskStatus(String taskId) async {
    final resp = await http
        .get(_uri('/api/tasks/$taskId'))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 200) {
      return TaskInfo.fromJson(jsonDecode(resp.body));
    }
    if (resp.statusCode == 404) {
      throw ApiException(statusCode: 404, message: '任务不存在');
    }
    _throwError(resp);
  }
}

/// API 异常
class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'ApiException($statusCode): $message';
}
