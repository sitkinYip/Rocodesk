/// 「整支队伍完全可编辑」的测试。
///
/// 用户的要求：拿到一图流之后还能自己搭配 —— 换精灵、重选血脉、
/// 改性格、改个体资质、换任意技能，而不是只能改"模型读不准的"那几个。
///
/// 这些覆盖参数是**出码那一层**的最后一站，所以这里测的是
/// "改了之后阵容码真的变了、而且是按预期变的"。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rocodesk/core/codec_tables.dart';
import 'package:rocodesk/core/models.dart';
import 'package:rocodesk/core/pipeline.dart';
import 'package:rocodesk/core/teamcodec.dart';

Map<String, dynamic> _read(String p) =>
    jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;

void main() {
  late CodecTables tables;
  late TeamCodec codec;
  setUpAll(() {
    tables = CodecTables.fromMaps(
      pets: _read('assets/data/pets.json'),
      skills: _read('assets/data/skills.json'),
      natures: _read('assets/data/natures.json'),
      codec: _read('assets/data/codec.json'),
    );
    codec = TeamCodec(tables);
  });

  /// 一只识别结果：雪影娃娃，性格固执，带 4 个技能，首领血脉。
  RecognizedTeam one() => normalizeVlmOutput({
        'magic': '进化之力',
        'pets': [
          {
            'name': '雪影娃娃',
            'nature': '固执',
            'evs': ['物攻', '物防', '生命'],
            'skills': ['暴风雪', '冰墙', '冬至', '超级糖果'],
            'bloodline': '首领',
            'bloodline_letter': 'T',
          },
        ],
      }, codec: codec, tables: tables);

  /// 出码并解码回来，方便断言"码里真的是这个"。
  Team roundTrip(RecognizedTeam rt, {
    Map<int, String> bloodline = const {},
    Map<int, String> pet = const {},
    Map<int, String> nature = const {},
    Map<int, List<String>> evs = const {},
    Map<int, List<String>> skills = const {},
  }) {
    final team = toCodecTeam(
      rt, bloodline,
      petOverrides: pet,
      natureOverrides: nature,
      evOverrides: evs,
      skillOverrides: skills,
      tables: tables,
    );
    return codec.decode(codec.encode(team));
  }

  group('每一项都能改', () {
    test('不改动时就是识别结果', () {
      final t = roundTrip(one());
      expect(t.pets.single.petId, 'wz');
      expect(t.pets.single.nature, '固执');
      expect(t.pets.single.evsList, ['物攻', '物防', '生命']);
      expect(t.pets.single.skills, ['暴风雪', '冰墙', '冬至', '超级糖果']);
      expect(t.pets.single.bloodlineLetter, 'T');
    });

    test('改精灵 —— 整只换掉', () {
      final t = roundTrip(one(), pet: const {1: 'zF'});
      expect(t.pets.single.petId, 'zF', reason: '换成了寂灭骨龙');
      expect(t.pets.single.petName, '寂灭骨龙',
          reason: '名字要跟着换，否则界面会"骨龙的码配雪影娃娃的名"');
    });

    test('改血脉 —— 换成任意 24 条之一', () {
      for (final entry in const {'翼': 'N', '龙': 'I', '无': 'A'}.entries) {
        final t = roundTrip(one(), bloodline: {1: entry.key});
        if (entry.key == '无') {
          // 空串表示"明确无血脉"（哨兵 A）
          final t2 = roundTrip(one(), bloodline: const {1: ''});
          expect(t2.pets.single.bloodlineLetter, 'A');
        } else {
          expect(t.pets.single.bloodlineLetter, entry.value,
              reason: '改成${entry.key}血脉');
        }
      }
    });

    test('改性格', () {
      final t = roundTrip(one(), nature: const {1: '开朗'});
      expect(t.pets.single.nature, '开朗');
    });

    test('改个体资质 —— 换成另外三个维度', () {
      final t = roundTrip(one(), evs: const {
        1: ['魔攻', '魔防', '速度']
      });
      expect(t.pets.single.evsList, ['魔攻', '魔防', '速度']);
    });

    test('改技能 —— 换成完全不同的四个', () {
      final t = roundTrip(one(), skills: const {
        1: ['冰点', '先发制人', '双星', '冰墙']
      });
      expect(t.pets.single.skills, ['冰点', '先发制人', '双星', '冰墙']);
    });

    test('减少技能数量', () {
      final t = roundTrip(one(), skills: const {
        1: ['冰墙']
      });
      expect(t.pets.single.skills, ['冰墙']);
    });
  });

  group('多项一起改', () {
    test('换精灵 + 换血脉 + 换技能 + 换性格 + 换资质', () {
      final t = roundTrip(
        one(),
        pet: const {1: '2B'},
        bloodline: const {1: '翼'},
        nature: const {1: '开朗'},
        evs: const {
          1: ['生命', '魔攻', '速度']
        },
        skills: const {
          1: ['双星', '先发制人', '冰点', '冰墙']
        },
      );
      final p = t.pets.single;
      expect(p.petId, '2B');
      expect(p.petName, '月牙雪熊');
      expect(p.bloodlineLetter, 'N');
      expect(p.nature, '开朗');
      expect(p.evsList, ['生命', '魔攻', '速度']);
      expect(p.skills, ['双星', '先发制人', '冰点', '冰墙']);
    });

    test('换精灵优先于选形态（用户可能换成完全不同的精灵）', () {
      final rt = normalizeVlmOutput({
        'pets': [
          {'name': '卡瓦重', 'types': ['草', '冰'], 'skills': []},
        ],
      }, codec: codec, tables: tables);
      // 卡瓦重有 4 个形态；这里同时给"选形态"和"换精灵"，后者应当获胜
      final team = toCodecTeam(
        rt, const {},
        variantOverrides: const {1: 'zg'},
        petOverrides: const {1: 'wz'},
        tables: tables,
      );
      expect(codec.decode(codec.encode(team)).pets.single.petId, 'wz');
    });

    test('换精灵后技能保留原样（不静默清空）', () {
      // 用户先改技能再换精灵，技能不该被丢掉 ——
      // 由界面负责提示"这只学不了这个技能"，而不是这里悄悄删。
      final t = roundTrip(
        one(),
        pet: const {1: 'zF'},
        skills: const {
          1: ['借用', '隼鳞', '电弧', '报复']
        },
      );
      expect(t.pets.single.skills, ['借用', '隼鳞', '电弧', '报复']);
    });
  });

  group('覆盖只影响指定那一只', () {
    test('6 只里只改第 3 只，其余不动', () {
      final rt = normalizeVlmOutput({
        'pets': [
          {'name': '雪影娃娃', 'nature': '固执', 'skills': ['冰墙']},
          {'name': '月牙雪熊', 'nature': '固执', 'skills': ['双星']},
          {'name': '尖嘴狐仙', 'nature': '开朗', 'skills': ['炎枪']},
        ],
      }, codec: codec, tables: tables);

      final team = toCodecTeam(
        rt, const {},
        natureOverrides: const {3: '慎重'},
        tables: tables,
      );
      final back = codec.decode(codec.encode(team));
      expect(back.pets[0].nature, '固执');
      expect(back.pets[1].nature, '固执');
      expect(back.pets[2].nature, '慎重', reason: '只有第 3 只被改');
    });

    test('编号从 1 开始（和第几只一致）', () {
      final rt = normalizeVlmOutput({
        'pets': [
          {'name': '雪影娃娃', 'skills': ['冰墙']},
          {'name': '月牙雪熊', 'skills': ['双星']},
        ],
      }, codec: codec, tables: tables);
      final team = toCodecTeam(rt, const {},
          petOverrides: const {1: 'wz'}, tables: tables);
      final back = codec.decode(codec.encode(team));
      expect(back.pets[0].petId, 'wz', reason: '键 1 = 第 1 只');
      expect(back.pets[1].petId, isNot('wz'), reason: '第 2 只不该被影响');
    });
  });

  group('异常输入不产生废码', () {
    test('换成不存在的精灵码会抛错，而不是写出无效的码', () {
      final team = toCodecTeam(one(), const {},
          petOverrides: const {1: 'NOT_A_CODE'}, tables: tables);
      expect(() => codec.encode(team),
          throwsA(isA<TeamCodeException>()),
          reason: '宁可报错也不能生成一个进游戏无效的码');
    });

    test('改成不存在的性格会抛错', () {
      final team = toCodecTeam(one(), const {},
          natureOverrides: const {1: '不存在的性格'},
        tables: tables,
      );
      expect(() => codec.encode(team), throwsA(isA<TeamCodeException>()));
    });
  });
}
