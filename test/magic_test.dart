/// 魔法的测试。
///
/// 魔法会直接写进阵容码（段 55），读错或改错整支队伍的魔法就错了。
/// 名字也容易记混 —— 用户就把「愿力强化」记成了「愿力冲击」，
/// 所以这里把三个准确名字钉死。
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
  late CodecTables tables;
  late TeamCodec codec;
  setUpAll(() {
    tables = _tables();
    codec = TeamCodec(tables);
  });

  group('魔法表的准确内容', () {
    test('只有三个，名字必须与官方一致', () {
      expect(tables.magic, {
        'ZZB': '光合治愈',
        'ZZC': '愿力强化',
        'ZZH': '进化之力',
      });
    });

    test('「愿力冲击」不是魔法名 —— 用户记混过，钉住防止被写进表', () {
      expect(tables.magicRev.containsKey('愿力冲击'), isFalse);
      expect(tables.magicRev.containsKey('愿力强化'), isTrue);
    });

    test('魔法名 -> 码 的反查表方向正确', () {
      expect(tables.magicRev['进化之力'], 'ZZH');
      expect(tables.magicRev['光合治愈'], 'ZZB');
      expect(tables.magicRev['愿力强化'], 'ZZC');
    });
  });

  group('识别结果的魔法', () {
    RecognizedTeam teamWithMagic(String magic) => normalizeVlmOutput({
          'magic': magic,
          'pets': [
            {'name': '雪影娃娃', 'nature': '固执', 'skills': []}
          ],
        }, codec: codec, tables: tables);

    test('读到什么就是什么', () {
      expect(teamWithMagic('光合治愈').magic, '光合治愈');
      expect(teamWithMagic('愿力强化').magic, '愿力强化');
      expect(teamWithMagic('进化之力').magic, '进化之力');
    });

    test('没读到就留空，由编码层回落到默认', () {
      expect(teamWithMagic('').magic, isEmpty);
    });

    test('魔法容错字段名（magic / 魔法）', () {
      final rt = normalizeVlmOutput({
        '魔法': '光合治愈',
        'pets': [
          {'name': '雪影娃娃', 'skills': []}
        ],
      }, codec: codec, tables: tables);
      expect(rt.magic, '光合治愈');
    });
  });

  group('三个魔法都能正确编码进阵容码', () {
    /// 取载荷里的魔法段。
    ///
    /// 段位：魔法段在**尾部**，紧跟着的是尾部标记 'F'+第一个覆写字母。
    /// 用「从后往前找 MAGIC 表里的段」定位，比算固定下标稳。
    String magicSeg(String code) {
      final segs = code.split('~');
      for (var i = segs.length - 1; i >= 0; i--) {
        final s = segs[i];
        if (tables.magic.containsKey(s) || tables.magic.containsValue(s)) {
          return s;
        }
        // 尾部标记与覆写字母粘连的形式：'FA'
        if (s.length >= 3 && tables.magic.containsKey(s.substring(s.length - 3))) {
          return s.substring(s.length - 3);
        }
      }
      return '';
    }

    for (final entry in const [
      ('进化之力', 'ZZH'),
      ('光合治愈', 'ZZB'),
      ('愿力强化', 'ZZC'),
    ]) {
      final (name, code3) = entry;
      test('$name -> $code3', () {
        final rt = normalizeVlmOutput({
          'magic': name,
          'pets': [
            {
              'name': '雪影娃娃',
              'nature': '固执',
              'evs': ['物攻', '物防', '生命'],
              'skills': [],
            }
          ],
        }, codec: codec, tables: tables);

        final code = codec.encode(toCodecTeam(rt, const {}));
        expect(magicSeg(code), code3);
        // 往返后魔法名不变
        expect(codec.decode(code).magic, name);
      });
    }
  });

  group('用户手改魔法', () {
    RecognizedTeam baseTeam() => normalizeVlmOutput({
          'magic': '进化之力',
          'pets': [
            {
              'name': '雪影娃娃',
              'nature': '固执',
              'evs': ['物攻', '物防', '生命'],
              'skills': [],
            }
          ],
        }, codec: codec, tables: tables);

    test('手改优先于模型识别的结果', () {
      final rt = baseTeam();
      expect(rt.magic, '进化之力', reason: '模型读的是进化之力');

      final code = codec.encode(
        toCodecTeam(rt, const {}, magicOverride: '光合治愈'),
      );
      expect(codec.decode(code).magic, '光合治愈',
          reason: '用户改成光合治愈后必须生效');
    });

    test('三个魔法互相切换都生效', () {
      for (final m in const ['进化之力', '光合治愈', '愿力强化']) {
        final code = codec.encode(
          toCodecTeam(baseTeam(), const {}, magicOverride: m),
        );
        expect(codec.decode(code).magic, m, reason: m);
      }
    });

    test('覆盖为空串时回落到模型识别的结果，而不是变成空魔法', () {
      final rt = baseTeam();
      final code = codec.encode(
        toCodecTeam(rt, const {}, magicOverride: ''),
      );
      expect(codec.decode(code).magic, '进化之力');
    });

    test('非法魔法名会被 codec 拒绝，不会静默出废码', () {
      final rt = baseTeam();
      expect(
        () => codec.encode(
          toCodecTeam(rt, const {}, magicOverride: '愿力冲击'),
        ),
        throwsA(isA<TeamCodeException>()),
        reason: '「愿力冲击」不是合法魔法名，必须报错而不是写进去',
      );
    });
  });

  group('知识库提供的可选项', () {
    test('界面选项直接来自 magic 表，不是界面里写死的', () {
      // 界面用 tables.magic.values，改了表界面就跟着变
      expect(tables.magic.values.toList()..sort(),
          ['光合治愈', '愿力强化', '进化之力']..sort());
    });
  });
}
