// 调试：为什么 skillMatcher.learnableNames('vi') 返回空
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:rocodesk/core/codec_tables.dart';

Map<String, dynamic> _read(String p) =>
    jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final skills = _read('assets/data/skills.json');
  final learnsets = _read('assets/data/learnsets.json');

  print('learnsets 顶层键: ${learnsets.keys.toList()}');
  final byPet = learnsets['by_pet'];
  print('by_pet 类型: ${byPet.runtimeType}');
  if (byPet is Map) {
    print('by_pet 条数: ${byPet.length}');
    final vi = byPet['vi'];
    print('by_pet["vi"] 类型: ${vi.runtimeType}  长度: ${(vi as List?)?.length}');
    print('by_pet["vi"] 前3项: ${vi?.take(3).toList()}');
  }

  print('');
  final tables = CodecTables.fromMaps(
    pets: _read('assets/data/pets.json'),
    skills: skills,
    natures: _read('assets/data/natures.json'),
    codec: _read('assets/data/codec.json'),
    variantTypes: _read('assets/data/variant_types.json'),
    learnsets: learnsets,
  );

  final m = tables.skillMatcher;
  print('skillMatcher.isReady: ${m.isReady}');
  print('debugLearnsetCount: ${m.debugLearnsetCount}');
  print('debugLearnsetCodes("vi") 长度: ${m.debugLearnsetCodes('vi').length}');
  print('前3个码: ${m.debugLearnsetCodes('vi').take(3).toList()}');
  print('debugNameCount: ${m.debugNameCount}');
  print('debugNameOf("ayBM"): ${m.debugNameOf('ayBM')}');
  print('debugNameOf("a0bQ"): ${m.debugNameOf('a0bQ')}');
  final names = m.learnableNames('vi');
  print('learnableNames("vi") 长度: ${names.length}');
  print('前5个: ${names.take(5).toList()}');
  print('');
  final s = m.suggest('藤蔓奔流', 'vi');
  print('suggest("藤蔓奔流", "vi") -> ${s.map((e) => "${e.name}=${e.score.toStringAsFixed(2)}").toList()}');
}
