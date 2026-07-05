import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/preferences_service.dart';
import '../models/api_models.dart';
import '../widgets/webapp_selector.dart';
import 'task_status_screen.dart';

class RunPipelineScreen extends StatefulWidget {
  final ApiService apiService;
  final PreferencesService prefs;

  const RunPipelineScreen({
    super.key,
    required this.apiService,
    required this.prefs,
  });

  @override
  State<RunPipelineScreen> createState() => _RunPipelineScreenState();
}

class _RunPipelineScreenState extends State<RunPipelineScreen> {
  final _webappIdController = TextEditingController();
  bool _loadingNodes = false;
  String? _nodesError;
  List<NodeInfo>? _nodes;
  /// 每个节点对应的修改控制器
  final _modControllers = <_NodeModCtrl>[];
  bool _submitting = false;
  TaskInfo? _submitResult;

  @override
  void dispose() {
    _webappIdController.dispose();
    for (final c in _modControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _onWebappIdSelected(String id) async {
    setState(() {
      _loadingNodes = true;
      _nodesError = null;
      _nodes = null;
      _submitResult = null;
      // 清空旧控制器
      for (final c in _modControllers) {
        c.dispose();
      }
      _modControllers.clear();
    });

    try {
      final info = await widget.apiService.getNodeInfo(id);
      if (mounted) {
        setState(() {
          _nodes = info.data;
          _loadingNodes = false;
          // 为每个节点创建控制器
          for (final node in info.data) {
            _modControllers.add(_NodeModCtrl(
              fieldValue: node.fieldValue ?? '',
            ));
          }
          if (info.data.isEmpty) {
            _nodesError = '该应用没有可编辑的节点';
          }
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _nodesError = e.message;
          _loadingNodes = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _nodesError = e.toString();
          _loadingNodes = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    final webappId = _webappIdController.text.trim();
    if (webappId.isEmpty || _nodes == null) return;

    final modifications = <Modification>[];
    for (int i = 0; i < _nodes!.length; i++) {
      final node = _nodes![i];
      final ctrl = _modControllers[i];
      final newValue = ctrl.fieldValue.text.trim();

      // 有变化的字段才提交
      if (newValue != (node.fieldValue ?? '')) {
        modifications.add(Modification(
          nodeId: node.nodeId,
          fieldName: node.fieldName,
          fieldValue: newValue.isEmpty ? null : newValue,
        ));
      }
    }

    if (modifications.isEmpty) {
      _showSnack('没有需要提交的修改');
      return;
    }

    setState(() {
      _submitting = true;
      _submitResult = null;
    });

    try {
      final task = await widget.apiService.runPipeline(
        webappId: webappId,
        modifications: modifications,
      );
      if (mounted) {
        setState(() {
          _submitResult = task;
          _submitting = false;
        });
        _showSnack('流水线任务已提交');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _submitting = false);
      _showSnack('提交失败: ${e.message}');
    } catch (e) {
      if (mounted) setState(() => _submitting = false);
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
          // ── Webapp ID 选择器 ──
          Text('选择 AI 应用', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: WebappSelector(
                  prefs: widget.prefs,
                  controller: _webappIdController,
                  onSubmitted: _onWebappIdSelected,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _loadingNodes
                    ? null
                    : () => _onWebappIdSelected(_webappIdController.text.trim()),
                icon: _loadingNodes
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.search),
                label: Text(_loadingNodes ? '加载中' : '查询'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── 加载节点信息 ──
          if (_loadingNodes) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('正在获取节点信息...'),
                  ],
                ),
              ),
            ),
          ],

          // ── 错误提示 ──
          if (_nodesError != null)
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
                      child: Text(_nodesError!, style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      )),
                    ),
                  ],
                ),
              ),
            ),

          // ── 节点编辑列表 ──
          if (_nodes != null && _nodesError == null) ...[
            Row(
              children: [
                Text('节点参数', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text('${_nodes!.length} 个节点', style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
              ],
            ),
            const SizedBox(height: 8),
            ...List.generate(_nodes!.length, (i) => _buildNodeCard(i, theme)),
            const SizedBox(height: 16),

            // ── 提交按钮 ──
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: Text(_submitting ? '提交中...' : '提交流水线'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],

          // ── 提交结果 ──
          if (_submitResult != null) ...[
            const SizedBox(height: 16),
            _buildResultCard(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildNodeCard(int index, ThemeData theme) {
    final node = _nodes![index];
    final ctrl = _modControllers[index];
    final isFile = node.fieldType == 'IMAGE' ||
        node.fieldType == 'AUDIO' ||
        node.fieldType == 'VIDEO';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 节点头部 ──
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _typeColor(node.fieldType).withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    node.fieldType,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _typeColor(node.fieldType),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('节点 #${node.nodeId}',
                    style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),

            // ── 字段名 ──
            Text(node.fieldName,
                style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
            const SizedBox(height: 6),

            // ── 始终渲染可编辑 TextField ──
            TextField(
              controller: ctrl.fieldValue,
              decoration: InputDecoration(
                labelText: isFile ? '文件路径' : '字段值',
                hintText: isFile
                    ? 'D:/images/example.jpg'
                    : (node.fieldValue ?? '输入值...'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: node.fieldType == 'PROMPT' ? 3 : 1,
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
            Text('Task ID: ${_submitResult!.taskId}',
                style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            )),
            const SizedBox(height: 4),
            Text('状态: ${_submitResult!.status.label}',
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
                      apiService: widget.apiService,
                      initialTaskId: _submitResult!.taskId,
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

  Color _typeColor(String type) {
    switch (type) {
      case 'TEXT':
      case 'PROMPT':
        return Colors.blue;
      case 'IMAGE':
        return Colors.green;
      case 'AUDIO':
        return Colors.orange;
      case 'VIDEO':
        return Colors.red;
      case 'NUMBER':
        return Colors.purple;
      case 'SELECT':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }
}

/// 节点修改的控制器集合
class _NodeModCtrl {
  final TextEditingController fieldValue;

  _NodeModCtrl({String fieldValue = ''})
      : fieldValue = TextEditingController(text: fieldValue);

  void dispose() {
    fieldValue.dispose();
  }
}
