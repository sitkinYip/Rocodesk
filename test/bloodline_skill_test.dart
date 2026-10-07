/// 血脉与技能的联动 —— 游戏机制，不是 UI 细节。
///
/// ## 机制（实测自知识库）
///
/// 技能有三个来源，行为不同：
///   * `level`     升级学会 —— 一直可用
///   * `stone`     技能石   —— 一直可用
///   * `bloodline` 血脉技能 —— **只有当前血脉对上才学得了**
///
/// 实测：每只精灵恰好有 18 个血脉技能，**每个对应一个系别**
/// （雪影娃娃：冰爪=冰、飞吻=萌、引燃=火、蓄水=水、羽化加速=翼…），
/// 而 24 条血脉里的 18 条 elemental 就是那 18 个系别。
///
/// 所以「血脉 = 额外的一个系别位」，改血脉会让一些技能失效 ——
/// 界面必须据此清掉学不了的血脉技能，否则会出一串游戏里不成立的配置。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rocodesk/core/codec_tables.dart';

Map<String, dynamic> _read(String p) =>
    jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;

CodecTables _tables() => CodecTables.fromMaps(
      pets: _read('assets/data/pets.json'),
      skills: _read('assets/data/skills.json'),
      natures: _read('assets/data/natures.json'),
      codec: _read('assets/data/codec.json'),
      learnsets: _read('assets/data/learnsets.json'),
    );

