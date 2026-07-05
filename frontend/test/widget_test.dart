import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const HoodApp());
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
