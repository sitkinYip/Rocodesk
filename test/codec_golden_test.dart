/// 阵容码编解码器的**等价性**测试。
///
/// 夹具由 Python 端 `tools/make_golden_fixture.py` 生成，里面冻结了：
///   * 593 条真实线上阵容码的解码字段 + 逐字节往返结果；
///   * 8 个构造用例（名称 -> 码）；
///   * 77 个名称解析用例；
///   * 性格/资质/血脉/魔法四张表。
///
/// Dart 实现必须与 Python **逐字段一致**。任何漂移都在这里失败。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rocodesk/core/codec_tables.dart';
import 'package:rocodesk/core/models.dart';
import 'package:rocodesk/core/teamcodec.dart';

const _dataDir = 'assets/data';
const _goldenPath = 'assets/golden/teamcode_golden.json';

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// 取字符串 `at` 位置起的 8 个字符，越界返回 `<end>`。
/// 抽成函数是因为内联进 `${...}` 会让 Dart 的引号嵌套无法解析。
String _sliceAt(String s, int at) {
  if (at >= s.length) return '<end>';
  final end = at + 8 > s.length ? s.length : at + 8;
  return s.substring(at, end);
}

/// 夹具是否在仓库里。
///
/// 它是 2.73 MB 的生成物（593 条真实阵容码的逐字段快照）。带上它，
/// clone 下来的人不用先跑生成脚本就能验证编解码器；不想带它也可以删掉 ——
/// 那时这一组测试会**显式跳过**并提示怎么重新生成，而不是静默通过。
///
/// 重新生成：`python tools/make_golden_fixture.py`（用仓库外的知识库）
bool _hasGolden() => File(_goldenPath).existsSync();

