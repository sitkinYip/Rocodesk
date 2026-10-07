/// 阵容码解析的测试。
///
/// 两条路径共用同一个结果页：
///   * 识别：截图 -> 模型 -> [toCodecTeam]
///   * 解析：阵容码 -> [TeamCodec.decode] -> [toRecognizedTeam]
///
/// 所以这里重点测**逆变换**：解码出来的队伍转成界面模型后，
/// 必须与原始队伍逐字段一致，否则用户会看到"解析对了但显示错了"。
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

  group('解码 -> 界面模型', () {
    test('实机验证过的那串码：逐字段还原', () {
      // 用户实机确认过的阵容（6 只 / 魔法 进化之力）
      final rt = normalizeVlmOutput({
        'magic': '进化之力',
        'team_name': '队伍3',
        'pets': [
          {
            'name': '雪影娃娃', 'nature': '固执',
            'evs': ['物攻', '物防', '生命'],
            'skills': ['暴风雪', '冰墙', '冬至', '超级糖果'],
            'bloodline': '首领', 'bloodline_letter': 'T',
          },
          {
            'name': '月牙雪熊', 'nature': '固执',
            'evs': ['物攻', '物防', '生命'],
            'skills': ['双星', '先发制人', '冰点', '冰墙'],
          },
          {
            'name': '尖嘴狐仙', 'nature': '开朗',
            'evs': ['物防', '生命', '速度'],
            'skills': ['焚烧烙印', '冬至', '火焰护盾', '炎枪'],
          },
          {
            'name': '卡瓦重（雪山附近的样子）', 'nature': '慎重',
            'evs': ['物攻', '生命', '速度'],
            'skills': ['筛管奔流', '冬至', '晒太阳', '跺地'],
          },
          {
            'name': '饮雪狂兽', 'nature': '慎重',
            'evs': ['物攻', '生命', '速度'],
            'skills': ['力量增效', '雪原狩猎', '冷凝', '跺地'],
          },
          {
            'name': '寂灭骨龙', 'nature': '开朗',
            'evs': ['物攻', '生命', '魔防'],
            'skills': ['借用', '隼鳞', '电弧', '报复'],
            'bloodline': '龙', 'bloodline_letter': 'I',
          },
        ],
      }, codec: codec, tables: tables);

      final original = toCodecTeam(rt, const {});
      final code = codec.encode(original);

      // 走解析路径
      final parsed = codec.decode(code);
      final shown = toRecognizedTeam(parsed, tables);

      expect(shown.pets.length, 6);
      expect(shown.magic, '进化之力');
      // 队伍名**不在阵容码里**（码就是纯段数据），所以解码只能拿到兜底名。
      // 这是刻意的：解码器保证"任何时候都有一支可展示的队伍"，
      // 而不是留一堆 null 让界面去处理。
      expect(parsed.name, '未命名队伍',
          reason: '阵容码不含队伍名，解码器应填兜底名而不是留空');

      for (var i = 0; i < 6; i++) {
        final a = original.pets[i];
        final b = shown.pets[i];
        expect(b.name, a.petName, reason: '第 ${i + 1} 只的名字');
        expect(b.petId, a.petId, reason: '第 ${i + 1} 只的精灵码');
        expect(b.nature, a.nature, reason: '第 ${i + 1} 只的性格');
        expect(b.evs, a.evsList, reason: '第 ${i + 1} 只的个体资质');
        expect(b.skills, a.skills, reason: '第 ${i + 1} 只的技能');
        expect(b.bloodlineLetter, a.bloodlineLetter,
            reason: '第 ${i + 1} 只的血脉字母');
        // 解码出来的必须是"已确定"状态，界面才允许直接出码
        expect(b.resolved, isTrue, reason: '第 ${i + 1} 只应当标记为已解析');
      }

      // 血脉名要还原成**界面用的短名**（阵容码里只有字母）。
      // 注意不能从 codec 表里直接查 —— 那里是全名「首领血脉」「龙系血脉」，
      // 而界面会自己拼上「血脉」二字，全名会导致「龙系血脉血脉」。
      expect(shown.pets[0].bloodline, '首领');
      expect(shown.pets[5].bloodline, '龙');
      for (final p in shown.pets) {
        expect(p.bloodline.endsWith('血脉'), isFalse,
            reason: '血脉名必须是短名（界面自己拼「血脉」）。'
                '实际拿到「${p.bloodline}」说明查了全名表');
      }
    });

    test('往返之后重新出码与原码完全相同', () {
      final original = codec.decode(
        'B~Gzg~~~H~V~BQBPBUbDCa~ayIs~a0bQ~bC_S~31~~~I~c~BQBPBTbFcK~a23C~a2y0~ax-E~u8~~~M~Y~BPBRBUa7qY~bDBy~bAls~a0ao~wF~~~G~C~BSBPBTbAkI~a20s~a230~a22G~yQ~~~M~C~BQBPBUa5PY~bPL6~bPOk~bPNe~vD~~~T~V~BQBPBUayI2~ayGq~ayAu~bY86~ZZH~FA~A~A~A~A~A~A~A~A~A~A~A~',
      );
      final shown = toRecognizedTeam(original, tables);
      final reencoded = codec.encode(toCodecTeam(shown, const {}));
      expect(reencoded, original.payload,
          reason: '解析后原样再出码，必须逐字节相同（否则用户改一个字就毁码）');
    });
  });

  group('解码路径与识别路径的差异（刻意为之）', () {
    late RecognizedTeam shown;
    setUpAll(() {
      shown = toRecognizedTeam(
        codec.decode(
          'B~Gzg~~~H~V~BQBPBUbDCa~ayIs~a0bQ~bC_S~31~~~I~c~BQBPBTbFcK~a23C~a2y0~ax-E~u8~~~M~Y~BPBRBUa7qY~bDBy~bAls~a0ao~wF~~~G~C~BSBPBTbAkI~a20s~a230~a22G~yQ~~~M~C~BQBPBUa5PY~bPL6~bPOk~bPNe~vD~~~T~V~BQBPBUayI2~ayGq~ayAu~bY86~ZZH~FA~A~A~A~A~A~A~A~A~A~A~A~',
        ),
        tables,
      );
    });

    test('不产生形态候选 —— 码里已经确定了是哪只', () {
      for (final p in shown.pets) {
        expect(p.variants, isEmpty,
            reason: '阵容码里是确定的精灵码，不存在形态歧义');
        expect(p.needsVariantChoice, isFalse);
      }
    });

    test('不产生技能纠错候选 —— 码里的技能名是准确的', () {
      for (final p in shown.pets) {
        expect(p.skillSuggestions, isEmpty,
            reason: '没有 OCR，就不该提示"可能看错了"');
      }
    });

    test('系别为空 —— 阵容码里没有系别，界面据此不显示系别标签', () {
      for (final p in shown.pets) {
        expect(p.types, isEmpty,
            reason: '不能凭空猜系别；留空让界面不显示，比显示错的强');
      }
    });
  });

  group('数据表认不出的码：保留 + 警告，不整体失败', () {
    test('未知精灵码仍能展示，但带警告', () {
      // 造一个数据表里不存在的精灵码
      final fake = Team(
        name: '测试',
        magic: '进化之力',
        header: 'B',
        pets: [
          Pet(
            petId: 'ZZ',
            petName: '',
            nature: '固执',
            evsList: const ['物攻'],
            skills: const ['冰墙'],
            bloodline: '首领',
            bloodlineLetter: 'T',
          ),
        ],
      );
      final shown = toRecognizedTeam(fake, tables);

      expect(shown.pets.length, 1);
      // 名字兜底用码本身，界面不至于是空白
      expect(shown.pets.single.name, 'ZZ');
      expect(shown.pets.single.warnings, isNotEmpty,
          reason: '不认识的码必须明确标出来');
      expect(shown.pets.single.warnings.join(), contains('ZZ'));
    });

    test('未知血脉字母仍能展示，并记一条队伍级警告', () {
      final fake = Team(
        name: '测试',
        magic: '进化之力',
        header: 'B',
        pets: [
          Pet(
            petId: 'wz',
            petName: '',
            bloodline: '',
            bloodlineLetter: 'Z', // 不在 24 条里
          ),
        ],
      );
      final shown = toRecognizedTeam(fake, tables);
      expect(shown.pets.single.bloodline, isEmpty);
      expect(shown.warnings, isNotEmpty);
      expect(shown.warnings.join(), contains('Z'));
    });

    test('「无血脉」哨兵值 A 不产生任何警告', () {
      final fake = Team(
        name: '测试',
        magic: '进化之力',
        header: 'B',
        pets: [
          Pet(
            petId: 'wz',
            petName: '',
            bloodline: '',
            bloodlineLetter: 'A',
          ),
        ],
      );
      final shown = toRecognizedTeam(fake, tables);
      expect(shown.pets.single.bloodline, isEmpty);
      expect(shown.pets.single.warnings, isEmpty,
          reason: '「无血脉」是正常状态，不是错误');
      expect(shown.warnings, isEmpty);
      expect(shown.pets.single.resolved, isTrue);
    });

    test('名字以数据表为准，不信任传入的 petName', () {
      final fake = Team(
        name: '测试',
        magic: '进化之力',
        header: 'B',
        // 故意塞一个错的名字
        pets: [Pet(petId: 'wz', petName: '完全错误的名字')],
      );
      final shown = toRecognizedTeam(fake, tables);
      expect(shown.pets.single.name, '雪影娃娃',
          reason: '名字应当从精灵码反查，而不是信任来源');
    });
  });

  group('解码本身对坏输入要报错，不能静默出废数据', () {
    test('空串抛错', () {
      expect(() => codec.decode(''), throwsA(isA<TeamCodeException>()));
    });

    test('乱写的码抛错', () {
      expect(() => codec.decode('这不是一个阵容码'),
          throwsA(isA<TeamCodeException>()));
    });

    test('长度对但段位错的码抛错', () {
      expect(() => codec.decode('X2wa0CAATR~BVl'),
          throwsA(isA<TeamCodeException>()));
    });
  });
}
