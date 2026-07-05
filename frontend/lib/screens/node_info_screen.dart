import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/api_models.dart';

class NodeInfoScreen extends StatefulWidget {
  final ApiService? apiService;

  const NodeInfoScreen({super.key, this.apiService});

  @override
  State<NodeInfoScreen> createState() => _NodeInfoScreenState();
}

class _NodeInfoScreenState extends State<NodeInfoScreen> {
  late final ApiService _api;
  final _webappIdController = TextEditingController();
  List<NodeInfo>? _nodes;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = widget.apiService ?? ApiService();
  }

  @override
  void dispose() {
    _webappIdController.dispose();
    super.dispose();
  }

  Future<void> _fetchNodeInfo() async {
    final id = _webappIdController.text.trim();
    if (id.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _nodes = null;
    });

    try {
      final info = await _api.getNodeInfo(id);
      if (mounted) {
        setState(() {
          _nodes = info.data;
          _loading = false;
          if (info.data.isEmpty) {
            _error = '未获取到节点信息，请检查 webappId 是否正确';
          }
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('节点信息')),
      body: Column(
        children: [
          // ── 输入区域 ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _webappIdController,
                    decoration: const InputDecoration(
                      labelText: 'Webapp ID',
                      hintText: '1937084629516193794',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _fetchNodeInfo(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _loading ? null : _fetchNodeInfo,
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
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          if (_nodes != null) _buildNodeList(theme),
        ],
      ),
    );
  }

  Widget _buildNodeList(ThemeData theme) {
    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _nodes!.length,
        itemBuilder: (context, index) {
          final node = _nodes![index];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
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
                  _infoRow('字段名', node.fieldName, theme),
                  if (node.fieldValue != null && node.fieldValue!.isNotEmpty)
                    _infoRow('当前值', node.fieldValue!, theme),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _infoRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'TEXT':
        return Colors.blue;
      case 'IMAGE':
        return Colors.green;
      case 'AUDIO':
        return Colors.orange;
      case 'VIDEO':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
