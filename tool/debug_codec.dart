// 这是命令行调试工具，print 是刻意的输出方式。
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:rocodesk/core/codec_tables.dart';
import 'package:rocodesk/core/teamcodec.dart';

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final t = CodecTables.fromMaps(
    pets: _readJson('assets/data/pets.json'),
    skills: _readJson('assets/data/skills.json'),
    natures: _readJson('assets/data/natures.json'),
    codec: _readJson('assets/data/codec.json'),
  );
  final codec = TeamCodec(t);

  print('natureByLetter 条数: ${t.natureByLetter.length}');
  print("natureByLetter['V'] = ${t.natureByLetter['V']}");
  print("natureByLetter['C'] = ${t.natureByLetter['C']}");
  print("natureByName['胆小'] = ${t.natureByName['胆小']}");
  print('natureData 条数: ${t.natureData.length}');
  print('natureData[0] = ${t.natureData.first}');
  print('');

  const code =
      'B~Gzg~~~H~V~BQBPBUbC--~bDAi~bDDC~bU5m~2B~~~H~c~BSBPBUbbdi~ayGq~bDDg~bDAi~ZZH~FA~A~A~A~A~A~A~A~A~A~A~A~';
  final o = codec.splitSegments(code);
  print('段数: ${o.length}');
  for (var i = 0; i < 12; i++) {
    print('  段[$i] = ${o[i]}');
  }
  print('');
  final team = codec.decode(code);
  print('magic=${team.magic} magicCode=${team.magicCode} header=${team.header}');
  for (final p in team.pets) {
    print('  ${p.petName}: bl=${p.bloodlineLetter} nat=${p.natureLetter}/${p.nature} '
        'up=${p.natureUp} down=${p.natureDown}');
  }
  print('');
  print('全字段解码（用真实样例）:');
  const sample =
      'B~Gx_~~~D~N~BPBRBUbH5W~bbd2~a20E~bH5-~3x~~~T~L~BPBRBUbRrc~bWii~ayJA~ayAG~'
      'xO~~~T~L~BPBRBUa2zc~bWh6~ayI2~bZBc~3a~~~T~C~BQBSBPax_K~a-HQ~bAmA~a-HG~'
      'yd~~~K~e~BSBPBTayJK~ayJy~bRq0~bKT4~4c~~~F~b~BSBPBRa7ro~ayGq~ayJK~ayGW~'
      'ZZH~FA~C~A~A~A~A~A~A~A~C~A~G~';
  final t2 = codec.decode(sample);
  for (final p in t2.pets) {
    print('  ${p.petName}: bl=${p.bloodline}(${p.bloodlineLetter}) '
        'nat=${p.nature}(${p.natureLetter}) up=${p.natureUp} down=${p.natureDown} '
        'evs=${p.evsList.join("/")} skills=${p.skills.join("、")}');
  }
  print('magic=${t2.magic}');
  print('往返一致: ${codec.encode(t2) == sample}');
}
