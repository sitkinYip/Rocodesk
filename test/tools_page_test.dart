/// 「工具」页的界面契约。
///
/// ## 这一页的定位：**就是两个入口**
///
/// 试过两版头部（大标题 + 事实条），都被否掉了 —— 实测"越改越难看"，
/// 因为**入口被推下去了**。这一页没有需要解释的东西：
/// 打开 app 看到两张卡，点哪张进哪个功能，就够了。
///
/// 所以现在的规矩是：**页面顶部不放任何解释性内容**。
/// 下面的测试盯住这条，以及卡片的层级与可点性。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rocodesk/features/tools/tools_page.dart';
import 'package:rocodesk/theme/app_theme.dart';
import 'package:rocodesk/theme/tokens.dart';

Future<void> _pump(WidgetTester tester, {
  Size size = const Size(390, 844),
  VoidCallback? onGenerator,
  VoidCallback? onParser,
  VoidCallback? onBuilder,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: ToolsPage(
        onOpenGenerator: onGenerator ?? () {},
        onOpenParser: onParser ?? () {},
        onOpenBuilder: onBuilder ?? () {},
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('页面顶部', () {
    testWidgets('不放标题、不放事实条 —— 第一眼就是入口', (tester) async {
      await _pump(tester);

      // 三个入口都在
      expect(find.text('一图流生成阵容码'), findsOneWidget);
      expect(find.text('阵容码解析'), findsOneWidget);
      expect(find.text('自主配队'), findsOneWidget);

      // 之前那两版头部的东西都不该回来
      expect(find.text('工具'), findsNothing, reason: '页面顶部不再放大标题');
      expect(find.text('截图直接出阵容码，粘贴码反查出全队配置'), findsNothing);
      expect(find.text('收录精灵'), findsNothing);
      expect(find.text('收录技能'), findsNothing);
      expect(find.text('623'), findsNothing, reason: '不放数据事实条');
      expect(find.text('可用'), findsNothing, reason: '入口不需要"可用"分组标题');
    });

    testWidgets('第一个入口就在首屏顶部（没被任何东西推下去）', (tester) async {
      await _pump(tester, size: const Size(390, 700));
      final top = tester.getTopLeft(find.text('一图流生成阵容码')).dy;
      expect(top, lessThan(80),
          reason: '主卡标题应在顶部 80px 内，实测 $top —— 别在它上面加东西');
    });
  });

  group('卡片层级', () {
    testWidgets('两张可用卡都在，且描述可读', (tester) async {
      await _pump(tester);
      // 主卡描述压短了，但仍要说清"上传截图 -> 出码"
      expect(find.textContaining('上传阵容截图'), findsOneWidget);
      expect(find.textContaining('粘贴一串阵容码'), findsOneWidget);
      // 主卡的能力标签还在（扫读比读长句快）
      expect(find.text('读系别与血脉图标'), findsOneWidget);
      expect(find.text('识别错了可手改'), findsOneWidget);
    });

    testWidgets('主卡有强调色描边，次卡是普通分隔线 —— 层级差是真实的',
        (tester) async {
      await _pump(tester);
      final c = tester.element(find.text('一图流生成阵容码')).colors;

      Border borderOf(String label) {
        final container = tester.widget<Container>(
          find
              .ancestor(of: find.text(label), matching: find.byType(Container))
              .last,
        );
        return ((container.decoration as BoxDecoration).border! as Border);
      }

      final main = borderOf('一图流生成阵容码');
      final second = borderOf('阵容码解析');

      expect(main.top.color, c.accent.withValues(alpha: 0.35),
          reason: '主卡用强调色描边');
      expect(main.top.width, 1.5, reason: '主卡描边更粗');
      expect(second.top.color, c.separator, reason: '次卡用普通分隔线');
      expect(second.top.width, 1.0);
      expect(main.top.color, isNot(second.top.color),
          reason: '两张卡必须能一眼区分主次');
    });

    testWidgets('主卡有阴影，次卡没有', (tester) async {
      await _pump(tester);
      double shadowCount(String label) {
        final container = tester.widget<Container>(
          find
              .ancestor(of: find.text(label), matching: find.byType(Container))
              .last,
        );
        final d = (container.decoration as BoxDecoration);
        return (d.boxShadow?.length ?? 0).toDouble();
      }

      expect(shadowCount('一图流生成阵容码'), greaterThan(0),
          reason: '主卡靠阴影抬起来');
      expect(shadowCount('阵容码解析'), 0, reason: '次卡纯描边即可');
    });

    testWidgets('点到卡片会回调，不是死的', (tester) async {
      var gen = 0;
      var parse = 0;
      var build = 0;
      await _pump(tester,
          onGenerator: () => gen++,
          onParser: () => parse++,
          onBuilder: () => build++);

      await tester.tap(find.text('一图流生成阵容码'));
      await tester.pumpAndSettle();
      expect(gen, 1, reason: '主卡点了要打开一图流');

      await tester.tap(find.text('阵容码解析'));
      await tester.pumpAndSettle();
      expect(parse, 1, reason: '次卡点了要打开解析');

      await tester.tap(find.text('自主配队'));
      await tester.pumpAndSettle();
      expect(build, 1, reason: '自主配队卡点了要打开配队页');
    });

    testWidgets('自主配队卡说得清"不用截图也不用码"', (tester) async {
      await _pump(tester);
      // 它跟另外两个的本质区别是**不需要任何输入**，文案必须点明，
      // 否则用户会以为还得先有截图或码
      expect(find.textContaining('不用截图、不用码'), findsOneWidget);
      expect(find.text('623 只里搜'), findsOneWidget);
      expect(find.text('能学什么就选什么'), findsOneWidget);
      expect(find.text('改一项码就变'), findsOneWidget);
    });
  });

  group('联网边界（修正过的错误表述）', () {
    testWidgets('主卡明确写出"识别要联网、之后的改配出码本地算"', (tester) async {
      // 一图流识别要调用视觉模型 API（VlmClient.analyzeImage，
      // 需要 baseUrl + apiKey），断网用不了。
      // 原来写「离线可用」是误导 —— 首页最显眼的入口恰恰要联网。
      await _pump(tester);
      expect(find.textContaining('识别需要联网并填 API Key'), findsOneWidget,
          reason: '必须让用户知道识别那一步要联网 + 配 Key');
      expect(find.textContaining('都是本地算'), findsOneWidget,
          reason: '"本地"只覆盖识别之后的部分，要说准');
      expect(find.textContaining('离线'), findsNothing,
          reason: '绝不能声称离线可用');
    });
  });

  group('计划中的功能', () {
    testWidgets('明确标注，且不可点（不做假入口）', (tester) async {
      await _pump(tester);
      expect(find.text('计划中'), findsOneWidget);
      expect(find.text('属性克制查询'), findsOneWidget);
      expect(find.text('伤害估算器'), findsOneWidget);

      // 计划中的项**不该**有 InkWell —— 点了没反应比看不出没做更糟
      final inkwells = find.descendant(
        of: find.ancestor(
          of: find.text('属性克制查询'),
          matching: find.byType(Padding),
        ).first,
        matching: find.byType(InkWell),
      );
      expect(inkwells, findsNothing, reason: '计划中的项不该可点');
    });
  });
}
