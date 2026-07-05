import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/api_models.dart';
import 'task_status_screen.dart';

class RunPipelineScreen extends StatefulWidget {
  final ApiService? apiService;

  const RunPipelineScreen({super.key, this.apiService});

  @override
  State<RunPipelineScreen> createState() => _RunPipelineScreenState();
}

class _RunPipelineScreenState extends State<RunPipelineScreen> {
  late final ApiService _api;
  final _webappIdController = TextEditingController();
  final _modifications = <_ModificationEntry>[];
  bool _submitting = false;
  TaskInfo? _result;

  @override
  void initState() {
    super.initState();
    _api = widget.apiService ?? ApiService();
  }

  @override
  void dispose() {
    _webappIdController.dispose();
    for (final m in _modifications) {
      m.nodeId.dispose();
      m.fieldName.dispose();
      m.fieldValue.dispose();
      m.filePath.dispose();
    }
    super.dispose();
  }

  void _addModification() {
    setState(() {
      _modifications.add(_ModificationEntry());
    });
  }

  void _removeModification(int index) {
    final m = _modifications.removeAt(index);
    m.nodeId.dispose();
    m.fieldName.dispose();
    m.fieldValue.dispose();
    m.filePath.dispose();
    setState(() {});
  }

  Future<void> _submit() async {
    final webappId = _webappIdController.text.trim();
    if (webappId.isEmpty) {
      _showSnack('请输入 Webapp ID');
      return;
    }

    final mods = <Modification>[];
    for (final m in _modifications) {
      final nodeId = m.nodeId.text.trim();
      final fieldName = m.fieldName.text.trim();
      if (nodeId.isEmpty && fieldName.isEmpty) continue; // 跳过空行
      if (nodeId.isEmpty || fieldName.isEmpty) {
        _showSnack('请补全所有修改项的节点 ID 和字段名');
        return;
      }
      mods.add(Modification(
        nodeId: nodeId,
        fieldName: fieldName,
        fieldValue: m.fieldValue.text.trim().isEmpty
            ? null
            : m.fieldValue.text.trim(),
        filePath: m.filePath.text.trim().isEmpty
            ? null
            : m.filePath.text.trim(),
      ));
    }

    if (mods.isEmpty) {
      _showSnack('请至少添加一个修改项');
      return;
    }

    setState(() {
      _submitting = true;
      _result = null;
    });

    try {
      final task = await _api.runPipeline(webappId: webappId, modifications: mods);
      if (mounted) {
        setState(() {
          _result = task;
          _submitting = false;
        });
        _showSnack('任务已提交: ${task.taskId}');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _submitting = false; });
      _showSnack('提交失败: ${e.message}');
    } catch (e) {
      if (mounted) setState(() { _submitting = false; });
      _showSnack('错误: $e');
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
      appBar: AppBar(title: const Text('运行流水线')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Webapp ID ──
          TextField(
            controller: _webappIdController,
            decoration: const InputDecoration(
              labelText: 'Webapp ID',
              hintText: '1937084629516193794',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),

          // ── 修改项标题 ──
          Row(
            children: [
              Text('节点修改项', style: theme.textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                onPressed: _addModification,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
              ),
            ],
          ),

          // ── 修改项列表 ──
          if (_modifications.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    '暂无修改项，点击"添加"按钮',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          for (int i = 0; i < _modifications.length; i++) ...[
            _buildModificationCard(i, theme),
            const SizedBox(height: 8),
          ],

          const SizedBox(height: 16),

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
                : const Icon(Icons.send),
            label: Text(_submitting ? '提交中...' : '提交流水线'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),

          // ── 提交结果 ──
          if (_result != null) ...[
            const SizedBox(height: 16),
            _buildResultCard(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildModificationCard(int index, ThemeData theme) {
    final m = _modifications[index];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('修改 #${index + 1}',
                    style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                )),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => _removeModification(index),
                  visualDensity: VisualDensity.compact,
                  color: Colors.red,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: m.nodeId,
                    decoration: const InputDecoration(
                      labelText: '节点 ID',
                      hintText: '22',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: m.fieldName,
                    decoration: const InputDecoration(
                      labelText: '字段名',
                      hintText: 'positive',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: m.fieldValue,
              decoration: const InputDecoration(
                labelText: '字段值 (文本)',
                hintText: '一只可爱的猫',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: m.filePath,
              decoration: const InputDecoration(
                labelText: '文件路径 (图片/音频/视频)',
                hintText: 'D:/images/cat.jpg',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(ThemeData theme) {
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle,
                    color: theme.colorScheme.onPrimaryContainer, size: 20),
                const SizedBox(width: 8),
                Text('任务已提交',
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
    );
  }
}

class _ModificationEntry {
  final nodeId = TextEditingController();
  final fieldName = TextEditingController();
  final fieldValue = TextEditingController();
  final filePath = TextEditingController();
}
