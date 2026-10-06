/// 资产文件名必须是 ASCII —— 否则 Flutter Web 上永远 404。
///
/// 这是一次真实事故的回归防线（用户报告白屏 + 技能图标不显示）：
///
///  1. `flutter build web` 把中文名资产 `一拳.png` 落到磁盘时，
///     文件名是它**字面的百分号编码**字节 —— hex 验证过：
///     `25 45 34 25 42 38` 就是 `%E4%B8%80...` 这 14 个 ASCII 字符。
///  2. 运行时框架按 manifest 里的原始中文键请求 `.../skill/一拳.png`，
///     任何正常服务器会把它解码回 `%E4%B8%80%E6%8B%B3.png`，
///     而磁盘上那个文件的**名字**正是这串字符，于是要找的是双重编码。
///  3. 结果：每一个 CJK 文件名资产都 404。ASCII 名（血脉图标 `T.png`）
///     却能正常加载 —— 这个对比是定位问题的关键线索。
///
/// 所以图标文件一律用 ASCII 名（技能用技能码，血脉用字母），
/// 名字 -> 路径的映射放在 index.json 里。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 只允许 ASCII 可见字符。
bool _isAscii(String s) => s.codeUnits.every((c) => c > 0x20 && c < 0x7F);

void main() {
  group('资产文件名必须是 ASCII（Flutter Web 限制）', () {
    test('icons 目录下所有文件名都是 ASCII', () {
      final dir = Directory('assets/icons');
      expect(dir.existsSync(), isTrue, reason: '图标目录不存在');

      final offenders = <String>[];
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        final name = f.uri.pathSegments.last;
        if (!_isAscii(name)) offenders.add(f.path.replaceAll('\\', '/'));
      }

      expect(offenders, isEmpty,
          reason: '这些资产文件名含非 ASCII 字符，Flutter Web 上会 404：'
              '\n  ${offenders.take(10).join('\n  ')}'
              '\n修法：用 ASCII 名（如技能码 a0bQ.png），'
              '名字映射放进 assets/icons/index.json。');
    });

    test('data 目录下的文件名也都是 ASCII', () {
      final offenders = Directory('assets/data')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => !_isAscii(n))
          .toList();
      expect(offenders, isEmpty, reason: '数据文件名必须 ASCII：$offenders');
    });
  });

  group('图标索引与文件要一致', () {
    late Map<String, dynamic> index;

    setUpAll(() {
      index = jsonDecode(
        File('assets/icons/index.json').readAsStringSync(),
      ) as Map<String, dynamic>;
    });

    test('索引里每个技能图标的文件都真实存在', () {
      final skill = (index['skill'] as Map<String, dynamic>);
      expect(skill.length, greaterThan(400),
          reason: '技能图标应当覆盖全部可学技能，实测 487 个');

      final missing = <String>[];
      for (final entry in skill.entries) {
        final path = entry.value as String;
        if (!File(path).existsSync()) missing.add('${entry.key} -> $path');
      }
      expect(missing, isEmpty,
          reason: '索引指向了不存在的文件：\n  ${missing.take(5).join('\n  ')}');
    });

    test('索引里每个属性图标的文件都真实存在（18 个系别）', () {
      final type = index['type'] as Map<String, dynamic>;
      expect(type.length, 18, reason: '18 个系别都要有图标');
      for (final t in const [
        '草', '火', '水', '冰', '龙', '恶', '幽', '萌', '翼', '普通',
      ]) {
        expect(type.containsKey(t), isTrue, reason: '缺系别图标：$t');
        expect(File(type[t] as String).existsSync(), isTrue, reason: t);
      }
    });

    test('索引里每个精灵头像的文件都真实存在', () {
      final pet = index['pet'] as Map<String, dynamic>;
      // 542 只：阵容码共 623 个，其中 81 个（多为活动/未收录形态）
      // 在知识库里按全名 join 不上，所以没有头像。
      expect(pet.length, 542, reason: '实测 542 只精灵码能对上头像');

      final missing = <String>[];
      for (final entry in pet.entries) {
        if (!File(entry.value as String).existsSync()) missing.add(entry.key);
      }
      expect(missing, isEmpty, reason: '缺头像：${missing.take(5)}');
    });

    test('精灵头像的键是**阵容码**，文件名是数字 id（避开大小写冲突）', () {
      final pet = index['pet'] as Map<String, dynamic>;
      // 两套编号体系不同，搞混了界面就全是占位图
      expect(pet.containsKey('vi'), isTrue, reason: 'vi 是卡瓦重草地形态的阵容码');
      expect(pet.containsKey('wz'), isTrue, reason: 'wz 是雪影娃娃的阵容码');
      expect(pet.containsKey('108'), isFalse,
          reason: '108 是知识库 id，不是阵容码，不该做索引的键');

      // 但**文件名**必须是数字 id：阵容码区分大小写（0f vs 0F 是两只不同的
      // 精灵），而 Windows 文件名不区分 —— 直接用码命名会互相覆盖，
      // 实测 542 个文件只能枚举出 385 个，且 Flutter 打包靠遍历目录，
      // 那 157 个会静默丢失。
      for (final entry in pet.entries) {
        final file = (entry.value as String).split('/').last;
        expect(RegExp(r'^\d+\.png$').hasMatch(file), isTrue,
            reason: '${entry.key} 的文件名 "$file" 不是纯数字 id —— '
                '大小写不同的阵容码会指向同一个文件');
      }
    });

    test('文件名在忽略大小写后仍然唯一（这是丢文件的根因）', () {
      // Windows 文件名不区分大小写。任何两个文件只差大小写都会互相覆盖，
      // 而且失败是静默的（打包不报错，只是 404）。
      final all = <String>[];
      for (final group in ['bloodline', 'type', 'skill', 'pet']) {
        final dir = Directory('assets/icons/$group');
        for (final f in dir.listSync().whereType<File>()) {
          all.add('$group/${f.uri.pathSegments.last.toLowerCase()}');
        }
      }
      final seen = <String>{};
      final dupes = <String>[];
      for (final f in all) {
        if (!seen.add(f)) dupes.add(f);
      }
      expect(dupes, isEmpty,
          reason: '这些文件名忽略大小写后重复，会互相覆盖：$dupes');
    });

    test('用户这张图上的 6 只都有头像；技能图标只差 2 个（知识库就没图）', () {
      final pet = index['pet'] as Map<String, dynamic>;
      final skill = index['skill'] as Map<String, dynamic>;

      // 精灵码是**阵容码**体系（实机验证过的那张阵容图）
      for (final code in const ['wz', '2B', 'wF', 'zg', '0P', 'zF']) {
        expect(pet.containsKey(code), isTrue, reason: '缺 $code 的头像');
        expect(File(pet[code] as String).existsSync(), isTrue, reason: code);
      }

      // 这张图上实际出现的技能。除了下面 2 个，全都有图标。
      const onCard = [
        '暴风雪', '冰墙', '冬至', '超级糖果', '双星', '先发制人',
        '焚烧烙印', '火焰护盾', '炎枪', '筛管奔流', '晒太阳', '跺地',
        '力量增效', '隼鳞', '借用', '电弧', '报复',
      ];
      for (final name in onCard) {
        expect(skill.containsKey(name), isTrue, reason: '缺技能图标：$name');
        expect(File(skill[name] as String).existsSync(), isTrue, reason: name);
      }

      // 这两个官方图鉴里就没有 icon_url（实测 97 个技能没图），
      // 界面会退化成首字占位。明确记下来，免得以后以为漏导出了。
      const knownNoArt = ['雪原狩猎', '冷凝'];
      for (final name in knownNoArt) {
        expect(skill.containsKey(name), isFalse,
            reason: '$name 现在有图了？可以把它从 knownNoArt 挪到 onCard');
      }
    });

    test('索引里每个血脉图标的文件都真实存在', () {
      final blood = (index['bloodline'] as Map<String, dynamic>);
      expect(blood.length, 21, reason: '21 条血脉有图标（3 条 CDN 上没有）');

      final missing = <String>[];
      for (final letter in blood.keys) {
        if (!File('assets/icons/bloodline/$letter.png').existsSync()) {
          missing.add(letter);
        }
      }
      expect(missing, isEmpty, reason: '缺图标：$missing');
    });

    test('索引里的路径本身也只能含 ASCII', () {
      for (final group in ['skill', 'bloodline']) {
        final m = index[group] as Map<String, dynamic>;
        for (final entry in m.entries) {
          if (group == 'skill') {
            expect(_isAscii(entry.value as String), isTrue,
                reason: '${entry.key} 的路径含非 ASCII：${entry.value}');
          }
        }
      }
    });

    test('用户实际踩到的那个技能有图标（筛管奔流）', () {
      final skill = index['skill'] as Map<String, dynamic>;
      expect(skill.containsKey('筛管奔流'), isTrue,
          reason: 'OCR 纠错面板要显示它的参考图');
      expect(File(skill['筛管奔流'] as String).existsSync(), isTrue);
    });
  });
}
