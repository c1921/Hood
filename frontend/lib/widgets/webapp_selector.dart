import 'package:flutter/material.dart';
import '../services/preferences_service.dart';

/// 可复用的 Webapp ID 选择/输入组件
///
/// - 输入新 ID 后自动保存到历史记录
/// - 点击下拉可快速选择最近使用的 ID
/// - 支持清除单个历史项
class WebappSelector extends StatefulWidget {
  final PreferencesService prefs;
  final TextEditingController controller;
  final ValueChanged<String>? onSubmitted;

  const WebappSelector({
    super.key,
    required this.prefs,
    required this.controller,
    this.onSubmitted,
  });

  @override
  State<WebappSelector> createState() => _WebappSelectorState();
}

class _WebappSelectorState extends State<WebappSelector> {
  List<String> _recentIds = [];
  final _focusNode = FocusNode();
  bool _showDropdown = false;

  @override
  void initState() {
    super.initState();
    _recentIds = widget.prefs.recentWebappIds;
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _showDropdown = _focusNode.hasFocus && _recentIds.isNotEmpty;
    });
  }

  Future<void> _selectId(String id) async {
    widget.controller.text = id;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: id.length),
    );
    await widget.prefs.recordWebappId(id);
    setState(() {
      _recentIds = widget.prefs.recentWebappIds;
      _showDropdown = false;
    });
    _focusNode.unfocus();
    widget.onSubmitted?.call(id);
  }

  Future<void> _removeId(String id) async {
    await widget.prefs.removeWebappId(id);
    setState(() {
      _recentIds = widget.prefs.recentWebappIds;
    });
  }

  Future<void> _onFieldSubmitted(String value) async {
    final id = value.trim();
    if (id.isNotEmpty) {
      await widget.prefs.recordWebappId(id);
      setState(() {
        _recentIds = widget.prefs.recentWebappIds;
      });
      widget.onSubmitted?.call(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            labelText: 'Webapp ID',
            hintText: '1937084629516193794',
            border: const OutlineInputBorder(),
            suffixIcon: _recentIds.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.history),
                    tooltip: '最近使用',
                    onPressed: () {
                      setState(() => _showDropdown = !_showDropdown);
                    },
                  )
                : null,
          ),
          textInputAction: TextInputAction.go,
          onSubmitted: _onFieldSubmitted,
          onTap: () {
            if (_recentIds.isNotEmpty) {
              setState(() => _showDropdown = true);
            }
          },
        ),
        if (_showDropdown) _buildDropdown(),
      ],
    );
  }

  Widget _buildDropdown() {
    return Card(
      margin: const EdgeInsets.only(top: 4),
      elevation: 4,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: _recentIds.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final id = _recentIds[index];
          return ListTile(
            dense: true,
            leading: const Icon(Icons.history, size: 18),
            title: Text(id, style: const TextStyle(fontSize: 14)),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => _removeId(id),
              visualDensity: VisualDensity.compact,
            ),
            onTap: () => _selectId(id),
          );
        },
      ),
    );
  }
}
