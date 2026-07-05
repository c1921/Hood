import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/main.dart';

void main() {
  setUp(() {
    // 为测试初始化 SharedPreferences 模拟数据
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const HoodApp());
    // 等待 HoodApp 异步初始化完成（PreferencesService.init）
    await tester.pumpAndSettle();

    // 验证首页标题
    expect(find.text('Hood'), findsOneWidget);
    // 验证功能入口存在
    expect(find.text('节点信息'), findsOneWidget);
    expect(find.text('运行流水线'), findsOneWidget);
    expect(find.text('VAE 解码'), findsOneWidget);
    expect(find.text('任务状态'), findsOneWidget);
  });
}
