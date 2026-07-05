import 'package:shared_preferences/shared_preferences.dart';

/// 持久化用户偏好 — 服务器地址、最近使用的 webapp ID 等
class PreferencesService {
  static const _keyServerUrl = 'server_url';
  static const _keyRecentWebappIds = 'recent_webapp_ids';
  static const _kMaxRecentIds = 10;

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  SharedPreferences get _p {
    if (_prefs == null) {
      throw StateError('PreferencesService not initialized — call init() first');
    }
    return _prefs!;
  }

  // ── 服务器地址 ────────────────────────────────────

  String get serverUrl => _p.getString(_keyServerUrl) ?? 'http://localhost:8000';

  Future<bool> setServerUrl(String url) => _p.setString(_keyServerUrl, url);

  // ── 最近使用的 webapp ID ─────────────────────────

  List<String> get recentWebappIds =>
      _p.getStringList(_keyRecentWebappIds) ?? [];

  /// 记录一个 webapp ID 到历史列表（去重 + 容量限制）
  Future<void> recordWebappId(String id) {
    final ids = recentWebappIds;
    ids.remove(id); // 去重
    ids.insert(0, id); // 最新放最前
    if (ids.length > _kMaxRecentIds) {
      ids.removeRange(_kMaxRecentIds, ids.length);
    }
    return _p.setStringList(_keyRecentWebappIds, ids);
  }

  /// 移除一个 webapp ID
  Future<void> removeWebappId(String id) {
    final ids = recentWebappIds;
    ids.remove(id);
    return _p.setStringList(_keyRecentWebappIds, ids);
  }

  /// 清空所有 webapp ID
  Future<void> clearWebappIds() =>
      _p.setStringList(_keyRecentWebappIds, []);
}
