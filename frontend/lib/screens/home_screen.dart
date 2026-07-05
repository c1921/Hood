import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/preferences_service.dart';
import '../models/api_models.dart';
import 'node_info_screen.dart';
import 'run_pipeline_screen.dart';
import 'decode_screen.dart';
import 'task_status_screen.dart';

class HomeScreen extends StatefulWidget {
  final ApiService apiService;
  final PreferencesService prefs;

  const HomeScreen({
    super.key,
    required this.apiService,
    required this.prefs,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HealthResponse? _health;
  bool _loadingHealth = false;
  String? _healthError;

  @override
  void initState() {
    super.initState();
    _checkHealth();
  }

  Future<void> _checkHealth() async {
    setState(() {
      _loadingHealth = true;
      _healthError = null;
    });
    try {
      final health = await widget.apiService.health();
      if (mounted) {
        setState(() {
          _health = health;
          _loadingHealth = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _health = null;
          _healthError = e.toString();
          _loadingHealth = false;
        });
      }
    }
  }

  Future<void> _showServerSettings() async {
    final controller = TextEditingController(text: widget.apiService.baseUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('服务器设置'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '服务器地址',
            hintText: 'http://localhost:8000',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      widget.apiService.updateBaseUrl(result);
      await widget.prefs.setServerUrl(result);
      _checkHealth();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hood'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '服务器设置',
            onPressed: _showServerSettings,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _checkHealth,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildServerStatusCard(theme),
            const SizedBox(height: 24),
            Text('功能入口', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildFeatureGrid(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildServerStatusCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _health != null ? Icons.check_circle : Icons.error_outline,
                  color: _health != null
                      ? Colors.green
                      : (_healthError != null ? Colors.red : Colors.grey),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text('服务器状态', style: theme.textTheme.titleSmall),
                const Spacer(),
                if (_loadingHealth)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: '刷新',
                    onPressed: _checkHealth,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.apiService.baseUrl,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            if (_health != null)
              Text(
                'v${_health!.version} — ${_health!.status}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.green.shade700,
                ),
              )
            else if (_healthError != null)
              Text(
                _healthError!,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
              )
            else if (_loadingHealth)
              const Text('正在连接...')
            else
              const Text('未检测'),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureGrid(ThemeData theme) {
    final features = [
      _FeatureItem(
        icon: Icons.list_alt_rounded,
        label: '节点信息',
        desc: '查看 RunningHub 应用的节点列表',
        color: Colors.indigo,
        screen: NodeInfoScreen(apiService: widget.apiService),
      ),
      _FeatureItem(
        icon: Icons.play_circle_fill_rounded,
        label: '运行流水线',
        desc: '提交云端推理 → VAE 解码完整流程',
        color: Colors.deepOrange,
        screen: RunPipelineScreen(
          apiService: widget.apiService,
          prefs: widget.prefs,
        ),
      ),
      _FeatureItem(
        icon: Icons.image_rounded,
        label: 'VAE 解码',
        desc: '独立解码 .latent 文件为图片',
        color: Colors.teal,
        screen: DecodeScreen(apiService: widget.apiService),
      ),
      _FeatureItem(
        icon: Icons.pending_actions_rounded,
        label: '任务状态',
        desc: '查询异步任务的执行进度',
        color: Colors.blue,
        screen: TaskStatusScreen(apiService: widget.apiService),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.95,
      ),
      itemCount: features.length,
      itemBuilder: (context, index) {
        final f = features[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => f.screen),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(f.icon, color: f.color, size: 32),
                  const Spacer(),
                  Text(f.label, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    f.desc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FeatureItem {
  final IconData icon;
  final String label;
  final String desc;
  final Color color;
  final Widget screen;

  const _FeatureItem({
    required this.icon,
    required this.label,
    required this.desc,
    required this.color,
    required this.screen,
  });
}
