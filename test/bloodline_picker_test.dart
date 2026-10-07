/// 血脉选择器必须**一个不漏**地列出全部 24 条血脉。
///
/// 这里钉的是一个真实 bug：推荐位只取前 3 个显示，但"其余全部"的排除条件
/// 用的是完整的 6 个排序列表 —— 于是排名第 4~6 的血脉两边都不出现，
/// 凭空消失。每只精灵都会少 9 个可选血脉。
///
/// 用户就是因为「选血脉那里原来可以选的一些属性缺失了，起码缺少了翼」
/// 而发现的。翼 在月牙雪熊的排序里正好排第 4。
///
/// 这类"静默丢数据"的 bug 靠肉眼很难发现 —— 所以用穷举断言钉住。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rocodesk/core/bloodline_ranks.dart';
import 'package:rocodesk/core/icon_assets.dart';
import 'package:rocodesk/core/pipeline.dart';
import 'package:rocodesk/core/skill_matcher.dart';
import 'package:rocodesk/features/generator/result_view.dart';
import 'package:rocodesk/theme/app_theme.dart';

/// 全部 24 条血脉的名字，按官方字母表顺序。测试里独立列一遍，
/// **不 import 生产代码的常量** —— 否则常量本身写错就测不出来了。
const kExpected = [
  '普通', '草', '火', '水', '光', '地', '冰', '龙', '电', '毒',
  '虫', '武', '翼', '萌', '幽', '恶', '机械', '幻', '首领', '巨兽',
  '黑魔法', '异核', '污染', '奇异',
];

RecognizedPet _pet() => RecognizedPet(
      name: '雪影娃娃',
      petId: 'wz',
      nature: '固执',
      evs: const ['物攻', '物防', '生命'],
      skills: const ['暴风雪'],
      types: const ['冰'],
    );

/// 统计某个名字在整棵树里出现了几次。
///
/// 不能简单用 `findsOneWidget` —— 血脉名和系别名重叠（「冰」「龙」「普通」…），
/// 卡片上的系别行也会渲染同名文字，所以只数"打开选择器后是否多出来了"。
int _countOf(WidgetTester tester, String text) =>
    find.text(text).evaluate().length;

/// 打开选择器，返回"打开前各名字的数量"，供调用方比对增量。
Future<Map<String, int>> _openPicker(
  WidgetTester tester,
  List<String> rankedLetters,
) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: ResultView(
          team: RecognizedTeam(pets: [_pet()]),
          code: 'TEST~CODE',
          codeError: '',
          aiText: '',
          bloodlineOverrides: const {},
          variantOverrides: const {},
          skillOverrides: const {},
          learnableSkills: (_) => const [],
          magic: '进化之力',
          magicOptions: const ['进化之力'],
          teamName: '队伍3',
          onEditTeamName: (_) {},
          icons: IconAssets.empty(),
          bloodlineRanks: _FakeRanks(rankedLetters),
          onChooseMagic: (_) {},
          onChooseVariant: (_, _) {},
          onSkillsChanged: (_, _) {},
          onOverrideBloodline: (_, _) {},
          onCopy: (_, _) async {},
        ),
      ),
    ),
  ));

  final before = {for (final n in kExpected) n: _countOf(tester, n)};

  // 点血脉标签打开选择器
  await tester.tap(find.text('血脉未识别'));
  await tester.pumpAndSettle();
  expect(find.text('选择血脉'), findsOneWidget, reason: '选择器没打开');
  return before;
}

/// 断言 24 条血脉在选择器里**每条都至少渲染了一次**（相对打开前有增量）。
void _expectAllRendered(WidgetTester tester, Map<String, int> before) {
  final missing = <String>[];
  for (final name in kExpected) {
    if (_countOf(tester, name) <= (before[name] ?? 0)) missing.add(name);
  }
  expect(missing, isEmpty,
      reason: '这些血脉没出现在选择器里：$missing\n'
          '（推荐位只显示前 3 个，但排除条件若用完整列表，'
          '排名 4~6 的就会被吞掉 —— 这就是「翼 不见了」的根因）');
}

/// 固定返回给定的排序，避免依赖真实数据文件。
class _FakeRanks implements BloodlineRanks {
  _FakeRanks(this._letters);
  final List<String> _letters;

  @override
  List<String> forPet(String petName) => _letters;

