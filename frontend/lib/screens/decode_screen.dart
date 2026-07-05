import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/api_models.dart';
import 'task_status_screen.dart';

class DecodeScreen extends StatefulWidget {
  final ApiService? apiService;

  const DecodeScreen({super.key, this.apiService});

  @override
  State<DecodeScreen> createState() => _DecodeScreenState();
}

class _DecodeScreenState extends State<DecodeScreen> {
  late final ApiService _api;
  final _latentFileController = TextEditingController();
  final _outputDirController = TextEditingController();
  bool _submitting = false;
  TaskInfo? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = widget.apiService ?? ApiService();
  }

  @override
  void dispose() {
    _latentFileController.dispose();
    _outputDirController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final latentFile = _latentFileController.text.trim();
    if (latentFile.isEmpty) {
      _showSnack('请输入 .latent 文件路径');
      return;
    }

    setState(() {
      _submitting = true;
      _result = null;
      _error = null;
    });

    try {
      final task = await _api.decodeLatent(
        latentFile: latentFile,
        outputDir: _outputDirController.text.trim().isEmpty
            ? null
            : _outputDirController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _result = task;
          _submitting = false;
        });
        _showSnack('解码任务已提交: ${task.taskId}');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _submitting = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _submitting = false; });
    }
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('VAE 解码')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 说明 ──
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: theme.colorScheme.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '将 .latent 文件送入本地 ComfyUI 解码为图片',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── 输入区域 ──
          TextField(
            controller: _latentFileController,
            decoration: const InputDecoration(
              labelText: '.latent 文件路径 *',
              hintText: 'D:/ComfyUI/input/123456.latent',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _outputDirController,
            decoration: const InputDecoration(
              labelText: '输出目录（可选）',
              hintText: '默认 output/',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),

          // ── 提交按钮 ──
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.image),
            label: Text(_submitting ? '提交中...' : '开始解码'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),

          // ── 错误提示 ──
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
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
          ],

          // ── 结果 ──
          if (_result != null) ...[
            const SizedBox(height: 16),
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: theme.colorScheme.onPrimaryContainer,
                            size: 20),
                        const SizedBox(width: 8),
                        Text('解码任务已提交',
                            style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        )),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Task ID: ${_result!.taskId}',
                        style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    )),
                    const SizedBox(height: 4),
                    Text('状态: ${_result!.status.label}',
                        style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    )),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TaskStatusScreen(
                              apiService: _api,
                              initialTaskId: _result!.taskId,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.track_changes, size: 18),
                      label: const Text('查看任务状态'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
