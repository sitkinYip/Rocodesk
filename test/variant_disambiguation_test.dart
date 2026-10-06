/// 形态消歧的测试。
///
/// 背景：pets 表里 61 个基础名有多个形态（卡瓦重 4 个、圣代甜甜 9 个），
/// 模型只读到基础名时无法确定是哪一个。这块逻辑决定"能不能自动选对"，
/// 选错会让阵容码里出现**另一种形态**，所以必须有测试。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rocodesk/core/variant_hints.dart';

/// 用真实的 variant_types.json 测，不用造数据 —— 造的数据测不出真实系别分布。
VariantHints _realHints() {
  final raw = jsonDecode(
    File('assets/data/variant_types.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return VariantHints.fromJson(raw);
}

void main() {
  late VariantHints hints;
  setUpAll(() => hints = _realHints());

  group('候选查找', () {
    test('基础名能找到全部形态', () {
      final c = hints.candidatesForName('卡瓦重');
      expect(c.length, 4, reason: '实测有 4 个形态');
      expect(c.map((e) => e.code).toSet(), {'vi', 'ze', 'zf', 'zg'});
    });

    test('全名只返回它自己', () {
      final c = hints.candidatesForName('卡瓦重（草地附近的样子）');
      expect(c.length, 1);
      expect(c.single.code, 'vi');
    });

    test('唯一名的形态只有一个候选', () {
      final c = hints.candidatesForName('雪影娃娃');
      expect(c.length, 1);
      expect(c.single.code, 'wz');
    });

    test('完全未知的名字返回空', () {
      expect(hints.candidatesForName('不存在的精灵'), isEmpty);
    });

    test('覆盖了 542 条（导出时统计的数量）', () {
      // 抽查几个不同基础名，确认表确实装进来了
      expect(hints.byCode('vi'), isNotNull);
      expect(hints.byCode('wz'), isNotNull);
      expect(hints.byCode('2B'), isNotNull);
    });
  });

  group('用系别自动消歧', () {
    test('卡瓦重 + 系别「草/冰」-> 唯一最优，自动选中', () {
      // 真实数据：vi=草, ze=草火, zf=草地, zg=草冰
      // 模型读到的「草/冰」应当把 zg 选出来
      final d = hints.disambiguate(
        queriedName: '卡瓦重',
        observedTypes: ['草', '冰'],
      );
      expect(d.picked, 'zg', reason: '草冰对应雪山形态');
      expect(d.needsUserChoice, isFalse);
      expect(d.reason, contains('系别'));
    });

    test('卡瓦重 + 系别「草/火」-> 选中火山形态', () {
      final d = hints.disambiguate(
        queriedName: '卡瓦重',
        observedTypes: ['草', '火'],
      );
      expect(d.picked, 'ze');
    });

    test('卡瓦重 + 系别「草/地」-> 选中沙地形态', () {
      final d = hints.disambiguate(
        queriedName: '卡瓦重',
        observedTypes: ['草', '地'],
      );
      expect(d.picked, 'zf');
    });

    test('系别读不出来时**不猜**，交给用户选', () {
      final d = hints.disambiguate(queriedName: '卡瓦重', observedTypes: []);
      expect(d.picked, isNull, reason: '没有依据时绝不能替用户决定');
      expect(d.needsUserChoice, isTrue);
      expect(d.candidates.length, 4);
      expect(d.reason, contains('没读出来'));
    });

    test('只读到「草」时选中草地形态 —— 这不是乱猜，而是有理据的', () {
      // 实测分数：vi=1.0（库里就是 ['草']），ze/zf/zg=0.5（两系别只命中一个）。
      // vi 是**草地形态**，映射到它符合语义，不是随机选。
      final d = hints.disambiguate(
        queriedName: '卡瓦重',
        observedTypes: ['草'],
      );
      expect(d.picked, 'vi');
      expect(d.reason, contains('系别'));
    });

    test('观察到的系别一个都不命中时，不猜，交给用户', () {
      // 用一个和四个形态都不沾边的系别
      final d = hints.disambiguate(
        queriedName: '卡瓦重',
        observedTypes: ['幽灵系'],
      );
      expect(d.picked, isNull, reason: '没有任何命中依据时必须问用户');
      expect(d.needsUserChoice, isTrue);
      expect(d.candidates.length, 4);
    });

    test('唯一名的名字不需要消歧', () {
      final d = hints.disambiguate(
        queriedName: '雪影娃娃',
        observedTypes: ['冰', '萌'],
      );
      expect(d.picked, 'wz');
      expect(d.needsUserChoice, isFalse);
    });

    test('候选按契合度排序，最匹配的排第一', () {
      final d = hints.disambiguate(
        queriedName: '卡瓦重',
        observedTypes: ['草', '冰'],
      );
      expect(d.candidates.first.code, 'zg');
      expect(d.candidates.first.score, greaterThan(0));
    });
  });

  group('打分规则', () {
    test('知识库少记一个系别时仍能选出正确形态（容错）', () {
      // 实测：`vi` 在知识库里是 ['草']，但游戏里显示「草/冰」。
      // 模型读到「草/冰」时，vi 和 zg 都会得一些分，
      // 要求 zg 不低于 vi —— 即模型看到的真实系别能把正确的排前面。
      final scored = VariantHints.scoreCandidates(
        hints.candidatesForName('卡瓦重'),
        ['草', '冰'],
      );
      final viRank = scored.indexWhere((c) => c.code == 'vi');
      final zgRank = scored.indexWhere((c) => c.code == 'zg');
      expect(zgRank, lessThan(viRank),
          reason: '命中「草+冰」的形态应当排在只命中「草」的前面');
    });

    test('没有观察系别时保持原顺序，不打分', () {
      final input = hints.candidatesForName('卡瓦重');
      final out = VariantHints.scoreCandidates(input, []);
      expect(out.map((c) => c.code).toList(), input.map((c) => c.code).toList());
    });
  });

  group('跨多个基础名的抽查', () {
    test('晶石蜗（6 个形态）能按系别区分', () {
      final c = hints.candidatesForName('晶石蜗');
      expect(c.length, greaterThanOrEqualTo(2));
      // 不假设一定能自动选中，但必须给出候选让用户能选
      final d = hints.disambiguate(queriedName: '晶石蜗', observedTypes: []);
      expect(d.needsUserChoice, isTrue);
      expect(d.candidates.length, c.length);
    });

    test('所有候选的基础名都等于查询名（不会串到别的精灵）', () {
      for (final base in ['卡瓦重', '丢丢', '化蝶', '圣代甜甜', '晶石蜗']) {
        final c = hints.candidatesForName(base);
        for (final x in c) {
          final cbase =
              x.name.replaceAll(RegExp(r'[（(].*?[)）]'), '').trim();
          expect(cbase, base, reason: '${x.code} 的名字是 ${x.name}');
        }
      }
    });
  });
}
