// 命令行调试工具，print 是刻意的输出方式。
// ignore_for_file: avoid_print

// 调试：打印编码结果的全部段，定位血脉位为什么是 'C'
// 纯 Dart 逻辑，用 tool/ 下跑。
import 'dart:convert';
import 'dart:io';

import 'package:rocodesk/core/codec_tables.dart';
import 'package:rocodesk/core/pipeline.dart';
import 'package:rocodesk/core/teamcodec.dart';

Map<String, dynamic> _read(String p) =>
    jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final tables = CodecTables.fromMaps(
    pets: _read('assets/data/pets.json'),
    skills: _read('assets/data/skills.json'),
    natures: _read('assets/data/natures.json'),
    codec: _read('assets/data/codec.json'),
  );
  final codec = TeamCodec(tables);

  final rt = normalizeVlmOutput({
    'pets': [
      {
        'name': '雪影娃娃',
        'types': ['冰', '萌'],
        'bloodline': '首领',
        'nature': '固执',
        'evs': ['物攻', '物防', '生命'],
        'skills': [],
      }
    ],
  }, codec: codec, tables: tables);

  final p = rt.pets.single;
  print('解析结果:');
  print('  name            = ${p.name}');
  print('  petId           = ${p.petId}');
  print('  bloodline       = ${p.bloodline}');
  print('  bloodlineLetter = ${p.bloodlineLetter}');
  print('  nature          = ${p.nature}');
  print('  evs             = ${p.evs}');
  print('  types           = ${p.types}');
  print('');

  final team = toCodecTeam(rt, const {});
  final codecPet = team.pets.single;
  print('toCodecTeam 之后的 Pet:');
  print('  bloodline       = ${codecPet.bloodline}');
  print('  bloodlineLetter = ${codecPet.bloodlineLetter}');
  print('  nature          = ${codecPet.nature}');
  print('  natureLetter    = ${codecPet.natureLetter}');
  print('');

  final code = codec.encode(team);
  final segs = code.split('~');
  print('编码结果段位:');
  for (var i = 0; i < 10 && i < segs.length; i++) {
    final label = switch (i) {
      0 => ' <- 头标记',
      1 => ' <- 数量字母+精灵码',
      4 => ' <- 血脉字母',
      5 => ' <- 性格字母',
      6 => ' <- 资质+技能1',
      _ => '',
    };
    print('  段[$i] = ${jsonEncode(segs[i])}$label');
  }
  print('');
  print('完整码长度: ${code.length}');
  print('编码后再解码:');
  final back = codec.decode(code);
  for (final x in back.pets) {
    print('  ${x.petName}  血脉=${x.bloodline}(${x.bloodlineLetter})  '
        '性格=${x.nature}(${x.natureLetter})  资质=${x.evsList}');
  }
}
