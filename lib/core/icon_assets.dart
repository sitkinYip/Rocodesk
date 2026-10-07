/// 参考图标：界面里**所有有图的地方都显示图**。
///
/// 为什么值得做：图标是 128~360px 的绘制图，而名字是 10px 的扭曲汉字。
/// 图能让人一眼确认「认对了没有」，读字不行。
///
/// 这比"让模型做二轮图标比对"可靠得多 —— 后者实测更差
/// （见 PASS2_FINDINGS.md），因为要先精确裁剪出卡上的图标，
/// 而裁剪坐标每张图都不一样。显示参考图没有这个问题。
///
/// 资源体积：血脉 21（96px）+ 属性 18（48px）+ 技能 487（48px）
/// + 精灵头像 621（64px）≈ 5.8 MB。
///
/// ⚠️ **所有文件名必须是 ASCII**。Flutter Web 把 CJK 资产名写成字面的
/// 百分号编码文件名，运行时却按原始中文请求，导致必然 404。
/// 所以每张图都用稳定的 ASCII 码命名（技能码 / 血脉字母 / 属性码 / 精灵码），
/// 名字 -> 路径的映射由 assets/icons/index.json 提供。
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class IconAssets {
  // 字段保持私有，同时调用点能写 bloodline: / pet: 这种可读键名。
  // ignore_for_file: prefer_initializing_formals
  IconAssets._({
    required Map<String, String> bloodline,
    required Map<String, String> type,
    required Map<String, String> skill,
    required Map<String, String> pet,
    Map<String, String> trait = const {},
  })  : _bloodline = bloodline,
        _type = type,
        _skill = skill,
        _pet = pet,
        _trait = trait;

  /// 血脉字母 -> 资源路径。
  final Map<String, String> _bloodline;

  /// 属性名 -> 资源路径。
  final Map<String, String> _type;

  /// 技能名 -> 资源路径。
  final Map<String, String> _skill;

  /// 精灵码 -> 资源路径。
  final Map<String, String> _pet;

  /// 特性名 -> 资源路径。
  final Map<String, String> _trait;

  static IconAssets? _cache;

  /// 空实例：没有图标资源时用（界面退化成纯文字，功能不受影响）。
  factory IconAssets.empty() => IconAssets._(
        bloodline: const {},
        type: const {},
        skill: const {},
        pet: const {},
        trait: const {},
      );

  /// 载入索引（幂等，全局只读一次）。失败返回空实例。
  ///
  /// 索引的形态：
  ///   bloodline  字母 -> 名字（**值不是路径**，路径按 key 推导）
  ///   type       属性名 -> 路径
  ///   skill      技能名 -> 路径
  ///   pet        阵容码 -> 路径
  ///   trait      特性名 -> 路径（特性名就是 key，因为一只精灵只有一个特性）
  ///
  /// 后几组直接取索引里的路径值 —— 文件名不一定是 key（技能用技能码、
  /// 精灵用知识库数字 id、特性用名字哈希，都是为了避开文件名大小写冲突
  /// 或非法字符），所以**不能**自己拼。
  static Future<IconAssets> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final raw = await rootBundle.loadString('assets/icons/index.json');
      final m = jsonDecode(raw) as Map<String, dynamic>;

      Map<String, String> paths(String key) =>
          (m[key] as Map<String, dynamic>? ?? const {})
              .map((k, v) => MapEntry(k, v as String));

      // 血脉索引里存的是名字（界面要用），路径按字母 key 推导
      final blood = (m['bloodline'] as Map<String, dynamic>? ?? const {})
          .map((k, _) => MapEntry(k, 'assets/icons/bloodline/$k.png'));

      return _cache = IconAssets._(
        bloodline: blood,
        type: paths('type'),
        skill: paths('skill'),
        pet: paths('pet'),
        trait: paths('trait'),
      );
    } catch (_) {
      // 图标是可选增强：缺了功能照常，只是界面上没有图
      return _cache = IconAssets.empty();
    }
  }

  bool get isEmpty =>
      _bloodline.isEmpty &&
      _type.isEmpty &&
      _skill.isEmpty &&
      _pet.isEmpty &&
      _trait.isEmpty;

  int get count =>
      _bloodline.length +
      _type.length +
      _skill.length +
      _pet.length +
      _trait.length;

  /// 某个血脉字母的图标路径；没有返回 null。
  String? bloodlineIcon(String letter) => _bloodline[letter];

  /// 某个属性名的图标路径；没有返回 null。
  String? typeIcon(String typeName) => _type[typeName];

  /// 某个技能名的图标路径；没有返回 null。
  String? skillIcon(String name) => _skill[name];

  /// 特性图标。数据包缺 traits.json 时返回 null（界面退化显示名字首字）。
  String? traitIcon(String name) => _trait[name];

  /// 某只精灵（按精灵码）的头像路径；没有返回 null。
  String? petIcon(String? petCode) =>
      petCode == null ? null : _pet[petCode];
}
