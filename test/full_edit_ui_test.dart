/// 「整队完全可编辑」的界面测试。
///
/// 逻辑层已在 `full_edit_test.dart` 验证过（改了之后码真的变），
/// 这里只测**界面接线**：那些东西是不是真的能点、点了会不会走对回调。
///
/// 为什么值得单独测：识别页和解析页都给了一堆回调，接错一个的表现是
/// "点了没反应" —— 用户会以为功能没做，而不是发现 bug。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rocodesk/core/bloodline_ranks.dart';
import 'package:rocodesk/core/codec_tables.dart';
import 'package:rocodesk/core/icon_assets.dart';
import 'package:rocodesk/features/parser/parse_page.dart';
import 'package:rocodesk/theme/app_theme.dart';

const kRealCode =
    'B~Gzg~~~H~V~QBPBUbDCa~ayIs~a0bQ~bC_S~31~~~I~c~BQBPBTbFcK~a23C~a2y0~ax-E~u8~~~M~Y~BPBRBUa7qY~bDBy~bAls~a0ao~wF~~~G~C~BSBPBTbAkI~a20s~a230~a22G~yQ~~~M~C~BQBPBUa5PY~bPL6~bPOk~bPNe~vD~~~T~V~QBPBUayI2~ayGq~ayAu~bY86~ZZH~FA~A~A~A~A~A~A~A~A~A~A~A~';

Map<String, dynamic> _read(String p) =>
    jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;

CodecTables _tables() => CodecTables.fromMaps(
      pets: _read('assets/data/pets.json'),
      skills: _read('assets/data/skills.json'),
      natures: _read('assets/data/natures.json'),
      codec: _read('assets/data/codec.json'),
      learnsets: _read('assets/data/learnsets.json'),
      variantTypes: _read('assets/data/variant_types.json'),
    );

/// 解析出结果，返回后停在结果页。
Future<void> _parse(WidgetTester tester) async {
  // 视口给足高度：结果页很长，默认 600px 高会让 tap 落到别的控件上
  tester.view.physicalSize = const Size(440 * 2, 1600 * 2);
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
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField).first, kRealCode);
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, '解析'));
  await tester.pumpAndSettle();
}

