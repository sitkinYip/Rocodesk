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
    Map<String, String> skillsByCode = const {},
    Map<String, Map<String, List<String>>> learnsetsBySource = const {},
    Map<String, String> skillTypesByName = const {},
  })  : _byName = skillsByName,
        // ignore: prefer_initializing_formals
        _learnsets = learnsets,
        _byCode = skillsByCode,
        _bySource = learnsetsBySource,
        _skillTypes = skillTypesByName;

  /// **技能名 -> 技能码**。
  ///
  /// ⚠️ 方向很重要：`learnsets` / `learnsetsBySource` 里存的是**码**，
  /// 所以要拿名字得用 [_byCode]，不能拿这张表当反查。
  ///
  /// 这个参数名（`skillsByName`）容易读成"按名字索引的技能表"，
  /// 我因此传反过一次，而且静默坏了三处（见 `CodecTables.skillMatcher`
  /// 的注释）。判断方向的唯一依据是**谁能查到谁**：
  /// `_byName['冰爪'] == 'bDBK'`。
  final Map<String, String> _byName;

  /// **技能码 -> 技能名**。从码取名字用这张。
  final Map<String, String> _byCode;

  /// 精灵码 -> 可学技能码。
  final Map<String, List<String>> _learnsets;

  /// 精灵码 -> 来源 -> 技能码（level / stone / bloodline）。
  ///
  /// **这是游戏机制，不是数据冗余**：技能有三个来源，行为完全不同 ——
  /// level/stone 一直可用，**bloodline 只在当前血脉对上时才学得了**。
  final Map<String, Map<String, List<String>>> _bySource;

  /// 技能名 -> 系别。判断血脉技能可用性要用。
  final Map<String, String> _skillTypes;

  bool get isReady => _byName.isNotEmpty;

  /// 有没有按来源拆分的可学数据。没有时血脉过滤退化成"不过滤"。
  bool get hasSourceData => _bySource.isNotEmpty;

  /// 技能码 -> 名字。优先用 [_byCode]，没有就退回遍历 [_byName]。
  String? _nameOfCode(String code) {
    final direct = _byCode[code];
    if (direct != null) return direct;
    // 兜底：老调用点可能没传 skillsByCode
    for (final e in _byName.entries) {
      if (e.value == code) return e.key;
    }
    return null;
  }

  /// 某只精灵在**当前血脉**下真正能用的技能名（排序后）。
  ///
  /// 规则（实测自知识库）：
  ///   * level / stone 来源的技能 —— 一直可用
  ///   * bloodline 来源的技能 —— 只有它的系别 == [bloodlineType] 时才可用
  ///
  /// ⚠️ **这个函数只该用来"标记哪些不可用"，不要用来当候选池。**
  /// 用户要的是"这只精灵能学的全部"（50 个），而不是"当前血脉下能用的"
  /// （33 个）—— 我曾用它当候选池，结果被指出"技能池少了"：
  /// 雪影娃娃改恶血脉能学「贪婪」，但改之前那个技能根本不出现在列表里，
  /// 用户没法先看见再决定。候选池请用 [allNamesForPet]。
  ///
  /// [bloodlineType] 为 null 时（如"无明显血脉"或特殊血脉）按"不过滤"处理。
  List<String> availableNames(String? petCode, String? bloodlineType) {
    final all = allNamesForPet(petCode);
    if (bloodlineType == null || bloodlineType.isEmpty) return all;
    return all
        .where((n) => isAvailable(n, petCode, bloodlineType))
        .toList();
  }

  /// 这只精灵**能学的全部技能名**（排序后）。
  ///
  /// = level + stone + **全部 18 个血脉技能**（不管当前血脉是哪个）。
  ///
  /// 为什么血脉技能要全给：那些技能本来就在它的可学列表里，只是要换血脉
  /// 才能用。让用户先看见「贪婪」，他才知道"改恶血脉能学这个"——
  /// 藏起来等于剥夺了这个信息。是否可用交给 [isAvailable] 标记。
  List<String> allNamesForPet(String? petCode) {
    final src = petCode == null ? null : _bySource[petCode];
    if (src == null) {
      // 没有来源数据（老数据包）-> 退回完整可学列表
      return learnableNames(petCode);
    }

    final out = <String>{};
    for (final key in const ['level', 'stone', 'other', 'bloodline']) {
      for (final c in (src[key] ?? const <String>[])) {
        final nm = _nameOfCode(c);
        if (nm != null) out.add(nm);
      }
    }
    return out.toList()..sort();
  }

  /// 某个技能在**当前血脉**下还能不能用。
  ///
  /// 用来实现「改了血脉 -> 清掉学不了的血脉技能」。
  /// level/stone 技能永远返回 true。
  bool isAvailable(String skillName, String? petCode, String? bloodlineType) {
    final src = petCode == null ? null : _bySource[petCode];
    if (src == null) return true; // 没有来源数据就不拦

    final code = _byName[skillName];
    if (code == null) return true; // 不在技能表里，不是这里能判断的

    final level = src['level'] ?? const <String>[];
    final stone = src['stone'] ?? const <String>[];
    final other = src['other'] ?? const <String>[];
    final blood = src['bloodline'] ?? const <String>[];
    if (level.contains(code) || stone.contains(code) || other.contains(code)) {
      return true;
    }

    if (!blood.contains(code)) {
      // 这只精灵根本学不了这个技能（用户从"全部技能"里硬选的）——
      // 这种情况不在这里拦，允许用户这么配。
      return true;
    }

    if (bloodlineType == null || bloodlineType.isEmpty) return true;
    return _skillTypes[skillName] == bloodlineType;
  }

  /// 调试用：看看内部到底装了多少只精灵的可学数据。
  int get debugLearnsetCount => _learnsets.length;

  /// 调试用：某只精灵的可学技能码。
  List<String> debugLearnsetCodes(String petCode) =>
      _learnsets[petCode] ?? const [];

  /// 调试用：名字表里有多少条、抽样几个。
  int get debugNameCount => _byName.length;
  String debugNameOf(String code) => _nameOfCode(code) ?? '<missing>';

  /// 这只精灵能学的技能名列表（用于手动填写时的提示范围）。
  List<String> learnableNames(String? petCode) {
    if (petCode == null) return const [];
    final codes = _learnsets[petCode];
    if (codes == null) return const [];
    return _namesOf(codes);
  }

  /// 技能码 -> 技能名，丢掉查不到的。
  List<String> _namesOf(List<String> codes) =>
      codes.map((c) => _nameOfCode(c) ?? '').where((s) => s.isNotEmpty).toList();

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
      // 全部技能**名**。注意是 keys 不是 values ——
      // `_byName` 是名字->码，values 是码。这里要的是名字。
      pool = _byName.keys;
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
