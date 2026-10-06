/// 技能名的近似匹配（治 OCR 错字）。
///
/// 为什么需要：技能名是卡面上**最小的字**，模型读错是常态而不是偶发。
/// 实测案例：「筛管奔流」被读成「藤蔓奔流」。
///
/// 关键杠杆：候选**只在这只精灵真正能学的技能里找**（卡瓦重 46 个），
/// 而不是全部 579 个。这让问题从"大海捞针"变成"46 选 1"。
///
/// 打分规则是**用真实数据选出来的**，不是拍脑袋：
/// 生成 192 条损坏样本（单字替换 / 漏字 / 重复字 / 换位）对比四种规则，
/// 「位置重叠」top1 命中 162/192（84%），且对"拿别的精灵技能来查"的
/// 毒输入最高只给到 0.5。
///
/// **因为毒输入能拿到 0.5，所以绝不自动采纳** —— 只提供候选让用户点选。
/// 这不是保守过度：技能错了阵容码就是错的，而让用户点一下几乎没有成本。
library;

/// 一条技能纠错建议。
class SkillSuggestion {
  const SkillSuggestion({
    required this.code,
    required this.name,
    required this.score,
  });

  /// 技能码（阵容码里用的）。
  final String code;

  /// 技能全名。
  final String name;

  /// 匹配度 0~1，仅用于排序与展示。
  final double score;

  int get percent => (score * 100).round();
}

/// 建议的最低分。低于它就不给建议（避免把垃圾输入硬套成某个技能）。
///
/// 基于实测：真实 OCR 错字的分数在 0.5 以上，而"别的精灵的技能"
/// 最高也只有 0.5。取 0.5 是这两者的分界。
const double kSkillSuggestMinScore = 0.5;

/// 最多给几条建议。太多反而难选。
const int kSkillSuggestLimit = 4;

class SkillMatcher {
  SkillMatcher({
    required Map<String, String> skillsByName,
    required Map<String, List<String>> learnsets,
  })  : _byName = skillsByName,
        // ignore: prefer_initializing_formals
        _learnsets = learnsets;

  /// 技能名 -> 技能码。
  final Map<String, String> _byName;

  /// 精灵码 -> 可学技能码。
  final Map<String, List<String>> _learnsets;

  bool get isReady => _byName.isNotEmpty;

  /// 调试用：看看内部到底装了多少只精灵的可学数据。
  int get debugLearnsetCount => _learnsets.length;

  /// 调试用：某只精灵的可学技能码。
  List<String> debugLearnsetCodes(String petCode) =>
      _learnsets[petCode] ?? const [];

  /// 调试用：名字表里有多少条、抽样几个。
  int get debugNameCount => _byName.length;
  String debugNameOf(String code) => _byName[code] ?? '<missing>';

  /// 这只精灵能学的技能名列表（用于手动填写时的提示范围）。
  List<String> learnableNames(String? petCode) {
    if (petCode == null) return const [];
    final codes = _learnsets[petCode];
    if (codes == null) return const [];
    return _namesOf(codes);
  }

  /// 技能码 -> 技能名，丢掉查不到的。
  List<String> _namesOf(List<String> codes) =>
      codes.map((c) => _byName[c] ?? '').where((s) => s.isNotEmpty).toList();

  /// 名字是否是一个真实技能。
  bool isKnownSkill(String name) => _byName.containsKey(name);

  /// 为可能读错的技能名找候选。
  ///
  /// [readName] 是模型读到的名字，[petCode] 是这只精灵的码。
  /// 返回按匹配度排序的建议；空列表表示"没有像的"，
  /// 此时界面应当只提供手动填写。
  List<SkillSuggestion> suggest(String readName, String? petCode) {
    final q = readName.trim();
    if (q.isEmpty) return const [];

    // 已经是真名 -> 不需要纠错
    final exact = _byName[q];
    if (exact != null) {
      return [SkillSuggestion(code: exact, name: q, score: 1.0)];
    }

    // 候选池：这只精灵的可学技能。
    //
    // **没有可学数据时要退回全部技能名**，而不是留下空池：
    // 精灵码认不出、或数据包版本较老没有 learnsets 时都会走到这里，
    // 此时"全表搜索"虽然慢一点，但比"什么都不给"有用得多。
    final petLearnset = petCode == null ? null : _learnsets[petCode];

    final Iterable<String> pool;
    if (petLearnset != null && petLearnset.isNotEmpty) {
      pool = _namesOf(petLearnset);
    } else {
      pool = _byName.values;
    }

    final out = <SkillSuggestion>[];
    for (final name in pool) {
      final s = score(q, name);
      if (s >= kSkillSuggestMinScore) {
        out.add(SkillSuggestion(
          code: _byName[name] ?? '',
          name: name,
          score: s,
        ));
      }
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out.take(kSkillSuggestLimit).toList();
  }

  /// 位置重叠打分。
  ///
  /// `(0.6 * 同位置相同字数 + 0.4 * 多重集重叠数) / max(长度)`
  ///
  /// 为什么给"同位置"更高权重：OCR 错字常见于**中间某个字**，
  /// 首尾多半是对的，同位置匹配能有效区分「藤蔓奔流 vs 筛管奔流」
  /// 这类同长错一字的情况。
  static double score(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    var samePos = 0;
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      if (a[i] == b[i]) samePos++;
    }

    // 多重集重叠：同一个字只算一次，避免「啊啊啊」这种重复字刷分
    final pool = b.split('');
    var overlap = 0;
    for (final ch in a.split('')) {
      final i = pool.indexOf(ch);
      if (i >= 0) {
        pool.removeAt(i);
        overlap++;
      }
    }

    final denom = a.length > b.length ? a.length : b.length;
    return (0.6 * samePos + 0.4 * overlap) / denom;
  }
}
