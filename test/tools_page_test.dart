/// 「工具」页的界面契约。
///
/// ## 为什么值得单独测
///
/// 这一页的视觉层级是**刻意**做的，而且理由来自实测：
///
///   * 头部三级层次（标题 / 定位一句话 / 数据事实行）
///   * 主功能（一图流）权重高于次要功能（阵容码解析）
///
/// 这类东西最容易在后续改动里被磨平 —— 有人为了"统一"把两卡改成一样、
/// 或把层级压回一行。测试在这里当护栏。
///
/// 另外头部那行数据（623 只 / 579 个技能）是**从数据表取的真实数字**，
/// 不是文案。这里核对它和实际数据一致，避免更新数据后数字变假。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rocodesk/features/tools/tools_page.dart';
import 'package:rocodesk/theme/app_theme.dart';
import 'package:rocodesk/theme/tokens.dart';

Map<String, dynamic> _read(String p) =>
    jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;

Future<void> _pump(WidgetTester tester, {
  Size size = const Size(390, 844),
  VoidCallback? onGenerator,
  VoidCallback? onParser,
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
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('头部', () {
    testWidgets('三级层次都在：标题 / 定位一句话 / 数据事实行', (tester) async {
      await _pump(tester);

      // 一级
      expect(find.text('工具'), findsOneWidget);

      // 二级：说清"能干什么"，不是元信息（原来只是"一站式工具"）
      expect(find.text('截图直接出阵容码，粘贴码反查出全队配置'), findsOneWidget);

      // 三级：真实数据事实行
      expect(find.text('623'), findsOneWidget);
      expect(find.text('只精灵'), findsOneWidget);
      expect(find.text('579'), findsOneWidget);
      expect(find.text('个技能'), findsOneWidget);
      expect(find.text('离线'), findsOneWidget);
    });

    testWidgets('头部数字与数据表实际条目数一致', (tester) async {
      // 防止手写数字过期：更新数据后这里会红，逼你去改头部
      final pets = _read('assets/data/pets.json')['by_code'] as Map;
      final skills = _read('assets/data/skills.json')['by_code'] as Map;

      await _pump(tester);
      expect(find.text('${pets.length}'), findsOneWidget,
          reason: '头部精灵数应与 pets.json 一致（实际 ${pets.length}）');
      expect(find.text('${skills.length}'), findsOneWidget,
          reason: '头部技能数应与 skills.json 一致（实际 ${skills.length}）');
    });

    testWidgets('头部小字用 textSecondary 而非 textTertiary（对比度）',
        (tester) async {
      // 实测（tools/check_contrast.py）：亮色下 textTertiary(#8E8E93)
      // 在 11px 上只有 3.26:1，低于 WCAG AA 的 4.5:1；
      // textSecondary 是 5.07:1（分组底色上 4.54:1）都过。
      // 这条盯住"别为了更淡的观感把它调回去"。
      await _pump(tester);
      final c = tester.element(find.text('只精灵')).colors;

      expect(c.textTertiary, isNot(c.textSecondary),
          reason: '两个色若被改成一样，这条断言就失去意义了');

      for (final label in const ['只精灵', '个技能', '不联网也能用']) {
        final t = tester.widget<Text>(find.text(label));
        expect(t.style?.color, c.textSecondary,
            reason: '「$label」是小字，必须用 textSecondary 才过 4.5:1');
      }
    });

    testWidgets('最窄档（320px）也不溢出', (tester) async {
      // 事实行是"数字 单位 · 数字 单位 · 数字 单位"，中文宽度不好估 ——
      // 别靠心算，直接在窄屏上跑一遍看有没有 RenderFlex overflow。
      await _pump(tester, size: const Size(320, 568));
      expect(tester.takeException(), isNull,
          reason: '320px（iPhone SE 一代）上头部不该溢出');
      // 溢出不抛异常而是画黄黑条时，会记进 FlutterError
      expect(find.text('623'), findsOneWidget);
      expect(find.text('不联网也能用'), findsOneWidget);
    });
  });

  group('卡片层级', () {
    testWidgets('两张可用卡都在，且描述可读', (tester) async {
      await _pump(tester);
      expect(find.text('一图流生成阵容码'), findsOneWidget);
      expect(find.text('阵容码解析'), findsOneWidget);
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
        // 卡片最外层那个带 BoxDecoration 的 Container
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
      await _pump(tester,
          onGenerator: () => gen++, onParser: () => parse++);

      await tester.tap(find.text('一图流生成阵容码'));
      await tester.pumpAndSettle();
      expect(gen, 1, reason: '主卡点了要打开一图流');

      await tester.tap(find.text('阵容码解析'));
      await tester.pumpAndSettle();
      expect(parse, 1, reason: '次卡点了要打开解析');
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
