/// 特性（talent）展示。
///
/// ## 机制
///
/// 特性是精灵自带的被动：**不在阵容码里、一只是 1 个、不可改**。
/// 与血脉是两件不同的事 —— 血脉 24 选 1 可改，特性天生固定。
/// 所以界面上特性只展示，没有编辑入口。
///
/// 数据：`pets.json.ability_by_code` 给"精灵码 -> 特性名"，
/// `traits.json` 给"特性名 -> 描述 + 官方图标 URL"（242 个，描述无冲突）。
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
      traits: _read('assets/data/traits.json'),
    );

void main() {
  group('数据前提', () {
    late CodecTables t;
    setUpAll(() => t = _tables());

    test('traits.json 有 242 个特性，描述都不为空', () {
      expect(t.traits.length, 242);
      final empty = t.traits.entries
          .where((e) => (e.value['desc'] ?? '').isEmpty)
          .map((e) => e.key)
          .toList();
      expect(empty, isEmpty, reason: '这些特性没有描述: $empty');
    });

    test('542 个精灵码有特性', () {
      expect(t.petAbilityByCode.length, 542);
    });

    test('每个精灵的特性名都能在 traits 表里查到', () {
      final orphan = t.petAbilityByCode.entries
          .where((e) => !t.traits.containsKey(e.value))
          .map((e) => '${e.key}->${e.value}')
          .toList();
      expect(orphan, isEmpty, reason: '查不到描述: ${orphan.take(8)}');
    });

    test('用户在用的这 6 只都能查到特性与描述', () {
      // 键是阵容码，值是**数据里真实的**特性名（别凭印象写）
      const expected = {
        'wz': '捉迷藏',
        '2B': '月牙雪糕',
        'wF': '灵魂灼伤',
        'zg': '诈死',
        '0P': '冰雪魂魄',
        'zF': '不朽',
      };
      for (final e in expected.entries) {
        expect(t.abilityOf(e.key), e.value, reason: e.key);
        expect(t.abilityDescOf(e.key), isNotNull, reason: '${e.key} 没有描述');
      }
    });

    test('没有特性的精灵码返回 null 而不是空串/异常', () {
      expect(t.abilityOf(null), isNull);
      expect(t.abilityOf('不存在的码'), isNull);
      expect(t.abilityDescOf('不存在的码'), isNull);
    });

    test('缺 traits.json 时能力退化但不崩', () {
      final bare = CodecTables.fromMaps(
        pets: _read('assets/data/pets.json'),
        skills: _read('assets/data/skills.json'),
        natures: _read('assets/data/natures.json'),
        codec: _read('assets/data/codec.json'),
      );
      // 特性名还在（来自 pets.json），但描述查不到
      expect(bare.abilityOf('wz'), '捉迷藏');
      expect(bare.abilityDescOf('wz'), isNull);
      expect(bare.traits, isEmpty);
    });
  });

  group('图标索引', () {
    test('242 个特性都有图标记录', () {
      final idx = jsonDecode(
        File('assets/icons/index.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final trait = (idx['trait'] as Map<String, dynamic>? ?? {});
      expect(trait.length, 242);

      final traits = _read('assets/data/traits.json')['by_name'] as Map;
      for (final nm in traits.keys) {
        expect(trait.containsKey(nm), isTrue, reason: '缺特性图标: $nm');
        expect(File(trait[nm] as String).existsSync(), isTrue, reason: '$nm');
      }
    });
  });

  group('界面：特性只展示，不可改', () {
    Future<void> parse(WidgetTester tester) async {
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

    testWidgets('卡片上出现特性名', (tester) async {
      await parse(tester);
      // 第 1 只是卡瓦重（雪山），特性「诈死」
      expect(find.text('诈死'), findsWidgets);
    });

    testWidgets('点特性能看到完整描述，并写明不可改', (tester) async {
      await parse(tester);
      await tester.tap(find.text('诈死').first);
      await tester.pumpAndSettle();

      expect(find.text('自己力竭时，少损失1点魔力。'), findsOneWidget);
      expect(find.text('精灵固有 · 不可改'), findsOneWidget,
          reason: '要明确写出来，否则用户会找"怎么改特性"');
    });
  });
}