/// 滚到可见再点 —— 结果页长，直接 tap 会落在视口外。
Future<void> _tapScrolled(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('每一项都能点开', () {
    testWidgets('点精灵名能打开换精灵（623 个码都能选）', (tester) async {
      await _parse(tester);
      await _tapScrolled(tester, find.text('卡瓦重（雪山附近的样子）').first);

      expect(find.text('换精灵'), findsOneWidget);
      // 注意是 623（tables.petNames 的条目数），不是 542 ——
      // 542 是"有头像/有系别数据"的数量，那是另一回事。
      expect(find.textContaining('共 623 只可选'), findsOneWidget);
      // 搜索框在，且能筛
      await tester.enterText(find.byType(TextField).last, '雪影');
      await tester.pumpAndSettle();
      expect(find.text('雪影娃娃'), findsWidgets);
    });

    testWidgets('换精灵后名字与系别都跟着变', (tester) async {
      await _parse(tester);
      await _tapScrolled(tester, find.text('卡瓦重（雪山附近的样子）').first);
      await tester.enterText(find.byType(TextField).last, '寂灭骨龙');
      await tester.pumpAndSettle();
      await tester.tap(find.text('寂灭骨龙').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // 名字换成新的了
      expect(find.text('寂灭骨龙'), findsWidgets);
      // 系别也跟着换成骨龙的（龙 / 幽），不再是卡瓦重的草/冰
      expect(find.text('幽'), findsWidgets,
          reason: '换了精灵，系别要跟着换，否则是误导');
    });

    testWidgets('点性格能改', (tester) async {
      await _parse(tester);
      // 第一只的性格标签
      final nature = find.textContaining('性格').first;
      await _tapScrolled(tester, nature);

      expect(find.text('选择性格'), findsOneWidget);
      await tester.tap(find.text('开朗').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('点个体资质能改（6 个维度选 3 个）', (tester) async {
      await _parse(tester);
      await _tapScrolled(tester, find.textContaining('资质').first);

      expect(find.text('选择个体资质'), findsOneWidget);
      expect(find.text('第一项'), findsOneWidget);
      expect(find.text('第二项'), findsOneWidget);
      expect(find.text('第三项'), findsOneWidget);
      // 6 个维度都在
      for (final d in const ['生命', '物攻', '魔攻', '物防', '魔防', '速度']) {
        expect(find.text(d), findsWidgets, reason: d);
      }
    });

    testWidgets('个体资质必须选满三项才让确定', (tester) async {
      await _parse(tester);
      await _tapScrolled(tester, find.textContaining('资质').first);

      // 直接点确定：当前已是 3 项，所以应当能提交（不报错）
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('技能：每一个都能点，不只是可疑的', () {
    testWidgets('点一个正常技能也能打开选择面板', (tester) async {
      await _parse(tester);
      // 夹具里第一只的技能之一是「晒太阳」——它不是可疑项
      await _tapScrolled(tester, find.text('晒太阳').first);

      expect(find.text('修正技能'), findsOneWidget);
      expect(find.text('搜索或直接输入技能名'), findsOneWidget);
    });

    testWidgets('有「它能学的 / 全部技能」范围切换', (tester) async {
      await _parse(tester);
      await _tapScrolled(tester, find.text('晒太阳').first);

      expect(find.text('它能学的'), findsOneWidget);
      expect(find.text('全部技能'), findsOneWidget);
    });

    testWidgets('切到「全部技能」后能搜到别的技能', (tester) async {
      await _parse(tester);
      await _tapScrolled(tester, find.text('晒太阳').first);

      await tester.tap(find.text('全部技能'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '暴风雪');
      await tester.pumpAndSettle();
      expect(find.textContaining('匹配「暴风雪」'), findsOneWidget);
    });

    testWidgets('空槽有「加技能」入口 —— 删掉后还能加回来', (tester) async {
      await _parse(tester);
      // 夹具每只都是 4 个技能，所以先删一个再验证入口出现
      await _tapScrolled(tester, find.text('晒太阳').first);
      await tester.tap(find.text('清空这个技能'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('加技能'), findsWidgets,
          reason: '空槽必须有添加入口，否则删了就加不回来');
    });

    testWidgets('抽屉不再截断候选 —— 排序靠后的技能也能滚到', (tester) async {
      // 用户报的问题：雪影娃娃能学 50 个，但「贪婪」按名字排序在第 40 位，
      // 面板以前只建前 24 个，所以它虽然在数据里却**完全看不到**。
      await _parse(tester);

      // 先把第 1 只换成雪影娃娃（它的技能池里有贪婪）
      await _tapScrolled(tester, find.text('卡瓦重（雪山附近的样子）').first);
      await tester.enterText(find.byType(TextField).last, '雪影娃娃');
      await tester.pumpAndSettle();
      await tester.tap(find.text('雪影娃娃').last);
      await tester.pumpAndSettle();

      // 换精灵后技能被清空，出现空槽 -> 点「加技能」打开面板
      await _tapScrolled(tester, find.text('加技能').first);
      expect(find.text('修正技能'), findsOneWidget);

      // 面板应当报告完整数量（50 个），而不是"前 24 个"
      expect(find.textContaining('它能学的 50 个'), findsOneWidget,
          reason: '要显示真实数量，让用户知道列表没被截断');

      // 「贪婪」在网格里。它在排序后第 40 位，需要滚动才可见 ——
      // 用 scrollUntilVisible 证明它**能被滚到**（懒加载会构建到它）。
      final greedy = find.text('贪婪');
      await tester.scrollUntilVisible(
        greedy,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(greedy, findsWidgets, reason: '贪婪必须能被滚到，否则用户永远配不出这个技能');
    });
  });
}
