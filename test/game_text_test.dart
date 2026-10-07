/// 「给官方 AI 助手的描述」的格式测试。
///
/// 用户明确要求：**不要阵容码、不要队伍名**，开头要给任务指令
/// （"按以下要求组一支队伍"）。这里把这几条钉住。
///
/// 为什么值得测：这段文本是用户唯一会复制出去的东西，
/// 格式变了（比如又把码带上了）用户不会发现，只会觉得助手回答得怪。
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

CodecTables _tables() => CodecTables.fromMaps(
      pets: _read('assets/data/pets.json'),
      skills: _read('assets/data/skills.json'),
      natures: _read('assets/data/natures.json'),
      codec: _read('assets/data/codec.json'),
      variantTypes: _read('assets/data/variant_types.json'),
      learnsets: _read('assets/data/learnsets.json'),
    );

void main() {
  late TeamCodec codec;
  setUpAll(() => codec = TeamCodec(_tables()));

  /// 用户那张图上的第 1 只（实机验证过的数据）。
  Team realTeam() => Team(
        name: '队伍3',
        magic: '进化之力',
        header: 'B',
        pets: [
          Pet(
            petId: 'wz',
            petName: '雪影娃娃',
            nature: '固执',
            evsList: ['物攻', '物防', '生命'],
            skills: ['暴风雪', '冰墙', '冬至', '超级糖果'],
            bloodline: '首领',
            bloodlineLetter: 'T',
          ),
        ],
      );

  group('给 AI 助手的描述（超浓缩版）', () {
    test('开头点明用途 + 魔法，不写解释性文字', () {
      final text = codec.toGameText(realTeam());
      expect(text.startsWith('配队 '), isTrue,
          reason: '要有一个引导词，否则助手容易只回一句"好的，收到了"');
      expect(text, contains('魔法=进化之力'));
    });

    test('**不含阵容码**', () {
      final team = realTeam();
      final text = codec.toGameText(team);
      final code = codec.encode(team);

      expect(text.contains(code), isFalse, reason: '整串码不该出现');
      // 码的特征字符也要查：分隔符和段
      expect(text.contains('~'), isFalse, reason: '出现了 ~ 说明码混进去了');
      for (final seg in code.split('~').take(4)) {
        if (seg.length > 2) {
          expect(text.contains(seg), isFalse,
              reason: '码片段「$seg」混进了导出文本');
        }
      }
    });

    test('**不含队伍名**', () {
      final text = codec.toGameText(realTeam());
      expect(text.contains('队伍3'), isFalse,
          reason: '名字是玩家自己起的，对助手没有信息量');
      expect(text.contains('###'), isFalse,
          reason: '原来用 ### 队伍名 做标题，现在不该有');
      expect(text.contains('#'), isFalse, reason: '不该有任何 # 前缀行');
    });

    test('保留配队需要的要素：魔法 / 精灵 / 性格 / 技能 / 血脉', () {
      final text = codec.toGameText(realTeam());
      expect(text, contains('进化之力'));
      expect(text, contains('雪影娃娃'));
      expect(text, contains('固执'));
      expect(text, contains('暴风雪'));
      expect(text, contains('超级糖果'));
      expect(text, contains('首领'));
    });

    test('**砍掉个体资质** —— 用户明确不要，它不影响配队', () {
      final text = codec.toGameText(realTeam());
      expect(text.contains('资质'), isFalse);
      // 六维的具体取值也不该出现（它们只从资质来）
      for (final dim in const ['物攻', '魔攻', '物防', '魔防', '生命', '速度']) {
        expect(text.contains(dim), isFalse, reason: '$dim 来自个体资质，应当砍掉');
      }
    });

    test('没有字段标签、没有换行冗余、没有括号分隔符', () {
      final text = codec.toGameText(realTeam());
      for (final noise in const ['性格', '血脉', '技能', '个体', '：', '；', '{', '}', '、', '- ']) {
        expect(text.contains(noise), isFalse,
            reason: '「$noise」是纯装饰，占额度但没有信息量');
      }
      // 不能有空行（空行也是要发的字符）
      expect(text.contains('\n\n'), isFalse);
    });

    test('每只精灵一行，顺序是 名字 性格 血脉 技能', () {
      final text = codec.toGameText(realTeam());
      final lines = text.split('\n');
      expect(lines.length, 2, reason: '1 行表头 + 1 只精灵');
      // 夹具里这只就是 4 个技能 —— 别凭印象写，会漏
      expect(lines[1].split(' '),
          ['雪影娃娃', '固执', '首领', '暴风雪', '冰墙', '冬至', '超级糖果']);
    });

    test('**整份文本足够短** —— 这才是这个格式存在的理由', () {
      // 用户实测完整版（333 字 / 11 行）超过了官方助手的输入限制。
      // 这里盯住上限，防止以后有人"为了可读性"把标签加回来。
      final text = codec.toGameText(realTeam());
      expect(text.length, lessThanOrEqualTo(60),
          reason: '单只精灵的描述要压在 60 字以内，实际 ${text.length} 字');
      expect(text.length, greaterThan(10), reason: '别压到没信息了');
    });

    test('无血脉时整段省掉，不写占位符（历史 bug：兜底成「首领」）', () {
      final team = Team(
        name: 'x',
        magic: '进化之力',
        header: 'B',
        pets: [
          Pet(
            petId: 'wz',
            petName: '雪影娃娃',
            nature: '固执',
            evsList: ['物攻'],
            skills: ['冰墙'],
            bloodline: '',
            bloodlineLetter: 'A',
          ),
        ],
      );
      final text = codec.toGameText(team);
      // 空血脉整段省掉（不再写「无血脉」占位）——
      // 空血脉被兜底成"首领"是实际发生过的 bug，所以仍然要断言它没出现
      expect(text.contains('首领'), isFalse);
      expect(text.contains('无血脉'), isFalse,
          reason: '省掉比写占位符更省额度');
      final line = text.split('\n')[1];
      expect(line.split(' '), ['雪影娃娃', '固执', '冰墙'],
          reason: '顺序：名字 性格 血脉(空则跳过) 技能');
    });

    test('六只精灵全部出现且顺序不变', () {
      final rt = normalizeVlmOutput({
        'magic': '进化之力',
        'pets': [
          {'name': '雪影娃娃', 'nature': '固执', 'skills': []},
          {'name': '月牙雪熊', 'nature': '固执', 'skills': []},
          {'name': '尖嘴狐仙', 'nature': '开朗', 'skills': []},
          {'name': '卡瓦重（雪山附近的样子）', 'nature': '慎重', 'skills': []},
          {'name': '饮雪狂兽', 'nature': '慎重', 'skills': []},
          {'name': '寂灭骨龙', 'nature': '开朗', 'skills': []},
        ],
      }, codec: codec, tables: _tables());
      final text = codec.toGameText(toCodecTeam(rt, const {},
        tables: _tables(),
      ));

      final order = [
        '雪影娃娃', '月牙雪熊', '尖嘴狐仙', '卡瓦重', '饮雪狂兽', '寂灭骨龙',
      ];
      var cursor = 0;
      for (final name in order) {
        final at = text.indexOf(name, cursor);
        expect(at, greaterThanOrEqualTo(0), reason: '缺 $name');
        cursor = at + name.length;
      }
    });

    test('技能为空的精灵也不会产生空花括号', () {
      final team = Team(
        name: 'x',
        magic: '进化之力',
        header: 'B',
        pets: [
          Pet(
            petId: 'wz',
            petName: '雪影娃娃',
            nature: '固执',
            evsList: ['物攻'],
            skills: [],
            bloodline: '',
            bloodlineLetter: 'A',
          ),
        ],
      );
      final text = codec.toGameText(team);
      expect(text.contains('{}'), isFalse);
      expect(text.contains('技能'), isFalse,
          reason: '没有技能时不写技能段');
      // 只剩「名字 性格」两段，不能拖尾空格
      final line = text.split('\n')[1];
      expect(line, '雪影娃娃 固执');
      expect(line.endsWith(' '), isFalse);
    });

    test('队伍名改了也不影响导出文本', () {
      final a = realTeam();
      final b = Team(
        name: '完全不同的名字',
        magic: a.magic,
        header: a.header,
        pets: a.pets,
      );
      expect(codec.toGameText(b), codec.toGameText(a),
          reason: '队伍名不进导出文本，所以改名字不该影响它');
    });
  });
}
