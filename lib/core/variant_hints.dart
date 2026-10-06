/// 形态歧义计数。
///
/// 背景：pets 表里 **61 个基础名有多个形态**（如「卡瓦重」有 4 个、
/// 「圣代甜甜」有 9 个），涉及 178 条精灵。模型只读到基础名时无法确定
/// 是哪一个，直接报错会让用户卡住 —— 这是实际遇到的第一个可用性阻塞。
///
/// 两级策略：
///   1. **用系别自动消歧**。各形态的系别不同（卡瓦重：草 / 草火 / 草地 / 草冰），
///      而模型能读出卡面上的系别图标。按重合度打分，唯一最优才采纳。
///   2. **不行就让用户选**。给出候选项与各自系别，一次点击解决。
///
/// 为什么用"打分"而不是"精确相等"：知识库记的系别与游戏内显示**未必完全一致**
/// （实测 `vi` 在库里是 `['草']`，游戏里显示 `草/冰`）。精确相等会漏判。
library;

/// 一个形态候选。
class VariantCandidate {
  const VariantCandidate({
    required this.code,
    required this.name,
    required this.types,
    this.score = 0,
  });

  /// 阵容码里的精灵码，如 `vi`。
  final String code;

  /// 完整名，如 `卡瓦重（草地附近的样子）`。
  final String name;

  /// 知识库记录的系别。
  final List<String> types;

  /// 与图上读到的系别的重合度（0~1）。仅用于排序。
  final double score;

  /// 词缀，用于在界面上显示「草地附近」这种区分信息。
  String get suffix {
    final i = name.indexOf(RegExp(r'[（(]'));
    if (i < 0) return '';
    return name
        .substring(i)
        .replaceAll(RegExp(r'^[（(]|[)）]$'), '')
        .trim();
  }
}

/// 自动采纳形态所需的最小领先幅度。
///
/// 分数是重合度（0~1）。实测卡瓦重的分布：
///   读到「草冰」-> zg 明显领先（>0.3），可自动采纳
///   读到「草火」-> ze 明显领先，可自动采纳
///   读到「草」  -> vi 领先 0.5（它库里就是 ['草']），也可自动采纳
///   读不到      -> 全部 0，必须交给用户
/// 取 0.15 是为了：明显命中就自动选，含糊不清就问人。
///
/// **调大它会更保守**（更常问用户），调小会更激进（更常自动选）。
/// 因为选错会让阵容码里出现另一种形态，宁可偏保守。
const double kAutoPickMinLead = 0.15;

/// 形态消歧的结果。
class Disambiguation {
  const Disambiguation({
    this.picked,
    this.candidates = const [],
    this.reason = '',
  });

  /// 自动选定的码；为空表示无法自动判定，需要用户选。
  final String? picked;

  /// 全部候选（已按契合度排序），供界面展示。
  final List<VariantCandidate> candidates;

  /// 为什么这样判定（用于提示，也让"没自动选"这件事可解释）。
  final String reason;

  bool get needsUserChoice => picked == null && candidates.length > 1;
  bool get hasCandidates => candidates.isNotEmpty;
}

/// 形态系别线索表：精灵码 -> (名字, 系别)。
class VariantHints {
  VariantHints._(this._byCode, this.ambiguousBases);

  final Map<String, VariantCandidate> _byCode;

  /// 有多个形态的基础名（如「卡瓦重」）。
  final Set<String> ambiguousBases;

  static VariantHints fromJson(Map<String, dynamic> json) {
    final raw = (json['all'] as Map?) ?? const {};
    final byCode = <String, VariantCandidate>{};
    raw.forEach((k, v) {
      if (v is! Map) return;
      final types = ((v['types'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList();
      byCode[k.toString()] = VariantCandidate(
        code: k.toString(),
        name: (v['name'] ?? '').toString(),
        types: types,
      );
    });
    final bases = ((json['ambiguous_bases'] as List?) ?? const [])
        .map((e) => e.toString())
        .toSet();
    return VariantHints._(byCode, bases);
  }

  bool get isEmpty => _byCode.isEmpty;

  VariantCandidate? byCode(String code) => _byCode[code];

  /// 按名字找候选（精确名 or 基础名）。
  List<VariantCandidate> candidatesForName(String name) {
    final exact = <VariantCandidate>[];
    for (final c in _byCode.values) {
      if (c.name == name) exact.add(c);
    }
    if (exact.isNotEmpty) return exact;

    // 基础名匹配：去掉括号后缀后相等
    final base = name.replaceAll(RegExp(r'[（(].*?[)）]'), '').trim();
    final out = <VariantCandidate>[];
    for (final c in _byCode.values) {
      final cbase = c.name.replaceAll(RegExp(r'[（(].*?[)）]'), '').trim();
      if (cbase == base) out.add(c);
    }
    return out;
  }

  /// 用图上读到的系别给候选打分。
  ///
  /// 打分规则（刻意见容）：
  ///   * 每个读到的系别在候选系别里 -> 计一分
  ///   * 候选的每个系别都被读到   -> 再加一分（鼓励完全覆盖）
  /// 归一化到 0~1。这样"知识库少记了一个系别"不会直接判零分。
  static List<VariantCandidate> scoreCandidates(
    List<VariantCandidate> candidates,
    List<String> observedTypes,
  ) {
    if (observedTypes.isEmpty || candidates.isEmpty) return candidates;
    final observed = observedTypes.toSet();

    final scored = candidates.map((c) {
      final ctypes = c.types.toSet();
      final hitObserved = observed.where(ctypes.contains).length;
      final covered =
          ctypes.isEmpty ? 0 : ctypes.where(observed.contains).length;
      final denom = observed.length + (ctypes.isEmpty ? 1 : ctypes.length);
      final score = denom == 0 ? 0.0 : (hitObserved + covered) / denom;
      return VariantCandidate(
        code: c.code,
        name: c.name,
        types: c.types,
        score: score,
      );
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  /// 尝试自动判定形态。
  ///
  /// 只在**唯一最优**且分数明显领先时才采纳；否则交给用户选。
  /// 宁可多问一次，也不要悄悄选错 —— 选错会让阵容码里出现另一种形态。
  Disambiguation disambiguate({
    required String queriedName,
    required List<String> observedTypes,
  }) {
    final cands = candidatesForName(queriedName);
    if (cands.length <= 1) {
      return Disambiguation(
        picked: cands.isEmpty ? null : cands.first.code,
        candidates: cands,
        reason: cands.isEmpty ? '没有候选' : '名字唯一，无需消歧',
      );
    }

    final scored = scoreCandidates(cands, observedTypes);

    if (observedTypes.isNotEmpty) {
      final best = scored.first;
      final second = scored.length > 1 ? scored[1] : null;
      // 唯一最优 + 分数领先 + 确实有重合，才自动采纳
      if (best.score > 0 &&
          (second == null || best.score - second.score >= kAutoPickMinLead)) {
        return Disambiguation(
          picked: best.code,
          candidates: scored,
          reason: '按系别「${observedTypes.join('、')}」判定为 ${best.name}',
        );
      }
    }

    return Disambiguation(
      candidates: scored,
      reason: observedTypes.isEmpty
          ? '图上的系别没读出来，无法自动判定形态'
          : '按系别无法唯一确定形态，请手动选择',
    );
  }
}
