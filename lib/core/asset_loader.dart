/// 从 Flutter 资产读取编解码数据表。
///
/// 单独一个文件，是为了让 `codec_tables.dart` / `teamcodec.dart` 保持
/// **不依赖 Flutter**，从而能在纯 Dart 环境（命令行、单元测试）里复用。
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'codec_tables.dart';

/// 载入打包进 App 的数据表。
///
/// 与 `KnowledgeBase.load()` 的区别：这个**只读内置资产**，
/// 不碰应用支持目录、不查远程更新。
///
/// 什么时候用哪个：
///   * 识别页用 `KnowledgeBase` —— 它需要"优先用已下载的新数据"
///   * 解析页用这个 —— 它只需要能解码，走最少的依赖
///
/// 这个区分不是洁癖：`KnowledgeBase` 要 `path_provider`,而那是平台通道，
/// 在单元测试里不可用；更重要的是，**缓存目录坏掉时不该连带解析功能一起废掉**，
/// 因为解析完全可以只靠内置数据工作。
Future<CodecTables> loadCodecTablesFromAssets() async {
  Future<Map<String, dynamic>> read(String name) async =>
      jsonDecode(await rootBundle.loadString('assets/data/$name'))
          as Map<String, dynamic>;

  /// 可选文件：老版本数据包里没有，缺了只是少了消歧/纠错能力。
  Future<Map<String, dynamic>?> readOptional(String name) async {
    try {
      return await read(name);
    } catch (_) {
      return null;
    }
  }

  return CodecTables.fromMaps(
    pets: await read('pets.json'),
    skills: await read('skills.json'),
    natures: await read('natures.json'),
    codec: await read('codec.json'),
    variantTypes: await readOptional('variant_types.json'),
    learnsets: await readOptional('learnsets.json'),
  );
}
