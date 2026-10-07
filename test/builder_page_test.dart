/// 自主配队：从零造一支队伍并出码。
///
/// ## 这个文件为什么先测纯函数
///
/// `buildDraft` 是纯函数（给同样输入得到同样输出），所以"改一项 → 码跟着变"
/// 这条规则可以在**不点界面**的情况下验证。界面测试只留给真正属于界面的东西
/// （空槽文案、回调接线）。
///
/// 这也让失败定位快得多：码错了就是 `buildDraft` 的问题，不是"某个
/// setState 忘了调 `_reencode`"。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rocodesk/core/codec_tables.dart';
import 'package:rocodesk/core/teamcodec.dart';
import 'package:rocodesk/features/builder/builder_page.dart';
import 'package:rocodesk/features/builder/team_draft.dart';
import 'package:rocodesk/theme/app_theme.dart';
import 'package:rocodesk/widgets/common.dart';

Map<String, dynamic> _read(String p) =>
    jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;

CodecTables _tables() => CodecTables.fromMaps(
      pets: _read('assets/data/pets.json'),
      skills: _read('assets/data/skills.json'),
      natures: _read('assets/data/natures.json'),
      codec: _read('assets/data/codec.json'),
      learnsets: _read('assets/data/learnsets.json'),
      variantTypes: _read('assets/data/variant_types.json'),
      traits: _read('assets/data/traits.json'),
    );

