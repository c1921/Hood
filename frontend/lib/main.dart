import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const HoodApp());
}

class HoodApp extends StatelessWidget {
  const HoodApp({super.key});

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
      home: HomeScreen(apiService: ApiService()),
    );
  }
}
