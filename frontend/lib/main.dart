import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'services/preferences_service.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HoodApp());
}

class HoodApp extends StatefulWidget {
  const HoodApp({super.key});

  @override
  State<HoodApp> createState() => _HoodAppState();
}

class _HoodAppState extends State<HoodApp> {
  final _prefs = PreferencesService();
  ApiService? _apiService;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _prefs.init();
    final url = _prefs.serverUrl;
    if (mounted) {
      setState(() {
        _apiService = ApiService(baseUrl: url);
        _ready = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hood',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: _ready
          ? HomeScreen(apiService: _apiService!, prefs: _prefs)
          : const _SplashScreen(),
    );
  }
}

/// 初始化前的启动画面
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Hood',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
