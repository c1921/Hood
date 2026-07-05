import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/api_models.dart';

class TaskStatusScreen extends StatefulWidget {
  final ApiService? apiService;
  final String? initialTaskId;

  const TaskStatusScreen({super.key, this.apiService, this.initialTaskId});

  @override
  State<TaskStatusScreen> createState() => _TaskStatusScreenState();
}

class _TaskStatusScreenState extends State<TaskStatusScreen> {
  late final ApiService _api;
  final _taskIdController = TextEditingController();
  TaskInfo? _task;
  bool _loading = false;
  String? _error;
  Timer? _pollTimer;
  bool _autoRefresh = false;

  @override
  void initState() {
    super.initState();
    _api = widget.apiService ?? ApiService();
    if (widget.initialTaskId != null) {
      _taskIdController.text = widget.initialTaskId!;
      _fetchTask();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _taskIdController.dispose();
    super.dispose();
  }

  Future<void> _fetchTask() async {
    final taskId = _taskIdController.text.trim();
    if (taskId.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final task = await _api.getTaskStatus(taskId);
      if (mounted) {
        setState(() {
          _task = task;
          _loading = false;
        });
        // 自动刷新：pending/running 时每 3 秒轮询
        if (_autoRefresh &&
            (task.status == TaskStatus.pending ||
             task.status == TaskStatus.running)) {
          _startPolling();
        } else if (_autoRefresh) {
          _stopPolling();
        }
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; _task = null; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; _task = null; });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchTaskSilent();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _fetchTaskSilent() async {
    final taskId = _taskIdController.text.trim();
    if (taskId.isEmpty) return;
    try {
      final task = await _api.getTaskStatus(taskId);
      if (mounted) {
        setState(() => _task = task);
        if (task.status == TaskStatus.done || task.status == TaskStatus.failed) {
          _stopPolling();
        }
      }
    } catch (_) {}
  }

  void _toggleAutoRefresh(bool value) {
    setState(() {
      _autoRefresh = value;
      if (value) {
        if (_task != null &&
            (_task!.status == TaskStatus.pending ||
             _task!.status == TaskStatus.running)) {
          _startPolling();
        }
      } else {
        _stopPolling();
      }
    });
  }

  String _formatTime(double timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).toInt());
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('任务状态')),
      body: Column(
        children: [
          // ── 输入区域 ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _taskIdController,
                    decoration: const InputDecoration(
                      labelText: 'Task ID',
                      hintText: '550e8400-e29b-...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) {
                      _stopPolling();
                      _fetchTask();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _loading ? null : () {
                    _stopPolling();
                    _fetchTask();
                  },
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search),
                  label: Text(_loading ? '查询中' : '查询'),
                ),
              ],
            ),
          ),

          // ── 自动刷新切换 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Spacer(),
                SizedBox(
                  height: 32,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('自动刷新',
                          style: theme.textTheme.labelSmall),
                      const SizedBox(width: 4),
                      Switch(
                        value: _autoRefresh,
                        onChanged: _toggleAutoRefresh,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── 错误提示 ──
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: theme.colorScheme.onErrorContainer, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        )),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── 任务详情 ──
          if (_task != null) _buildTaskDetail(theme),
        ],
      ),
    );
  }

  Widget _buildTaskDetail(ThemeData theme) {
    final task = _task!;
    final isActive = task.status == TaskStatus.pending ||
        task.status == TaskStatus.running;
    final isDone = task.status == TaskStatus.done;
    final isFailed = task.status == TaskStatus.failed;

    return Expanded(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 状态卡片 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // 状态图标
                  _statusIcon(task.status, theme),
                  const SizedBox(height: 12),
                  Text(
                    task.status.label,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDone
                          ? Colors.green
                          : isFailed
                              ? Colors.red
                              : theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (isActive)
                    const LinearProgressIndicator(),
                  if (_autoRefresh && isActive)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '自动刷新中...',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── 详细信息 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('详细信息', style: theme.textTheme.titleSmall),
                  const Divider(),
                  _detailRow('Task ID', task.taskId, theme),
                  _detailRow('消息', task.message, theme),
                  _detailRow('创建时间', _formatTime(task.createdAt), theme),
                  _detailRow('更新时间', _formatTime(task.updatedAt), theme),
                ],
              ),
            ),
          ),

          // ── 输出文件 ──
          if (task.outputFiles.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('输出文件', style: theme.textTheme.titleSmall),
                    const Divider(),
                    ...task.outputFiles.map((f) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(Icons.insert_drive_file_outlined,
                              size: 16, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(f,
                                style: theme.textTheme.bodySmall),
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ),
          ],

          // ── 操作按钮 ──
          if (isActive) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                _stopPolling();
                _fetchTask();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('手动刷新'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 40),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusIcon(TaskStatus status, ThemeData theme) {
    IconData icon;
    Color color;
    switch (status) {
      case TaskStatus.pending:
        icon = Icons.hourglass_empty;
        color = Colors.orange;
      case TaskStatus.running:
        icon = Icons.sync;
        color = Colors.blue;
      case TaskStatus.done:
        icon = Icons.check_circle;
        color = Colors.green;
      case TaskStatus.failed:
        icon = Icons.cancel;
        color = Colors.red;
      case TaskStatus.unknown:
        icon = Icons.help;
        color = Colors.grey;
    }
    return Icon(icon, size: 56, color: color);
  }

  Widget _detailRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
