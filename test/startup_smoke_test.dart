// 白屏排查：真实 pump 一遍启动流程，看有没有未捕获异常。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rocodesk/app/app_shell.dart';
import 'package:rocodesk/app/settings.dart';
import 'package:rocodesk/core/bloodline_ranks.dart';
import 'package:rocodesk/core/icon_assets.dart';
import 'package:rocodesk/theme/app_theme.dart';

void main() {
  testWidgets('启动加载：IconAssets.load 会不会抛', (tester) async {
    Object? caught;
    await tester.runAsync(() async {
      try {
        final icons = await IconAssets.load();
        // ignore: avoid_print
        print('IconAssets.load ok, isEmpty=${icons.isEmpty}');
      } catch (e) {
        caught = e;
      }
    });
    expect(caught, isNull, reason: 'IconAssets.load 抛了: $caught');
  });

  testWidgets('启动加载：BloodlineRanks.load 会不会抛', (tester) async {
    Object? caught;
    await tester.runAsync(() async {
      try {
        final r = await BloodlineRanks.load();
        // ignore: avoid_print
        print('BloodlineRanks.load ok, isEmpty=${r.isEmpty}');
      } catch (e) {
        caught = e;
      }
    });
    expect(caught, isNull, reason: 'BloodlineRanks.load 抛了: $caught');
  });

  testWidgets('pump 真实 AppShell（各分区同时构建，等同 IndexedStack）', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final store = SettingsStore.inMemory();

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: AppShell(store: store),
    ));

    // 让 initState 里的异步加载真的跑起来（rootBundle 在测试里可用）
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 白屏的判据：有没有未捕获异常 + 首页是否真的渲染出文字
    expect(tester.takeException(), isNull, reason: '启动期抛异常会导致整屏白');
    expect(find.byType(NavigationBar), findsOneWidget);
    // 启动落地页是「工具」，它的主卡片必须渲染出来
    expect(find.text('一图流生成阵容码'), findsOneWidget,
        reason: '启动落地页没渲染 = 白屏');
  });
}
