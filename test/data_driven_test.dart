/// 规矩：**新增一项数据，代码零改动**。
///
/// ## 为什么要有这个文件
///
/// 这个仓库出过一个典型事故：`血脉名 → 字母` 这个映射有 **4 份实现**，
/// 其中 3 份是把表抄进代码的常量（分布在 `core/pipeline.dart` 与
/// `features/generator/result_view.dart`），只有 1 份是遍历数据表的。
///
/// 后果不是"不整洁"，而是**热更新静默失灵**：数据包里加一条新血脉，
/// 那 3 份抄的表还是旧的 -> `map[name]` 返回 null -> 调用点静默回落成
/// 「无血脉」-> 出码时血脉丢了，不崩溃、不报错。
///
/// 所以这里用测试把规矩钉住：**给数据表加一条，代码必须自动认。**
///
/// 这类测试的价值在于它**不依赖具体数据** —— 它构造新数据来验证机制，
/// 所以数据怎么更新它都不会过期。反过来，如果哪天有人再抄一份表进去，
/// 这里会立刻红。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rocodesk/core/codec_tables.dart';

Map<String, dynamic> _read(String name) =>
    jsonDecode(File('assets/data/$name').readAsStringSync())
        as Map<String, dynamic>;

/// 真实数据表。
CodecTables _tables() => CodecTables.fromMaps(
      pets: _read('pets.json'),
      skills: _read('skills.json'),
      natures: _read('natures.json'),
      codec: _read('codec.json'),
      learnsets: _read('learnsets.json'),
      variantTypes: _read('variant_types.json'),
      traits: _read('traits.json'),
    );

/// 在真实数据基础上，往血脉表里**加一条现实中不存在的**。
///
/// 用"现实中不存在"的名字（`星` / `星系血脉`）是刻意的：
/// 如果哪天要抄一份写死的表才能过测试，这份测试就会红 ——
/// 而抄表的人不可能知道要抄 `星`。
CodecTables _withNewBloodline() {
  final codec = Map<String, dynamic>.from(_read('codec.json'));
  codec['bloodline'] = {
    ...(codec['bloodline'] as Map<String, dynamic>),
    'Z': '星系血脉',
  };
  codec['bloodlineAlias'] = {
    ...(codec['bloodlineAlias'] as Map<String, dynamic>),
    '星系血脉': 'Z',
    '星系': 'Z',
    '星': 'Z',
  };
  final skills = Map<String, dynamic>.from(_read('skills.json'));
  // 也给一个**真实存在**的技能码标上这个新系别。
  // （不能编一个不存在的码：`skillTypeByName` 的构造只在技能名存在时收录，
  //   编的码会被过滤掉，测试就会因为夹具错误而失败而不是因为机制。）
  final realCode = (skills['by_code'] as Map<String, dynamic>).keys.first;
  skills['type_by_code'] = {
    ...(skills['type_by_code'] as Map<String, dynamic>),
    realCode: '星',
  };
  return CodecTables.fromMaps(
    pets: _read('pets.json'),
    skills: skills,
    natures: _read('natures.json'),
    codec: codec,
    learnsets: _read('learnsets.json'),
  );
}

