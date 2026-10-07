/// 图标识别相关逻辑的测试。
///
/// 这块从"Python + numpy 模板匹配"改成了"交给多模态模型读图标"，
/// 于是**确定性只剩下一件事**：把模型给出的图标名映射成阵容码字母。
/// 映射错了会直接写进阵容码、影响游戏里的实际配置，所以必须有测试。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rocodesk/core/codec_tables.dart';
import 'package:rocodesk/core/models.dart';
import 'package:rocodesk/core/pipeline.dart';
import 'package:rocodesk/core/teamcodec.dart';

CodecTables _tables() => CodecTables.fromMaps(
      pets: jsonDecode('{"by_code":{"wz":"雪影娃娃"},"by_name":{"雪影娃娃":"wz"}}')
          as Map<String, dynamic>,
      skills: jsonDecode(
              '{"by_code":{"ax9I":"抓挠"},"by_name":{"抓挠":"ax9I"}}')
          as Map<String, dynamic>,
      natures: jsonDecode('{"by_letter":{"C":"固执"},"by_name":{"固执":"C"},'
          '"data":[{"name":"固执","up":"物攻","down":"魔攻"}]}') as Map<String, dynamic>,
      codec: jsonDecode(jsonEncode({
        'evs': {'生命': 'BP', '物攻': 'BQ', '物防': 'BS'},
        'evsRev': {'BP': '生命', 'BQ': '物攻', 'BS': '物防'},
        'bloodline': {
          'B': '普通系血脉', 'C': '草系血脉', 'D': '火系血脉', 'E': '水系血脉',
          'F': '光系血脉', 'G': '地系血脉', 'H': '冰系血脉', 'I': '龙系血脉',
          'J': '电系血脉', 'K': '毒系血脉', 'L': '虫系血脉', 'M': '武系血脉',
          'N': '翼系血脉', 'O': '萌系血脉', 'P': '幽系血脉', 'Q': '恶系血脉',
          'R': '机械系血脉', 'S': '幻系血脉', 'T': '首领血脉', 'U': '巨兽血脉',
          'V': '黑魔法血脉', 'W': '异核血脉', 'X': '污染血脉', 'Y': '奇异血脉',
        },
        'bloodlineAlias': {'首领': 'T', '翼': 'N'},
        'magic': {'ZZH': '进化之力'},
        'magicRev': {'进化之力': 'ZZH'},
        'dimLetters': {'B': '生命'},
        'seg': '~',
        'emptySkill': '00000',
        'emptySkillSeg': 'none',
        'tailMarker': 'F',
        'header': 'B',
        'defaults': {
          'evCode': 'BPBRBQ', 'natureLetter': 'V', 'bloodlineLetter': 'T',
          'bloodlineText': '默认血脉', 'magicName': '进化之力',
          'teamName': '未命名队伍', 'unknownPet': '未知宠物',
          'unknownSkill': '未知技能',
        },
        'evOrder': ['生命'],
        'evThirdGlobal': [['速度', 0.5]],
        'evSecondByFirst': <String, dynamic>{},
        'evThirdByPair': <String, dynamic>{},
      })) as Map<String, dynamic>,
    );

