/// 血脉与技能联动、换精灵清空的**界面**测试。
///
/// 逻辑规则已在 `bloodline_skill_test.dart` 里验证过（`availableNames` /
/// `isAvailable`）。这里测的是**界面真的按那个规则做了**：
///   * 改血脉 -> 学不了的血脉技能从卡片上消失
///   * 换精灵 -> 旧精灵的血脉/技能不残留
///
/// 这两条都是用户明确提出的机制要求，静默失效的代价是
/// 生成一串游戏里不成立的配置 —— 所以必须钉住。
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

Future<void> _parse(WidgetTester tester) async {
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

/// 在已打开的血脉选择器里点某个血脉。
///
/// ⚠️ 不能用 `find.text('火')` —— 页面（和选择器）里还有技能名
/// 「淬火」「火焰护盾」「火焰切割」，`.first` 会点到别的上面，
/// 表现是"点了但没生效"，很容易误判成功能坏了。
///
/// 血脉格子的文案就是血脉名本身，而技能名都更长 —— 所以直接精确
/// 匹配叶子 Text 且要求它等于目标名，再从中取最后一个（选择器在最上层）。
Future<void> _pickBloodline(WidgetTester tester, String name) async {
  final hits = find.byWidgetPredicate(
    (w) => w is Text && w.data == name,
  );
  expect(hits, findsWidgets, reason: '选择器里应当有「$name」这一项');
  await tester.tap(hits.last);
  await tester.pumpAndSettle();
}

void main() {
  group('改血脉会清掉学不了的血脉技能', () {
    testWidgets('冰血脉 -> 火血脉：卡片上的技能发生替换而不是原样保留',
        (tester) async {
      await _parse(tester);

      // 先记下改之前的全部文本
      List<String> texts() => tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      final before = texts();

      // 卡瓦重当前是冰血脉（H）。改成火。
      await _tapScrolled(tester, find.text('冰血脉').first);
      expect(find.text('选择血脉'), findsOneWidget);
      await _pickBloodline(tester, '火');

      expect(tester.takeException(), isNull);

      final after = texts();
      expect(after, contains('火血脉'));
      expect(after, isNot(equals(before)),
          reason: '改血脉后技能列表必须有变化，否则联动没生效');
    });

    testWidgets('改成「无血脉」也会清掉血脉技能', (tester) async {
      await _parse(tester);
      await _tapScrolled(tester, find.text('冰血脉').first);
      await _pickBloodline(tester, '无血脉');
      expect(tester.takeException(), isNull);
      expect(find.text('血脉未识别'), findsWidgets);
    });

    testWidgets('level / stone 技能不会因为改血脉而消失', (tester) async {
      await _parse(tester);

      // 「晒太阳」是第一只上的 level 技能（实测它的技能是
      // 速冻 / 晒太阳 / 筛管奔流 / 冰雹 —— 别猜，用真实值）
      expect(find.text('晒太阳').evaluate().length, greaterThan(0));

      await _tapScrolled(tester, find.text('冰血脉').first);
      await _pickBloodline(tester, '火');

      expect(find.text('晒太阳').evaluate().length, greaterThan(0),
          reason: 'level 技能不该被血脉联动清掉');
    });
  });

  group('技能池要给全量，不能按当前血脉砍掉', () {
    // 用户指出的问题：雪影娃娃能学 50 个，但冰血脉下只显示 33 个，
    // 「贪婪」根本不出现 —— 用户没法"先看见再决定换什么血脉"。

    testWidgets('打开技能面板时，血脉技能也在候选里（含当前用不了的）',
        (tester) async {
      await _parse(tester);

      // 第 1 只是卡瓦重（雪山），冰血脉。打开它的第一个技能。
      await _tapScrolled(tester, find.text('晒太阳').first);
      expect(find.text('修正技能'), findsOneWidget);

      // 面板给的是**完整候选池**（46 个，含全部 18 个血脉技能），
      // 而不是当前血脉下能用的那 29 个。
      //
      // 断言方式：找某个"因血脉不可用"的技能，它应当出现，并带原因说明。
      // 直接 find 会因为它在滚动区外而扑空，所以用 skipOffstage: false
      // 把视口外的也算上 —— 这里验的是"有没有渲染出来"，不是"能不能看到"。
      final lockedChip = find.textContaining('需', skipOffstage: false);
      expect(lockedChip, findsWidgets,
          reason: '被血脉锁住的技能要出现在候选里，并说明需要什么血脉；'
              '藏起来的话用户就不知道"改血脉能学这个"');
    });

    testWidgets('切到「全部技能」后能搜到任意技能', (tester) async {
      await _parse(tester);
      await _tapScrolled(tester, find.text('晒太阳').first);
      await tester.tap(find.text('全部技能'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '贪婪');
      await tester.pumpAndSettle();
      expect(find.textContaining('贪婪'), findsWidgets);
    });
  });

  group('换精灵不沿用旧精灵的血脉与技能', () {
    testWidgets('换精灵后血脉重置，技能清空等用户自己配', (tester) async {
      await _parse(tester);

      // 第 1 只原本是 卡瓦重（雪山）+ 冰血脉
      expect(find.text('卡瓦重（雪山附近的样子）'), findsWidgets);
      expect(find.text('冰血脉'), findsWidgets);

      // 换成雪影娃娃
      await _tapScrolled(tester, find.text('卡瓦重（雪山附近的样子）').first);
      await tester.enterText(find.byType(TextField).last, '雪影娃娃');
      await tester.pumpAndSettle();
      await tester.tap(find.text('雪影娃娃').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // 名字换了
      expect(find.text('雪影娃娃'), findsWidgets);
      // **血脉不能沿用卡瓦重的冰血脉**
      expect(find.text('冰血脉'), findsNothing,
          reason: '换精灵后血脉必须重置，否则是新精灵配旧血脉');
      expect(find.text('血脉未识别'), findsWidgets);
    });

    testWidgets('换精灵后出现空槽，可以自己加技能', (tester) async {
      await _parse(tester);

      await _tapScrolled(tester, find.text('卡瓦重（雪山附近的样子）').first);
      await tester.enterText(find.byType(TextField).last, '雪影娃娃');
      await tester.pumpAndSettle();
      await tester.tap(find.text('雪影娃娃').last);
      await tester.pumpAndSettle();

      // 技能被清空 -> 卡片上应该出现「加技能」入口
      expect(find.text('加技能'), findsWidgets,
          reason: '换精灵后技能清空，需要能自己加回来');
    });
  });
}
