/// 血脉候选的本地排序（让选择器把最可能的排在前面）。
///
/// 为什么需要：卡上血脉图标只有约 45px，实测**无法可靠地自动判定**：
///   * 模型直接读：5/6（唯一错的「龙→恶」是真歧义）
///   * 本地模板匹配单独作答：0-2/6（分数全挤在 0.85~0.96）
///
/// 但本地匹配的**排序**是有价值的 —— 正确答案进入前 3 的比例实测 5/6。
/// 所以这里不做自动判定，只用来把选择器里最可能的几个排到前面，
/// 让用户从「24 个里找」变成「3 个里挑」。
///
/// 数据是**每张图重新生成**的（由 tools/rank_bloodlines_local.py 产出），
/// 不是静态真值。缺了它选择器照常工作，只是退化成字母序。
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class BloodlineRanks {
  BloodlineRanks._(this._byPet);

  /// 精灵名 -> 排好序的血脉字母（最可能的在前）。
  final Map<String, List<String>> _byPet;

  static BloodlineRanks? _cache;

  static BloodlineRanks empty() => BloodlineRanks._(const {});

  bool get isEmpty => _byPet.isEmpty;

  /// 载入排序表（幂等）。失败返回空表，不影响功能。
  static Future<BloodlineRanks> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final raw =
          await rootBundle.loadString('assets/data/bloodline_ranks.json');
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final ranks = (m['ranks'] as Map<String, dynamic>? ?? const {});
      return _cache = BloodlineRanks._(ranks.map(
        (k, v) => MapEntry(k, (v as List).map((e) => e.toString()).toList()),
      ));
    } catch (_) {
      return _cache = BloodlineRanks.empty();
    }
  }

  /// 某个精灵名的候选顺序；没有则返回空列表。
  ///
  /// 名字可能是完整形态名（「卡瓦重（雪山附近的样子）」）也可能是基础名，
  /// 两种都试 —— 模型返回哪种并不稳定。
  List<String> forPet(String petName) {
    final direct = _byPet[petName];
    if (direct != null) return direct;
    final base = _base(petName);
    for (final entry in _byPet.entries) {
      if (_base(entry.key) == base) return entry.value;
    }
    return const [];
  }

  static String _base(String s) =>
      s.replaceAll(RegExp(r'[（(].*?[)）]'), '').trim();
}