void main() {
  group('血脉图标名 -> 阵容码字母', () {
    late CodecTables t;
    setUp(() => t = _tables());

    test('18 个元素血脉都能映射（图标名是裸名，表里带「系血脉」后缀）', () {
      const expected = {
        '普通': 'B', '草': 'C', '火': 'D', '水': 'E', '光': 'F', '地': 'G',
        '冰': 'H', '龙': 'I', '电': 'J', '毒': 'K', '虫': 'L', '武': 'M',
        '翼': 'N', '萌': 'O', '幽': 'P', '恶': 'Q', '机械': 'R', '幻': 'S',
      };
      expected.forEach((icon, letter) {
        expect(bloodlineLetterFromIcon(icon, t), letter, reason: '图标「$icon」');
      });
    });

    test('6 个特殊血脉都能映射（含最容易认错的首领）', () {
      const expected = {
        '首领': 'T', '巨兽': 'U', '黑魔法': 'V',
        '异核': 'W', '污染': 'X', '奇异': 'Y',
      };
      expected.forEach((icon, letter) {
        expect(bloodlineLetterFromIcon(icon, t), letter, reason: '图标「$icon」');
      });
    });

    test('也接受带后缀的写法（模型可能返回「火系血脉」）', () {
      expect(bloodlineLetterFromIcon('火系血脉', t), 'D');
      expect(bloodlineLetterFromIcon('火系', t), 'D');
      expect(bloodlineLetterFromIcon('首领血脉', t), 'T');
    });

    test('已经给了字母就直接用', () {
      expect(bloodlineLetterFromIcon('T', t), 'T');
      expect(bloodlineLetterFromIcon('I', t), 'I');
    });

    test('"没有血脉"的几种写法都归一成 A，而不是当成错误', () {
      for (final s in ['', '  ', '无', '没有', '无血脉', '未识别', 'none', 'null', '?']) {
        expect(bloodlineLetterFromIcon(s, t), noBloodlineLetter,
            reason: '输入 ${jsonEncode(s)}');
      }
    });

    test('认不出来的名字返回 null（交给调用方提示，不猜）', () {
      expect(bloodlineLetterFromIcon('紫色', t), isNull);
      expect(bloodlineLetterFromIcon('首领血脉·改', t), isNull);
      expect(bloodlineLetterFromIcon('Z', t), isNull,
          reason: 'Z 不在 B..Y 的 24 个字母里');
    });
  });

  group('模型输出规整', () {
    late TeamCodec codec;
    late CodecTables tables;
    setUp(() {
      tables = _tables();
      codec = TeamCodec(tables);
    });

    test('读得到 types 与 bloodline，并映射成字母', () {
      final rt = normalizeVlmOutput({
        'pets': [
          {
            'name': '雪影娃娃',
            'types': ['冰', '萌'],
            'bloodline': '首领',
            'nature': '固执',
            'evs': ['物攻', '物防', '生命'],
            'skills': ['抓挠'],
          }
        ],
      }, codec: codec, tables: tables);

      final p = rt.pets.single;
      expect(p.types, ['冰', '萌']);
      expect(p.bloodline, '首领');
      expect(p.bloodlineLetter, 'T', reason: '首领 -> T');
      expect(p.petId, 'wz');
    });

    test('没有血脉时留空字符串，不编造', () {
      final rt = normalizeVlmOutput({
        'pets': [
          {'name': '雪影娃娃', 'types': ['冰'], 'bloodline': '', 'skills': []}
        ],
      }, codec: codec, tables: tables);
      expect(rt.pets.single.bloodline, isEmpty);
      expect(rt.pets.single.bloodlineLetter, isEmpty,
          reason: '空串在这里表示"没识别到"，编码时会兜底成 A');
    });

    test('模型说「无血脉」时得到 sentinel A（明确的无血脉）', () {
      final rt = normalizeVlmOutput({
        'pets': [
          {'name': '雪影娃娃', 'bloodline': '无血脉', 'skills': []}
        ],
      }, codec: codec, tables: tables);
      expect(rt.pets.single.bloodlineLetter, noBloodlineLetter,
          reason: '"模型明确说没有" 与 "没读到" 要区分开');
      expect(rt.pets.single.warnings, isEmpty,
          reason: '"无血脉"是正常状态，不该产生警告');
    });

    test('血脉认不出来时给出警告，但不阻断', () {
      final rt = normalizeVlmOutput({
        'pets': [
          {'name': '雪影娃娃', 'bloodline': '紫色', 'skills': []}
        ],
      }, codec: codec, tables: tables);
      final p = rt.pets.single;
      expect(p.petId, 'wz', reason: '血脉认不出不该影响精灵识别');
      expect(p.warnings.any((w) => w.contains('紫色')), isTrue);
    });

    test('未知系别会给出警告', () {
      final rt = normalizeVlmOutput({
        'pets': [
          {'name': '雪影娃娃', 'types': ['冰', '彩虹'], 'skills': []}
        ],
      }, codec: codec, tables: tables);
      expect(rt.pets.single.types, contains('彩虹'));
      expect(
        rt.pets.single.warnings.any((w) => w.contains('彩虹')),
        isTrue,
      );
    });

    test('容忍各种字段名写法', () {
      final rt = normalizeVlmOutput({
        'pets': [
          {
            'pet_name': '雪影娃娃',
            'type': '冰',
            '血脉': '首领',
            '性格': '固执',
            '三围': '物攻 物防',
            '技能': '抓挠、抓挠',
          }
        ],
      }, codec: codec, tables: tables);
      final p = rt.pets.single;
      expect(p.name, '雪影娃娃');
      expect(p.types, ['冰'], reason: '单值字符串也要能变成列表');
      expect(p.bloodlineLetter, 'T', reason: '中文字段名也要认');
      expect(p.nature, '固执');
      expect(p.evs, ['物攻', '物防']);
      expect(p.skills, ['抓挠', '抓挠']);
    });
  });

  group('编码时血脉的处理（最关键的回归）', () {
    late TeamCodec codec;
    late CodecTables tables;
    setUp(() {
      tables = _tables();
      codec = TeamCodec(tables);
    });

    /// 取第 1 只精灵在载荷里的血脉位。
    ///
    /// 段位布局（首段是 'B' 时）：[0]='B' [1]=数量字母+精灵码 [2][3]=保留
    /// [4]=**血脉字母** [5]=性格字母 [6]=资质码+技能1 …
    /// 这个布局用 Python 端的 encode 对拍过，两边一致。
    String bloodlineSlot(String code) => code.split('~')[4];

    test('编码结果必须有头段，且段位与 Python 端一致', () {
      // 回归：曾经 encode 在 header 为空时**静默丢掉头段**，整串前移一段。
      // 本地回解看起来正常（解码对 D 的判定兼容两种），但游戏客户端会解析失败。
      final rt = normalizeVlmOutput({
        'pets': [
          {'name': '雪影娃娃', 'bloodline': '首领', 'nature': '固执',
           'evs': ['物攻', '物防', '生命'], 'skills': []}
        ],
      }, codec: codec, tables: tables);

      final team = toCodecTeam(rt, const {},
        tables: _tables(),
      );
      expect(team.header, 'B', reason: 'toCodecTeam 必须设标准头段');

      final code = codec.encode(team);
      final segs = code.split('~');
      expect(segs[0], 'B', reason: '段[0] 必须是头标记');
      expect(segs[1], 'Bwz', reason: '段[1] 必须是数量字母+精灵码');
      expect(segs[2], '', reason: '段[2] 保留位为空');
      expect(segs[3], '', reason: '段[3] 保留位为空');
      expect(segs[4], 'T', reason: '段[4] 是血脉字母');
      expect(segs[5], 'C', reason: '段[5] 是性格字母');

      // 与用户实机验证通过的那串同构：长度 47、10 段
      expect(code.length, 47);
      expect(segs.length, 10);
    });

    test('header 为空时也绝不产出畸形码', () {
      // 即使调用方忘了设 header，encode 也要回落到标准头段
      final team = Team(
        magic: '进化之力',
        header: '',
        pets: [
          Pet(petId: 'wz', petName: '雪影娃娃', natureLetter: 'C',
              evCode: 'BQBSBP', bloodlineLetter: 'T',
              skillSlots: ['', '', '', '']),
        ],
      );
      final code = codec.encode(team);
      expect(code.split('~')[0], 'B');
    });

    test('识别到首领 -> 写 T', () {
      final rt = normalizeVlmOutput({
        'pets': [
          {'name': '雪影娃娃', 'bloodline': '首领', 'nature': '固执',
           'evs': ['物攻', '物防', '生命'], 'skills': []}
        ],
      }, codec: codec, tables: tables);
      final code = codec.encode(toCodecTeam(rt, const {},
        tables: _tables(),
      ));
      expect(bloodlineSlot(code), 'T');
    });

    test('没识别到血脉 -> 写 A（无血脉），**绝不能写 T**', () {
      // 这是历史 bug：codec 的默认值是 'T'（首领），
      // 一旦留空，所有没有血脉的精灵都会在游戏里变成首领。
      final rt = normalizeVlmOutput({
        'pets': [
          {'name': '雪影娃娃', 'bloodline': '', 'nature': '固执',
           'evs': ['物攻', '物防', '生命'], 'skills': []}
        ],
      }, codec: codec, tables: tables);
      final code = codec.encode(toCodecTeam(rt, const {},
        tables: _tables(),
      ));
      expect(bloodlineSlot(code), 'A', reason: '必须显式写 A，不能留空让 codec 用默认 T');
    });

    test('用户手动覆盖优先于模型识别', () {
      final rt = normalizeVlmOutput({
        'pets': [
          {'name': '雪影娃娃', 'bloodline': '首领', 'nature': '固执',
           'evs': ['物攻', '物防', '生命'], 'skills': []}
        ],
      }, codec: codec, tables: tables);
      // 模型说首领(T)，用户改成冰(H)
      final code = codec.encode(toCodecTeam(rt, const {1: '冰'},
        tables: _tables(),
      ));
      expect(bloodlineSlot(code), 'H', reason: '人工指定必须赢过自动识别');
    });

    test('用户覆盖成"无"也是合法的', () {
      final rt = normalizeVlmOutput({
        'pets': [
          {'name': '雪影娃娃', 'bloodline': '首领', 'nature': '固执',
           'evs': ['物攻', '物防', '生命'], 'skills': []}
        ],
      }, codec: codec, tables: tables);
      final code = codec.encode(toCodecTeam(rt, const {1: ''},
        tables: _tables(),
      ));
      expect(bloodlineSlot(code), 'A');
    });
  });
}
