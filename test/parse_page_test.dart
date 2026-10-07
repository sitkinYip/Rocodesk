/// 阵容码解析页的端到端测试。
///
/// 逻辑层（解码 -> 界面模型）已经在 `parse_test.dart` 里逐字段验证过了，
/// 这里只测**界面接线**：
///   * 粘贴码能解析出结果
///   * 坏码给出可读的错误而不是崩
///   * 改了输入会清掉旧结果（否则用户以为旧结果对应新码）
///   * 解析结果里能直接改，改完重新生成码
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'dart:io';

import 'package:rocodesk/core/bloodline_ranks.dart';
import 'package:rocodesk/core/codec_tables.dart';
import 'package:rocodesk/core/icon_assets.dart';
import 'package:rocodesk/features/parser/parse_page.dart';
import 'package:rocodesk/theme/app_theme.dart';

/// 夹具里的第一条真实码（6 只 / 进化之力）。
const kRealCode =
    'B~Gzg~~~H~V~QBPBUbDCa~ayIs~a0bQ~bC_S~31~~~I~c~BQBPBTbFcK~a23C~a2y0~ax-E~u8~~~M~Y~BPBRBUa7qY~bDBy~bAls~a0ao~wF~~~G~C~BSBPBTbAkI~a20s~a230~a22G~yQ~~~M~C~BQBPBUa5PY~bPL6~bPOk~bPNe~vD~~~T~V~BQBPBUayI2~ayGq~ayAu~bY86~ZZH~FA~A~A~A~A~A~A~A~A~A~A~A~';

Map<String, dynamic> _read(String p) =>
    jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;

/// 直接读文件构造数据表 —— 绕开 rootBundle 与平台通道，测试才跑得动。
CodecTables _tables() => CodecTables.fromMaps(
      pets: _read('assets/data/pets.json'),
      skills: _read('assets/data/skills.json'),
      natures: _read('assets/data/natures.json'),
      codec: _read('assets/data/codec.json'),
    );

Future<void> _pump(WidgetTester tester) async {
  // 视口给高一点：默认 600px 高的情况下，结果列表与选择器容器都会
  // 被挤到很窄，tap 会落到错误的控件上（测试仍可能通过，但不可信）。
  tester.view.physicalSize = const Size(420 * 2, 1400 * 2);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: ParsePage(
      tables: _tables(),
      icons: IconAssets.empty(),
      bloodlineRanks: BloodlineRanks.empty(),
    ),
  ));

  // 等资料表加载完（页面 initState 里异步载入）
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('初始是空态，说明这个页面能做什么', (tester) async {
    await _pump(tester);
    expect(find.text('粘贴阵容码'), findsOneWidget);
    expect(find.text('还没有解析结果'), findsOneWidget);
    expect(find.text('解析'), findsWidgets);
  });

  testWidgets('粘贴真实码能解析出 6 只', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField).first, kRealCode);
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, '解析'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // 结果区出现，且是完整的 6 只
    expect(find.text('解析结果'), findsOneWidget);
    expect(find.text('共 6 只'), findsOneWidget);

    // 夹具首条码里的几只（名字来自数据表反查）
    expect(find.text('卡瓦重（雪山附近的样子）'), findsOneWidget);
    expect(find.text('爆焰喷喷'), findsOneWidget);
    expect(find.text('进化之力'), findsWidgets);
  });

  testWidgets('坏码给可读错误，不崩', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField).first, '这不是一个阵容码');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '解析'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '坏输入不该抛到界面');
    expect(find.text('解析结果'), findsNothing);
    // 错误提示里应当有可读内容
    expect(find.textContaining('阵容码'), findsWidgets);
  });

  testWidgets('空输入给提示而不是静默无反应', (tester) async {
    await _pump(tester);
    await tester.tap(find.widgetWithText(FilledButton, '解析'));
    await tester.pumpAndSettle();

    expect(find.textContaining('请先粘贴'), findsOneWidget);
  });

  testWidgets('改了输入会清掉上一次的结果', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField).first, kRealCode);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '解析'));
    await tester.pumpAndSettle();
    expect(find.text('解析结果'), findsOneWidget);

    // 改动输入 -> 旧结果必须消失，否则用户以为它对应新的码
    await tester.enterText(find.byType(TextField).first, '${kRealCode}X');
    await tester.pump();

    expect(find.text('解析结果'), findsNothing,
        reason: '留着旧结果会让人以为它对应新输入');
  });

  testWidgets('解析结果里能改血脉并重新出码', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField).first, kRealCode);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '解析'));
    await tester.pumpAndSettle();

    // 首只的血脉是「冰」。结果页很长，它可能在视口外 ——
    // 先滚动到可见再点，否则 tap 会落到别的控件上（点不到也不报错）。
    final ice = find.text('冰血脉').first;
    await tester.scrollUntilVisible(
      ice,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(ice);
    await tester.pumpAndSettle();
    expect(find.text('选择血脉'), findsOneWidget);

    await tester.tap(find.text('首领').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('首领血脉'), findsWidgets,
        reason: '改完血脉后标签应当变成「首领血脉」');
  });
}
