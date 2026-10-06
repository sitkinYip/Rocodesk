/// 从 Flutter 资产读取编解码数据表。
///
/// 单独一个文件，是为了让 `codec_tables.dart` / `teamcodec.dart` 保持
/// **不依赖 Flutter**，从而能在纯 Dart 环境（命令行、单元测试）里复用。
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'codec_tables.dart';

/// 载入打包进 App 的数据表。
Future<CodecTables> loadCodecTablesFromAssets() async {
  Future<Map<String, dynamic>> read(String name) async =>
      jsonDecode(await rootBundle.loadString('assets/data/$name'))
          as Map<String, dynamic>;

  return CodecTables.fromMaps(
    pets: await read('pets.json'),
    skills: await read('skills.json'),
    natures: await read('natures.json'),
    codec: await read('codec.json'),
  );
}