void main() {
  late CodecTables tables;
  late TeamCodec codec;
  late Map<String, dynamic> golden;

  setUpAll(() {
    // 测试直接读文件，绕开 Flutter 资产层，跑得快且不依赖 binding。
    tables = CodecTables.fromMaps(
      pets: _readJson('$_dataDir/pets.json'),
      skills: _readJson('$_dataDir/skills.json'),
      natures: _readJson('$_dataDir/natures.json'),
      codec: _readJson('$_dataDir/codec.json'),
    );
    codec = TeamCodec(tables);
    golden = _hasGolden()
        ? _readJson(_goldenPath)
        : const <String, dynamic>{};
  });

  // 没有夹具时跳过整组，理由写在 skip 里 —— 用 skip 而不是悄悄 return，
  // 这样测试报告里能看出"没跑"而不是"通过了"。
  final skipIfNoGolden = _hasGolden()
      ? null
      : '缺少 $_goldenPath（2.73 MB 的生成物，可删）。'
          '重新生成：python tools/make_golden_fixture.py';

  test('数据表与 Python 端一致', () {
    final t = golden['tables'] as Map<String, dynamic>;

    expect(tables.petNames.length, 623);
    expect(tables.skillNames.length, 579);

    expect(tables.natureByLetter,
        (t['NATURE'] as Map<String, dynamic>).cast<String, String>());
    expect(tables.bloodline,
        (t['BLOODLINE'] as Map<String, dynamic>).cast<String, String>(),
        reason: '血脉表必须与 Python 完全一致');
    expect(tables.evs,
        (t['EVS'] as Map<String, dynamic>).cast<String, String>());
    expect(tables.magic,
        (t['MAGIC'] as Map<String, dynamic>).cast<String, String>());

    expect(tables.defaultBloodlineLetter, t['DEFAULT_BLOODLINE_LETTER']);
    expect(tables.unknownPet, t['UNKNOWN_PET']);
    expect(tables.defaultBloodlineText, t['DEFAULT_BLOODLINE_TEXT']);
    }, skip: skipIfNoGolden);

  test('593 条真实阵容码：解码字段逐项一致', () {
    final corpus = (golden['corpus'] as List).cast<Map<String, dynamic>>();
    expect(corpus, isNotEmpty, reason: '夹具里必须有真实码');

    var checked = 0;
    final mismatches = <String>[];

    for (final entry in corpus) {
      final code = entry['code'] as String;
      final short = code.substring(0, 16);

      final Team got;
      try {
        got = codec.decode(code);
      } catch (e) {
        mismatches.add('$short… 解码抛错: $e');
        continue;
      }

      void cmp(String what, Object? a, Object? b) {
        if ('$a' != '$b') mismatches.add('$short… $what: dart=$a python=$b');
      }

      cmp('name', got.name, entry['name']);
      cmp('magic_code', got.magicCode, entry['magic_code']);
      cmp('magic', got.magic, entry['magic']);
      cmp('header', got.header, entry['header']);
      cmp('count_letter', got.countLetter, entry['count_letter']);
      cmp('tail_marker', got.tailMarker, entry['tail_marker']);

      final wantPets = (entry['pets'] as List).cast<Map<String, dynamic>>();
      cmp('pet_count', got.pets.length, wantPets.length);
      for (var i = 0; i < wantPets.length && i < got.pets.length; i++) {
        final w = wantPets[i];
        final p = got.pets[i];
        final tag = 'pet[$i](${w['pet_name']})';
        cmp('$tag.pet_id', p.petId, w['pet_id']);
        cmp('$tag.pet_name', p.petName, w['pet_name']);
        cmp('$tag.bloodline_letter', p.bloodlineLetter, w['bloodline_letter']);
        cmp('$tag.bloodline', p.bloodline, w['bloodline']);
        cmp('$tag.nature_letter', p.natureLetter, w['nature_letter']);
        cmp('$tag.nature', p.nature, w['nature']);
        cmp('$tag.nature_up', p.natureUp, w['nature_up']);
        cmp('$tag.nature_down', p.natureDown, w['nature_down']);
        cmp('$tag.ev_code', p.evCode, w['ev_code']);
        cmp('$tag.evs_list', p.evsList.join(','),
            (w['evs_list'] as List).join(','));
        cmp('$tag.skills', p.skills.join(','), (w['skills'] as List).join(','));
        cmp('$tag.skill_codes', p.skillCodes.join(','),
            (w['skill_codes'] as List).join(','));
        cmp('$tag.skill_slots', p.skillSlots.join(','),
            (w['skill_slots'] as List).join(','));
        cmp('$tag.tail_up', p.tailUp, w['tail_up']);
        cmp('$tag.tail_down', p.tailDown, w['tail_down']);
      }
      checked++;
      if (mismatches.length > 12) break; // 够定位即可，别刷屏
    }

    expect(mismatches, isEmpty, reason: mismatches.take(12).join('\n'));
    expect(checked, corpus.length, reason: '所有真实码都必须解码成功');
  }, skip: skipIfNoGolden);

  test('593 条真实阵容码：重新编码与原码逐字节相同', () {
    final corpus = (golden['corpus'] as List).cast<Map<String, dynamic>>();
    final failures = <String>[];

    for (final entry in corpus) {
      final code = entry['code'] as String;
      final want = entry['reencoded'] as String;
      final short = code.substring(0, 16);

      // 先确认 Python 侧确实无损往返，否则夹具本身有问题
      if (entry['roundtrip_ok'] != true) {
        failures.add('$short… 夹具标记 roundtrip_ok=false');
        continue;
      }

      final got = codec.encode(codec.decode(code));
      if (got != want) {
        var at = 0;
        while (at < got.length && at < want.length && got[at] == want[at]) {
          at++;
        }
        failures.add('$short… 首个差异 @$at: '
            'dart=${_sliceAt(got, at)} python=${_sliceAt(want, at)}');
      }
      if (failures.length > 8) break;
    }

    expect(failures, isEmpty, reason: failures.join('\n'));
  }, skip: skipIfNoGolden);

  test('构造用例：名称 -> 码 与 Python 一致', () {
    final cases = (golden['construct'] as List).cast<Map<String, dynamic>>();
    expect(cases, isNotEmpty);

    for (final c in cases) {
      final label = c['label'] as String;
      final wantCode = c['expected_code'] as String;
      final wantErr = c['expected_error'] as String;

      final pets = (c['pets'] as List).cast<Map<String, dynamic>>().map((p) {
        return Pet(
          petId: (p['pet_id'] as String?) ?? '',
          petName: (p['pet_name'] as String?) ?? '',
          nature: (p['nature'] as String?) ?? '',
          evsList: ((p['evs_list'] as List?) ?? const []).cast<String>(),
          skills: ((p['skills'] as List?) ?? const []).cast<String>(),
          bloodlineLetter: (p['bloodline_letter'] as String?) ?? '',
          tailUp: (p['tail_up'] as String?) ?? 'A',
          tailDown: (p['tail_down'] as String?) ?? 'A',
        );
      }).toList();

      final team = Team(
        name: c['name'] as String,
        magic: c['magic'] as String,
        // header/countLetter/tailMarker 必须照夹具设置：Python 的 Team 默认
        // header='B'、tailMarker='F'，Dart 端如果漏了就会少掉开头的 'B~'。
        header: (c['header'] as String?) ?? 'B',
        countLetter: (c['count_letter'] as String?) ?? '',
        tailMarker: (c['tail_marker'] as String?) ?? 'F',
        pets: pets,
      );

      String gotCode = '';
      String gotErr = '';
      try {
        gotCode = codec.encode(team);
      } catch (e) {
        gotErr = e.toString();
      }

      if (wantErr.isEmpty) {
        expect(gotErr, isEmpty, reason: '「$label」Dart 抛错但 Python 成功: $gotErr');
        expect(gotCode, wantCode, reason: '「$label」编码结果不一致');
      } else {
        // Python 报错的用例：Dart 也必须报错（文案不要求逐字一致）
        expect(gotErr, isNotEmpty,
            reason: '「$label」Python 报错「$wantErr」但 Dart 成功产出了码');
      }
    }
  }, skip: skipIfNoGolden);

  test('名称解析用例与 Python 一致', () {
    final cases = (golden['resolve_cases'] as List).cast<Map<String, dynamic>>();
    expect(cases, isNotEmpty);

    for (final c in cases) {
      final kind = c['kind'] as String;
      final input = c['input'] as String;
      final want = c['expected'] as String;

      final got = switch (kind) {
        'pet' => codec.resolvePetId(input),
        'nature' => codec.resolveNatureLetter(input),
        'bloodline' => codec.resolveBloodlineLetter(input),
        'skill' => codec.resolveSkillCode(input),
        _ => throw StateError('未知用例类型 $kind'),
      };
      expect(got, want, reason: '$kind「$input」解析不一致');
    }
  }, skip: skipIfNoGolden);

  test('无法解析时抛错而不是静默出废码', () {
    // 精灵名多义：卡瓦重有多个形态，必须要求写完整名称
    expect(() => codec.resolvePetId('卡瓦重'), throwsA(isA<TeamCodeException>()));
    // 不存在的名字
    expect(() => codec.resolvePetId('飞飞钢'), throwsA(isA<TeamCodeException>()));
    // 性格不在表内
    expect(() => codec.resolveNatureLetter('腼腆'), throwsA(isA<TeamCodeException>()));
    // 空阵容
    expect(() => codec.encode(Team(name: 'x')), throwsA(isA<TeamCodeException>()));
    // 空载荷 / 没有 ~ 的载荷
    expect(() => codec.decode(''), throwsA(isA<TeamCodeException>()));
    expect(() => codec.decode('not-a-code'), throwsA(isA<TeamCodeException>()));
  }, skip: skipIfNoGolden);

  test('实机验证过的那串码能正确解码并往返', () {
    // out/最终_图标血脉+全技能.txt 里那串（用户实机导入全部正确）
    const verified =
        'B~Gwz~~~T~C~BQBSBPbC--~bDAi~bDDC~bUFM~2B~~~N~C~BQBSBPbbdi~ayGq~bDDg~bDAi~'
        'wF~~~D~a~BSBPBUa230~bDDC~a20s~a2yg~vi~~~G~X~BQBPBUa0bQ~bDDC~ayIs~bAi4~'
        '0P~~~G~X~BQBPBUayBM~bDEc~bDD-~bAi4~zF~~~I~a~BQBPBTayEo~bFdG~bH4k~bWhm~'
        'ZZH~FA~A~A~A~A~A~A~A~A~A~A~A~';

    final team = codec.decode(verified);
    expect(team.pets.length, 6);
    expect(team.pets.map((p) => p.petName).toList(), [
      '雪影娃娃',
      '月牙雪熊',
      '尖嘴狐仙',
      '卡瓦重（草地附近的样子）',
      '饮雪狂兽',
      '寂灭骨龙',
    ]);
    expect(team.pets.map((p) => p.bloodline).toList(),
        ['首领', '翼', '火', '地', '地', '龙']);
    expect(team.pets.map((p) => p.nature).toList(),
        ['固执', '固执', '沉默', '开朗', '开朗', '沉默']);
    expect(team.pets.map((p) => p.evsList.join('/')).toList(), [
      '物攻/物防/生命',
      '物攻/物防/生命',
      '物防/生命/速度',
      '物攻/生命/速度',
      '物攻/生命/速度',
      '物攻/生命/魔防',
    ]);
    expect(team.pets[0].skills, ['暴风雪', '冰墙', '冬至', '超级糖果']);
    expect(team.magic, '进化之力');
    expect(codec.encode(team), verified);
  }, skip: skipIfNoGolden);
}