void main() {
  late CodecTables tables;
  setUpAll(() => tables = _tables());

  group('空队伍', () {
    test('默认 6 个空槽，一个都没填', () {
      final team = blankTeam();
      expect(team.pets.length, 6);
      expect(team.pets.every((p) => p.petId.isEmpty), isTrue);
      expect(team.allResolved, isFalse);
    });

    test('一只都没选时**不说技术报错**，把话留给界面说', () {
      // `encode` 对空队伍说的是「阵容为空，无法编码」—— 那是给开发者看的。
      // 这里刻意留空 codeError，界面就会显示 emptyCodeMessage
      // （「把精灵选上就会生成阵容码。」）。
      final d = buildDraft(blankTeam(), tables);
      expect(d.code, isEmpty);
      expect(d.codeError, isEmpty,
          reason: '空队伍的 codeError 应当留空，交给 emptyCodeMessage。'
              '实际拿到：「${d.codeError}」');
    });

    test('空槽会被跳过，不参与出码', () {
      // 6 个槽只填 2 个：出码应当只有 2 只，而不是被空槽拦住
      final d = buildDraft(
        blankTeam(),
        tables,
        petOverrides: _firstN(tables, 2),
      );
      expect(d.code, isNotEmpty, reason: '错误：${d.codeError}');
      expect(TeamCodec(tables).decode(d.code).pets.length, 2);
    });
  });

  group('填精灵就能出码', () {
    test('一只精灵：出码、回解、名字对得上', () {
      final team = blankTeam();
      final draft = buildDraft(
        team,
        tables,
        petOverrides: const {1: 'wz'},
      );

      expect(draft.code, isNotEmpty, reason: '错误：${draft.codeError}');
      final back = TeamCodec(tables).decode(draft.code);
      expect(back.pets.length, 1);
      expect(back.pets.first.petId, 'wz');
    });

    test('**不足 6 只也能出码**（encode 的 countLetter = 65 + n）', () {
      final draft = buildDraft(blankTeam(), tables, petOverrides: const {1: 'wz'});
      expect(draft.code, isNotEmpty);

      // 2 只
      final two = _firstN(tables, 2);
      final d2 = buildDraft(blankTeam(), tables, petOverrides: two);
      expect(d2.code, isNotEmpty);
      expect(TeamCodec(tables).decode(d2.code).pets.length, 2);
    });

    test('6 只满编：出码且回解 6 只', () {
      final six = _firstN(tables, 6);
      final d = buildDraft(blankTeam(), tables, petOverrides: six);
      expect(d.code, isNotEmpty, reason: d.codeError);
      expect(TeamCodec(tables).decode(d.code).pets.length, 6);
    });

    test('filledCount 数得对（且不受"两只一样"影响）', () {
      final first = tables.petNames.keys.first;
      // 故意让两只填成同一个精灵码 —— indexOf 写法会在这里数错
      final d = buildDraft(
        blankTeam(),
        tables,
        petOverrides: {1: first, 2: first},
      );
      expect(d.filledCount, 2);
    });
  });

  group('改一项，码跟着变', () {
    /// 出码再回解，取第 n 只的某个字段 —— 判断"改动是否真的进了码"。
    Map<String, dynamic> roundTrip(TeamDraft d) {
      final t = TeamCodec(tables).decode(d.code);
      return {
        'ids': t.pets.map((p) => p.petId).toList(),
        'natures': t.pets.map((p) => p.nature).toList(),
        'bloodlines': t.pets.map((p) => p.bloodlineLetter).toList(),
        'skills': t.pets.map((p) => p.skills).toList(),
      };
    }

    test('改性格进了码', () {
      final base = buildDraft(blankTeam(), tables, petOverrides: const {1: 'wz'});
      final changed = buildDraft(
        blankTeam(),
        tables,
        petOverrides: const {1: 'wz'},
        natureOverrides: const {1: '固执'},
      );
      expect(roundTrip(base)['natures'], isNot(roundTrip(changed)['natures']));
      expect(roundTrip(changed)['natures'], ['固执']);
    });

    test('改血脉进了码', () {
      final changed = buildDraft(
        blankTeam(),
        tables,
        petOverrides: const {1: 'wz'},
        bloodlineOverrides: const {1: 'H'}, // 冰
      );
      expect(roundTrip(changed)['bloodlines'], ['H']);
    });

    test('改技能进了码', () {
      final learnable = tables.skillMatcher.learnableNames('wz');
      expect(learnable, isNotEmpty, reason: '雪影娃娃应当有可学技能');
      final changed = buildDraft(
        blankTeam(),
        tables,
        petOverrides: const {1: 'wz'},
        skillOverrides: {
          1: [learnable.first, '', '', ''],
        },
      );
      expect(changed.code, isNotEmpty, reason: changed.codeError);
      // 回解出的技能表**不带尾部空槽**（空槽在码里是空段，解析时不还原成 ''）
      expect(roundTrip(changed)['skills']!.first, [learnable.first]);
    });

    test('**删掉一个技能**还能出码（空串是"这个槽空的"，不是技能名）', () {
      // 这里钉一个真实 bug：技能槽用空串表示空槽，但出码时把空串也当成
      // 技能名去反查，于是"删掉一个技能"直接变成
      // 「技能「」无法反查技能码」—— 用户只是清空一格却被拦住不让出码。
      //
      // 在识别页也一样会发生（那里删技能就是设成空串），
      // 只是自主配队一进来就全是空槽，所以更容易撞上。
      final learnable = tables.skillMatcher.learnableNames('wz');
      final d = buildDraft(
        blankTeam(),
        tables,
        petOverrides: const {1: 'wz'},
        skillOverrides: {
          1: [learnable[0], learnable[1], '', ''],
        },
      );
      expect(d.code, isNotEmpty,
          reason: '两格空着不该拦住出码。实际：${d.codeError}');
      expect(roundTrip(d)['skills']!.first, [learnable[0], learnable[1]]);
    });

    test('尾部空槽不出现在回解结果里（不是"两个技能 + 两个空"）', () {
      final learnable = tables.skillMatcher.learnableNames('wz');
      final d = buildDraft(
        blankTeam(),
        tables,
        petOverrides: const {1: 'wz'},
        skillOverrides: {
          1: [learnable[0], '', '', ''],
        },
      );
      expect(roundTrip(d)['skills']!.first, [learnable[0]],
          reason: '空槽是"没写"，不是"写了个空白技能"');
    });

    test('金标契约：空槽是**紧凑**的，位置不保留', () {
      // 这一条是照着 Python 参考实现的行为写的（`assets/golden/` 里
      // 的 593 条真实码逐项比对就是这个规则）：
      //
      //     dart=吹火,焚烧烙印,,爆米花爆破  python=吹火,焚烧烙印,爆米花爆破
      //
      // 所以"第 3 格空着"回解后，第 4 格的技能会出现在第 3 位。
      // 这不是我想要的界面效果，但**它是既定契约** ——
      // 改它必须两边一起改并重新生成夹具，不能只改 Dart。
      // 写成测试是为了让下次有人想"顺手修一下位置"时先看到这段。
      final learnable = tables.skillMatcher.learnableNames('wz');
      final d = buildDraft(
        blankTeam(),
        tables,
        petOverrides: const {1: 'wz'},
        skillOverrides: {
          1: [learnable[0], learnable[1], '', learnable[3]],
        },
      );
      expect(roundTrip(d)['skills']!.first,
          [learnable[0], learnable[1], learnable[3]],
          reason: '空槽被跳过（紧凑）。若这里变成带空串的 4 项，'
              '先去看 codec_golden_test 是否也一起改了');
    });

    test('技能名是真的（引号里不是空字符串）', () {
      final learnable = tables.skillMatcher.learnableNames('wz');
      expect(learnable.every((s) => s.trim().isNotEmpty), isTrue,
          reason: '候选池里不该有空名字，否则和"空槽"的约定撞车');
    });

    test('换精灵改写 petId（而不是叠加）', () {
      final codes = tables.petNames.keys.take(2).toList();
      final d = buildDraft(
        blankTeam(),
        tables,
        petOverrides: {1: codes[1]},
      );
      expect(roundTrip(d)['ids'], [codes[1]]);
    });

    test('改魔法名进了码', () {
      final opts = tables.magic.values.toList();
      expect(opts.length, greaterThanOrEqualTo(2));
      final a = buildDraft(blankTeam(), tables,
          petOverrides: const {1: 'wz'}, magicOverride: opts[0]);
      final b = buildDraft(blankTeam(), tables,
          petOverrides: const {1: 'wz'}, magicOverride: opts[1]);
      expect(a.code, isNot(b.code));
      expect(a.magic, opts[0]);
      expect(b.magic, opts[1]);
    });

    test('队伍名默认取数据表的值，改了就用改的', () {
      final d0 = buildDraft(blankTeam(), tables, petOverrides: const {1: 'wz'});
      expect(d0.teamName, tables.defaultTeamName,
          reason: '默认队名必须来自 codec.json.defaults，不能写死');

      final d1 = buildDraft(blankTeam(), tables,
          petOverrides: const {1: 'wz'}, teamNameOverride: '我的队伍');
      expect(d1.teamName, '我的队伍');
    });

    test('助手描述跟着队伍走（不是空转）', () {
      final d = buildDraft(blankTeam(), tables, petOverrides: const {1: 'wz'});
      expect(d.aiText, isNotEmpty);
      expect(d.aiText, contains('配队'));
    });
  });

  group('自主配队界面', () {
    Future<void> pump(WidgetTester tester, {Size size = const Size(390, 900)}) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: BuilderPage(injectedTables: tables),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('打开就是 6 个空槽，且文案不出现"识别"', (tester) async {
      await pump(tester);

      // 6 个格子
      for (var i = 1; i <= 6; i++) {
        expect(find.text('$i'), findsOneWidget, reason: '第 $i 格');
      }
      // 空槽是**可点的入口**，不是错误
      expect(find.text('选择精灵'), findsWidgets);
      expect(find.text('未知宠物'), findsNothing,
          reason: '空槽不该显示「未知宠物」—— 那是"认不出来"，不是"还没选"');
      expect(find.text('需要对上图鉴'), findsNothing,
          reason: '空槽不是"对不上图鉴"的失败状态');

      // 自主配队没有识别过程，标题不该出现「识别结果」
      expect(find.text('识别结果'), findsNothing);
      expect(find.text('队伍配置'), findsOneWidget);
      expect(find.textContaining('选好精灵就会自动生成阵容码'), findsOneWidget);
    });

    testWidgets('还没出码时是**蓝色信息条**，不是红色报错', (tester) async {
      await pump(tester);
      // 一进来当然还没有码 —— 那是正常状态。
      // 拿红色告警说"你还没开始选精灵"会让用户以为哪里坏了。
      final notice = tester.widget<InlineNotice>(find.byType(InlineNotice));
      expect(notice.severity, NoticeSeverity.info,
          reason: '空队伍的提示应当是 info 级');
      expect(notice.severity, isNot(NoticeSeverity.error));
    });

    testWidgets('选满提示会随选择更新', (tester) async {
      await pump(tester);
      expect(find.textContaining('已选 0/6'), findsOneWidget);
    });
  });
}

/// 取前 n 个精灵码，做成 `{1: code1, 2: code2, ...}`。
Map<int, String> _firstN(CodecTables t, int n) {
  final codes = t.petNames.keys.take(n).toList();
  return {for (var i = 0; i < codes.length; i++) i + 1: codes[i]};
}
