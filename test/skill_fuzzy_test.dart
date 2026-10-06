/// 技能名 OCR 纠错的测试。
///
/// 技能名是卡面上最小的字，读错是**常态**。实测案例：
///   「筛管奔流」被读成「藤蔓奔流」（用户反馈）
///   「焚烧烙印」被读成「焕烧烙印」
///
/// 这些测试用**真实的技能表与可学列表**，不用造数据 ——
/// 造的数据测不出真实难度。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rocodesk/core/skill_matcher.dart';

Map<String, dynamic> _read(String p) =>
    jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;

SkillMatcher _realMatcher() {
  final skills = _read('assets/data/skills.json');
  final learnsets = _read('assets/data/learnsets.json');
  return SkillMatcher(
    // 注意方向：这里要的是「技能码 -> 名字」（by_code），不是 by_name。
    // 可学列表里存的是技能码，要转成名字才能比。这里我一开始也传反过。
    skillsByName:
        (skills['by_code'] as Map<String, dynamic>).cast<String, String>(),
    learnsets: (learnsets['by_pet'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, (v as List).map((e) => e.toString()).toList()),
    ),
  );
}

void main() {
  late SkillMatcher m;
  setUpAll(() => m = _realMatcher());

  group('用户实际遇到的错字', () {
    test('藤蔓奔流 -> 筛管奔流 排第一（卡瓦重）', () {
      final s = m.suggest('藤蔓奔流', 'vi');
      expect(s, isNotEmpty, reason: '应当给出候选');
      expect(s.first.name, '筛管奔流',
          reason: '实测这个错字必须排第一，否则功能没意义');
      expect(s.first.score, greaterThanOrEqualTo(kSkillSuggestMinScore));
    });

    test('焕烧烙印 -> 焚烧烙印 能被建议出来（尖嘴狐仙）', () {
      final s = m.suggest('焕烧烙印', 'wF');
      expect(s.map((e) => e.name), contains('焚烧烙印'));
    });

    test('候选里只有这只精灵学得会的技能', () {
      final s = m.suggest('藤蔓奔流', 'vi');
      final learnable = m.learnableNames('vi');
      for (final x in s) {
        expect(learnable, contains(x.name),
            reason: '建议「${x.name}」不在卡瓦重的可学列表里');
      }
    });

    test('卡瓦重的可学列表里有 46 个技能（实测值）', () {
      expect(m.learnableNames('vi').length, 46);
    });
  });

  group('正确读出的技能不该被当成错误', () {
    test('精确命中返回 1.0', () {
      final s = m.suggest('筛管奔流', 'vi');
      expect(s, hasLength(1));
      expect(s.first.name, '筛管奔流');
      expect(s.first.score, 1.0);
    });

    test('其他正确技能同样满分', () {
      for (final name in ['冰墙', '暴风雪', '超级糖果']) {
        final s = m.suggest(name, 'wz');
        expect(s, isNotEmpty, reason: name);
        expect(s.first.name, name, reason: name);
        expect(s.first.score, 1.0, reason: name);
      }
    });
  });

  group('不该乱给建议', () {
    test('完全无关的输入不给候选', () {
      for (final junk in ['乱码乱码', '啊啊啊啊', 'xyz', '？？？']) {
        final s = m.suggest(junk, 'wz');
        expect(s, isEmpty, reason: '垃圾输入「$junk」不该硬套成某个技能');
      }
    });

    test('别的精灵的技能不会被当成这只精灵的技能', () {
      // 暴风雪是雪影娃娃的技能，不该建议给卡瓦重
      final s = m.suggest('暴风雷', 'vi');
      for (final x in s) {
        expect(m.learnableNames('vi'), contains(x.name),
            reason: '不能建议卡瓦重学不会的技能');
      }
    });

    test('空输入返回空', () {
      expect(m.suggest('', 'vi'), isEmpty);
      expect(m.suggest('   ', 'vi'), isEmpty);
    });
  });

  group('候选范围降级', () {
    test('没有精灵码时退回全表搜索，仍能找到近似的', () {
      final s = m.suggest('藤蔓奔流', null);
      expect(s.map((e) => e.name), contains('筛管奔流'),
          reason: '不知道是哪只精灵时也要能给建议');
    });

    test('精灵码不存在时同样退回全表', () {
      final s = m.suggest('藤蔓奔流', 'NOT_A_CODE');
      expect(s, isNotEmpty);
    });

    test('限制候选数量，避免一次给太多难选', () {
      final s = m.suggest('冰', 'wz');
      expect(s.length, lessThanOrEqualTo(kSkillSuggestLimit));
    });
  });

  group('打分规则本身', () {
    test('完全相同得 1.0', () {
      expect(SkillMatcher.score('筛管奔流', '筛管奔流'), 1.0);
    });

    test('同长错一字得分明显高于只重合一个字', () {
      final oneCharOff = SkillMatcher.score('藤蔓奔流', '筛管奔流');
      final barelyRelated = SkillMatcher.score('藤蔓奔流', '藤绞');
      expect(oneCharOff, greaterThan(barelyRelated));
    });

    test('长度差异越大得分越低（漏字/多字要被惩罚）', () {
      final sameLen = SkillMatcher.score('藤蔓奔流', '筛管奔流');
      final dropped = SkillMatcher.score('藤蔓奔', '筛管奔流');
      expect(dropped, lessThan(sameLen));
    });

    test('空串得 0 分，不抛异常', () {
      expect(SkillMatcher.score('', '冰墙'), 0.0);
      expect(SkillMatcher.score('冰墙', ''), 0.0);
      expect(SkillMatcher.score('', ''), 0.0);
    });

    test('重复字不会刷分', () {
      // 「啊啊啊啊」对「冰墙」应当很低
      expect(SkillMatcher.score('啊啊啊啊', '冰墙'), lessThan(0.3));
    });
  });

  group('真实数据的基本不变量', () {
    test('技能表 579 个、可学表 542 只精灵', () {
      expect(_read('assets/data/skills.json')['by_code'], hasLength(579));
      expect(_read('assets/data/learnsets.json')['covered_pets'], 542);
    });

    test('可学列表里的技能码都能在技能表里查到', () {
      final byCode = (_read('assets/data/skills.json')['by_code']
              as Map<String, dynamic>)
          .cast<String, String>();
      final byPet = _read('assets/data/learnsets.json')['by_pet']
          as Map<String, dynamic>;
      var checked = 0;
      for (final entry in byPet.entries) {
        for (final code in (entry.value as List)) {
          expect(byCode.containsKey(code.toString()), isTrue,
              reason: '${entry.key} 的技能码 $code 不在技能表里');
          checked++;
        }
      }
      expect(checked, greaterThan(20000), reason: '应当检查了两万多条记录');
    });
  });
}
