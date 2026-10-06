/// 冒烟测试：应用能构建、主题令牌正确、关键页面能渲染。
///
/// 不测业务逻辑（那些由 `codec_golden_test.dart` 用真实数据把关），
/// 这里只保证"界面能起来、主题切换不出错"。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rocodesk/app/app_shell.dart';
import 'package:rocodesk/app/settings.dart';
import 'package:rocodesk/theme/app_theme.dart';
import 'package:rocodesk/theme/tokens.dart';

void main() {
  testWidgets('窄屏渲染底部导航，两个 tab', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = SettingsStore.inMemory();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: AppShell(store: store),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    // 首页是「工具」，一图流生成是它里面的一张卡片，不再独占 tab
    expect(find.text('工具'), findsWidgets);
    expect(find.text('一图流生成阵容码'), findsOneWidget);
    // 旧的「生成」tab 必须已经没有了
    expect(find.text('生成'), findsNothing);
  });

  testWidgets('宽屏用侧边导航，不出现底部栏', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = SettingsStore.inMemory();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: AppShell(store: store),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('工具'), findsWidgets);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('点工具卡片能打开生成页（push 路由）', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = SettingsStore.inMemory();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: AppShell(store: store),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('一图流生成阵容码'));
    await tester.pumpAndSettle();

    // 生成页有 AppBar 标题，并且能返回
    expect(find.text('一图流生成阵容码'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget,
        reason: 'push 出来的页面必须有返回按钮，否则用户回不到工具列表');
  });

  testWidgets('切到设置页能看到模型配置', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = SettingsStore.inMemory();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: AppShell(store: store),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    // 靠上的分组直接可见
    expect(find.text('模型服务'), findsOneWidget);
    expect(find.text('API Key'), findsOneWidget);

    // 下面几节需要滚动才进视口 —— 用 scrollUntilVisible 而不是断言"找不到"
    await tester.scrollUntilVisible(
      find.text('关于密钥安全'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('关于密钥安全'), findsOneWidget);
  });

  test('两套主题的语义色都齐全', () {
    for (final c in [AppColors.light, AppColors.dark]) {
      expect(c.textPrimary, isNot(c.textSecondary));
      expect(c.textSecondary, isNot(c.textTertiary));
      // 强调色不能与文字主色相同，否则按钮会糊在背景里
      expect(c.accent, isNot(c.textPrimary));
      expect(c.onAccent, isNot(c.accent));
    }
    expect(AppColors.dark.isDark, isTrue);
    expect(AppColors.light.isDark, isFalse);
  });

  test('圆角系统是固定规则，没有随手写的值', () {
    expect(AppRadii.pill, greaterThan(AppRadii.card));
    expect(AppRadii.card, greaterThan(AppRadii.input));
    expect(AppRadii.input, greaterThan(AppRadii.thumb));
  });

  test('设置默认值合理', () {
    const s = AppSettings();
    expect(s.themeMode, ThemeMode.system, reason: '默认应跟随系统');
    expect(s.provider, ModelProvider.dashscope);
    expect(s.hasApiKey, isFalse);
    expect(s.isReady, isFalse, reason: '没填 Key 时不应认为已就绪');
    expect(s.effectiveModel, isNotEmpty, reason: '应当回落到服务商默认模型');
  });

  test('主题模式能正确持久化与还原', () async {
    // 用内存实现验证读写逻辑，不触碰平台通道
    final store = SettingsStore.inMemory();
    expect(store.themeMode, ThemeMode.system);

    await store.setThemeMode(ThemeMode.dark);
    expect(store.themeMode, ThemeMode.dark);

    await store.setApiKey('  sk-test  ');
    expect(store.apiKey, 'sk-test', reason: '应当去掉首尾空白');
    expect(store.isReady, isTrue);
    expect(store.settings.effectiveBaseUrl, isNotEmpty);

    await store.clearApiKey();
    expect(store.isReady, isFalse);
  });
}