void main() {
  late CodecTables tables;
  late dynamic matcher; // SkillMatcher，避免为了类型多引一个 import
  setUpAll(() {
    tables = _tables();
    matcher = tables.skillMatcher;
  });

  group('数据前提（机制靠这些成立）', () {
    test('技能表带系别，579 个全覆盖', () {
      expect(tables.skillTypeByName.length, 579);
      expect(tables.skillTypeByName['冰爪'], '冰');
      expect(tables.skillTypeByName['飞吻'], '萌');
      expect(tables.skillTypeByName['引燃'], '火');
    });

    test('按来源拆分的可学数据在，且雪影娃娃是 16/16/18', () {
      expect(matcher.hasSourceData, isTrue);
      // 全部可学 = 16 level + 16 stone + 18 bloodline = 50
      final all = matcher.allNamesForPet('wz') as List<String>;
      expect(all.length, 50);
    });
  });

  group('候选池要给全量，不能按当前血脉砍掉', () {
    // 这是用户指出的问题：雪影娃娃能学 50 个，但冰血脉下只显示 33 个，
    // 「贪婪」（恶系血脉技能）根本不出现 —— 用户没法"先看见再决定"。
    test('雪影娃娃的候选池是 50 个，与血脉无关', () {
      expect((matcher.allNamesForPet('wz') as List<String>).length, 50);
    });

    test('恶系血脉技能「贪婪」在池子里 —— 用户要能先看到它', () {
      final all = matcher.allNamesForPet('wz') as List<String>;
      expect(all, contains('贪婪'));
      // 当前是冰血脉，所以它被标为"不可用"，但**不能在池子里消失**
      expect(matcher.isAvailable('贪婪', 'wz', '冰'), isFalse);
      expect(matcher.isAvailable('贪婪', 'wz', '恶'), isTrue);
    });

    test('18 个血脉技能全都在池子里，一个不少', () {
      final all = (matcher.allNamesForPet('wz') as List<String>).toSet();
      for (final s in const [
        '冰爪', '飞吻', '星星撞击', '虹光冲击', '升龙咆哮', '徒长',
        '引燃', '蓄水', '泥浆铠甲', '麻痹', '毒孢子', '假寐',
        '化劲', '羽化加速', '勾魂', '贪婪', '啮合传递', '超维投射',
      ]) {
        expect(all, contains(s), reason: '$s 是血脉技能，必须在候选池里');
      }
    });

    test('availableNames 仍然只给"当前血脉下能用的"（用来标记，不是当池子）', () {
      final usable = matcher.availableNames('wz', '冰') as List<String>;
      // 16 level + 16 stone + 1 冰系血脉技能 = 33
      expect(usable.length, 33);
      expect(usable, contains('冰爪'));
      expect(usable, isNot(contains('贪婪')));
    });
  });

  group('血脉决定血脉技能可不可用', () {
    test('冰血脉 -> 只有冰系血脉技能能用，其他系的被排除', () {
      final bl = matcher.availableNames('wz', '冰') as List<String>;
      expect(bl, contains('冰爪'), reason: '冰系血脉技能');
      expect(bl, isNot(contains('飞吻')), reason: '萌系血脉技能，冰血脉下不可用');
      expect(bl, isNot(contains('引燃')), reason: '火系血脉技能');
      expect(bl, isNot(contains('羽化加速')), reason: '翼系血脉技能');
    });

    test('火血脉 -> 只有火系血脉技能能用', () {
      final bl = matcher.availableNames('wz', '火') as List<String>;
      expect(bl, contains('引燃'));
      expect(bl, isNot(contains('冰爪')));
      expect(bl, isNot(contains('飞吻')));
    });

    test('level / stone 技能不受血脉影响', () {
      final ice = matcher.availableNames('wz', '冰') as List<String>;
      final fire = matcher.availableNames('wz', '火') as List<String>;
      // 这两类来源的技能在两个血脉下都应当在
      for (final s in const ['冰墙', '防御', '超级糖果']) {
        expect(ice, contains(s), reason: '$s 是 level 技能');
        expect(fire, contains(s), reason: '$s 不该被血脉影响');
      }
    });

    test('特殊血脉（首领）不提供技能系别，但也不该让人少选项', () {
      final leader = matcher.availableNames('wz', '首领') as List<String>;
      // 「首领」不是 18 系别之一，所以没有血脉技能匹配 —— 但 level/stone 都在
      expect(leader, contains('冰墙'));
      expect(leader.length, greaterThanOrEqualTo(32),
          reason: 'level 16 + stone 16 至少要有');
    });

    test('不知道血脉时全部血脉技能都放出来，不替用户排除', () {
      final unknown = matcher.availableNames('wz', null) as List<String>;
      expect(unknown, contains('冰爪'));
      expect(unknown, contains('引燃'));
      expect(unknown, contains('飞吻'));
    });
  });

  group('单个技能的可用性判断（用来清掉失效的）', () {
    test('换了血脉，原本的血脉技能变不可用', () {
      // 冰爪是冰系血脉技能：冰血脉下可用，火血脉下不可用
      expect(matcher.isAvailable('冰爪', 'wz', '冰'), isTrue);
      expect(matcher.isAvailable('冰爪', 'wz', '火'), isFalse);
    });

    test('level 技能在任何血脉下都可用', () {
      for (final bl in const ['冰', '火', '首领', null]) {
        expect(matcher.isAvailable('冰墙', 'wz', bl), isTrue, reason: '$bl');
      }
    });

    test('用户从「全部技能」硬选的、这只学不了的技能不会被拦', () {
      // 用户就是要配一个它学不了的技能 —— 游戏允许，不该在这里拦
      expect(matcher.isAvailable('隼鳞', 'wz', '冰'), isTrue);
    });

    test('没有来源数据时一律放行（老数据包退回不过滤）', () {
      expect(matcher.isAvailable('冰爪', '不存在的码', '火'), isTrue);
    });
  });

  group('真实场景：雪影娃娃改血脉', () {
    test('从首领改成冰 —— 首领不提供技能，冰提供冰爪', () {
      final leader = (matcher.availableNames('wz', '首领') as List<String>).toSet();
      final ice = (matcher.availableNames('wz', '冰') as List<String>).toSet();
      // 首领下没有血脉技能可用；改成冰之后「冰爪」变得可用
      expect(leader, isNot(contains('冰爪')));
      expect(ice, contains('冰爪'));
    });

    test('从冰改成火 —— 冰爪失效，引燃变得可用', () {
      expect(matcher.isAvailable('冰爪', 'wz', '冰'), isTrue);
      expect(matcher.isAvailable('冰爪', 'wz', '火'), isFalse);
      expect(matcher.isAvailable('引燃', 'wz', '火'), isTrue);
      expect(matcher.isAvailable('引燃', 'wz', '冰'), isFalse);
    });
  });
}