void main() {
  group('血脉名 -> 字母：唯一实现，且数据驱动', () {
    late CodecTables t;
    setUpAll(() => t = _tables());

    test('三种写法都能查到（全名 / 短名 / X系）', () {
      for (final spelling in const ['火系血脉', '火系', '火']) {
        expect(t.bloodlineLetterFor(spelling), 'D', reason: spelling);
      }
      // 多字系别也要对
      for (final spelling in const ['机械系血脉', '机械系', '机械']) {
        expect(t.bloodlineLetterFor(spelling), 'R', reason: spelling);
      }
      // 特殊血脉
      for (final spelling in const ['首领血脉', '首领']) {
        expect(t.bloodlineLetterFor(spelling), 'T', reason: spelling);
      }
    });

    test('字母原样返回；不认识返回 null（不瞎猜）', () {
      expect(t.bloodlineLetterFor('H'), 'H');
      expect(t.bloodlineLetterFor('Y'), 'Y');
      expect(t.bloodlineLetterFor(''), isNull);
      expect(t.bloodlineLetterFor('这不是血脉'), isNull);
      // 单个中文字不能当成字母（「冰」是系别名，不是字母）
      expect(t.bloodlineLetterFor('冰'), 'H',
          reason: '「冰」要按名字解析，不能因为长度 1 就当成字母');
    });

    test('**数据表加一条，代码自动认** —— 这条是热更新的试金石', () {
      final withNew = _withNewBloodline();
      for (final spelling in const ['星系血脉', '星系', '星']) {
        expect(withNew.bloodlineLetterFor(spelling), 'Z',
            reason: '数据表里有这条，代码就该认：$spelling');
      }
      expect(withNew.bloodlineLetterFor('Z'), 'Z');
    });

    test('新系别也进 knownTypes（不再写死 18 个）', () {
      final base = t.knownTypes;
      expect(base, contains('火'));
      expect(base.length, greaterThanOrEqualTo(18),
          reason: '至少覆盖 18 个系别');

      final withNew = _withNewBloodline();
      expect(withNew.knownTypes, contains('星'),
          reason: 'knownTypes 必须从数据表推导，否则新系别会被当成"未知属性"');
    });
  });

  group('不变量：代码里不许再出现"数据宇宙"的副本', () {
    // 这几条是**源码级**断言，直接读 .dart 文件。
    // 目的是让"再抄一份映射表进去"这件事在 CI 上立刻失败。
    //
    // ⚠️ 判据要收得够紧，否则会误伤：
    //   * `vlm_client.dart` 的提示词会**提到**系别名（那是给模型的说明，不是映射）
    //   * `type_colors.dart` 是「系别 -> 颜色」，是设计资产，不是这张映射
    // 所以只找「中文 -> 单个 ASCII 字母」的映射字面量。

    /// 找出文件里「中文键 -> 单字母值」的映射对数。
    int letterMapPairs(String text) {
      // '普通': 'B'   或   ('普通', 'B')
      final mapForm = RegExp(
          r"""['"]([\u4e00-\u9fff]{1,6})['"]\s*:\s*['"]([A-Za-z])['"]""");
      final tupleForm = RegExp(
          r"""\(\s*['"]([A-Za-z])['"]\s*,\s*['"]([\u4e00-\u9fff]{1,6})['"]\s*\)""");
      return mapForm.allMatches(text).length + tupleForm.allMatches(text).length;
    }

    List<String> offenders(int threshold) {
      final out = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        // 数据层就是"从表里读"的地方，它自己不该被查
        if (f.path.endsWith('codec_tables.dart')) continue;
        if (letterMapPairs(f.readAsStringSync()) >= threshold) out.add(f.path);
      }
      return out;
    }

    test('18 个系别的「名 -> 字母」表不再出现（阈值 5）', () {
      const offendersThreshold = 5;
      final bad = offenders(offendersThreshold);
      expect(bad, isEmpty,
          reason: '这些文件里又抄了「系别名 -> 字母」的表，'
              '应该改成 tables.bloodlineLetterFor()：\n  ${bad.join('\n  ')}');
    });

    test('源码里不再有 kKnownTypes 那样的写死系别集合', () {
      final bad = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final text = f.readAsStringSync();
        // `const Set<String> kKnownTypes = { '普通', '火', ... }` 这种
        if (RegExp(r'const\s+Set<String>\s+\w*[Tt]ypes?\w*\s*=\s*\{')
            .hasMatch(text)) {
          bad.add(f.path);
        }
      }
      expect(bad, isEmpty,
          reason: '这些文件里写死了系别集合，应该用 CodecTables.knownTypes：\n'
              '  ${bad.join('\n  ')}');
    });

    test('默认文案不写死 —— 必须来自 codec.json.defaults', () {
      // `codec.json.defaults` 里有 8 个默认值。界面与逻辑里再写一份字面量
      // 就是又一份会漂移的副本：数据表换了、代码里还是旧值，
      // 于是"码里编出来的东西"和"界面上显示的东西"对不上。
      final defaults = _read('codec.json')['defaults'] as Map<String, dynamic>;
      // 只查含中文的那几个（纯 ASCII 的 BPBRBU / V / T 在别处有合法用途）
      final zhValues = defaults.values
          .whereType<String>()
          .where((v) => RegExp(r'[\u4e00-\u9fff]').hasMatch(v))
          .toList();
      expect(zhValues, isNotEmpty, reason: '数据表里应当有中文默认值');

      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final lines = f.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('//')) continue; // 注释里提到不算
          for (final v in zhValues) {
            if (line.contains("'$v'") || line.contains('"$v"')) {
              offenders.add('${f.path}:${i + 1} 含「$v」');
            }
          }
        }
      }
      expect(offenders, isEmpty,
          reason: '这些地方把默认文案写死了，应该用 tables.defaultXxx：\n'
              '  ${offenders.join('\n  ')}');
    });
  });
}