  @override
  bool get isEmpty => _letters.isEmpty;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('24 条血脉一个都不能少', () {
    testWidgets('没有任何推荐时，全部 24 条都在', (tester) async {
      final before = await _openPicker(tester, const []);
      _expectAllRendered(tester, before);
      expect(find.text('无血脉'), findsOneWidget);
    });

    testWidgets('有 6 个推荐时，仍然一个不漏（就是踩过的这个 bug）', (tester) async {
      // 月牙雪熊的真实排序：翼(N) 排第 4，前 3 推荐是 幻/冰/龙
      final before = await _openPicker(tester, const ['S', 'H', 'I', 'N', 'J', 'Y']);
      _expectAllRendered(tester, before);
    });

    testWidgets('推荐列表比 6 个更长时也不丢', (tester) async {
      final before = await _openPicker(
        tester,
        const ['S', 'H', 'I', 'N', 'J', 'Y', 'B', 'C', 'D', 'E'],
      );
      _expectAllRendered(tester, before);
    });

    testWidgets('推荐里含无效字母时不影响总数', (tester) async {
      // 数据脏了（字母不在 24 条里）不该让其他项消失
      final before =
          await _openPicker(tester, const ['Z', '?', 'S', 'H', 'I', 'N']);
      _expectAllRendered(tester, before);
    });

    testWidgets('推荐项带「推荐」角标，且不超过 3 个', (tester) async {
      await _openPicker(tester, const ['S', 'H', 'I', 'N', 'J', 'Y']);
      expect(find.text('推荐'), findsNWidgets(3),
          reason: '推荐位固定 3 个（实测正确项进前 3 的比例是 5/6）');
    });
  });

  group('移动端：抽屉内容多了要能滚，不能溢出', () {
    testWidgets('小屏手机上血脉选择器不溢出，且能滚到底部的血脉', (tester) async {
      // 真实的小屏手机尺寸（iPhone SE 一类），比测试默认的 800x600 更窄更矮
      tester.view.physicalSize = const Size(375 * 2, 667 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final storeless = _FakeRanks(const []);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ResultView(
              team: RecognizedTeam(pets: [_pet()]),
              code: 'T',
              codeError: '',
              aiText: '',
              bloodlineOverrides: const {},
              variantOverrides: const {},
              skillOverrides: const {},
              learnableSkills: (_) => const [],
              magic: '进化之力',
              magicOptions: const ['进化之力'],
              teamName: '队伍3',
              onEditTeamName: (_) {},
              icons: IconAssets.empty(),
              bloodlineRanks: storeless,
              onChooseMagic: (_) {},
              onChooseVariant: (_, _) {},
              onSkillsChanged: (_, _) {},
              onOverrideBloodline: (_, _) {},
              onCopy: (_, _) async {},
            ),
          ),
        ),
      ));

      await tester.tap(find.text('血脉未识别'));
      await tester.pumpAndSettle();

      // 溢出会以异常形式暴露（RenderFlex overflowed）
      expect(tester.takeException(), isNull,
          reason: '抽屉内容溢出会被 catch 成异常');

      // 滚动到底部，最后一条血脉必须可达
      final scrollable = find.byType(Scrollable).last;
      await tester.drag(scrollable, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('奇异'), findsWidgets,
          reason: '滚到底要能看到最后一条血脉；看不到说明抽屉被截断了');
    });

    testWidgets('技能纠错面板在小屏上也不溢出', (tester) async {
      tester.view.physicalSize = const Size(375 * 2, 667 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ResultView(
              team: RecognizedTeam(pets: [
                () {
                  final p = RecognizedPet(
                    name: '雪影娃娃',
                    petId: 'wz',
                    nature: '固执',
                    evs: const ['物攻'],
                    // 一个读不准的技能 -> 变成可点的可疑项
                    skills: const ['藤蔓奔流'],
                    types: const ['冰'],
                  );
                  // skillSuggestions 是可变字段（规整阶段填充），不是构造参数
                  p.skillSuggestions['藤蔓奔流'] = const [
                    SkillSuggestion(code: 'a0bQ', name: '筛管奔流', score: 0.5),
                  ];
                  return p;
                }(),
              ]),
              code: 'T',
              codeError: '',
              aiText: '',
              bloodlineOverrides: const {},
              variantOverrides: const {},
              skillOverrides: const {},
              learnableSkills: (_) => const ['筛管奔流', '冰墙', '冬至'],
              magic: '进化之力',
              magicOptions: const ['进化之力'],
              teamName: '队伍3',
              onEditTeamName: (_) {},
              icons: IconAssets.empty(),
              bloodlineRanks: _FakeRanks(const []),
              onChooseMagic: (_) {},
              onChooseVariant: (_, _) {},
              onSkillsChanged: (_, _) {},
              onOverrideBloodline: (_, _) {},
              onCopy: (_, _) async {},
            ),
          ),
        ),
      ));

      await tester.tap(find.text('藤蔓奔流'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '技能面板溢出');
      expect(find.text('修正技能'), findsOneWidget);
      // 搜索框（原来的「手动填写」标签已去掉 —— 现在搜索框就是输入框）
      expect(find.text('搜索或直接输入技能名'), findsOneWidget,
          reason: '输入区也要能看到');
      // 底部按钮栏必须钉在底部可见（不再跟着列表滚走）
      expect(find.text('清空这个技能'), findsOneWidget,
          reason: '底部按钮栏要固定在底部');
    });
  });
}
