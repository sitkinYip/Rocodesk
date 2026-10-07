/// 把模型返回的 JSON 规整成可编码的 [RecognizedTeam]。
///
/// 与 Python 端 `roco/pipeline.py` 的 `normalize_vlm_output` + `resolve_team` 职责相同：
///   * 容忍模型用各种字段名（name/pet_name、evs/stat_preference…）
///   * 名字走知识库反查（能纠错、能发现多形态歧义）
///   * **认不出来就明确报错，绝不编一个码出来**
///
/// 这一层的存在意义：模型输出是不可信的（会读错字、会漏字段），
/// 必须有一道确定性的校验，否则会生成一个进游戏无效的阵容码。
library;

import 'codec_tables.dart';
import 'models.dart';
import 'skill_matcher.dart';
import 'teamcodec.dart';
import 'variant_hints.dart';

/// 一只被识别出来的精灵（名字已尽量反查到精灵码）。
class RecognizedPet {
  RecognizedPet({
    required this.name,
    this.petId = '',
    this.nature = '',
    this.evs = const [],
    this.skills = const [],
    this.types = const [],
    this.bloodline = '',
    this.bloodlineLetter = '',
    List<VariantCandidate>? variants,
    List<String>? warnings,
  })  : variants = variants ?? [],
        warnings = warnings ?? [];

  /// 图上读到的名字（可能是模型读错的）。
  final String name;

  /// 反查到的精灵码；空字符串表示没认出来。
  String petId;

  String nature;
  List<String> evs;
  List<String> skills;

  /// 图标识别出的系别（1~2 个）。仅用于展示与核对，不进阵容码。
  List<String> types;

  /// 图标识别出的血脉名（如「首领」「翼」），空串表示没识别到。
  String bloodline;

  /// 映射出的阵容码血脉字母。空串表示"没识别到"，
  /// [noBloodlineLetter] 表示"明确无血脉"。
  String bloodlineLetter;

  /// 名字有多个形态时的候选（按与图上系别的契合度排序）。
  /// 非空且 [petId] 为空时，界面要提示用户点选一个。
  List<VariantCandidate> variants;

  /// 读不准的技能名 -> 纠错候选。键是**模型读到的名字**。
  ///
  /// 候选只在这只精灵能学的技能里找，所以需要先确定精灵码。
  final Map<String, List<SkillSuggestion>> skillSuggestions = {};

  List<String> warnings;

  bool get resolved => petId.isNotEmpty;

  /// 需要用户点一下选择形态（不是"认不出"，而是"认出了但不确定哪个形态"）。
  bool get needsVariantChoice => !resolved && variants.length > 1;
}

class RecognizedTeam {
  RecognizedTeam({
    required this.pets,
    this.teamName = '',
    this.magic = '',
    List<String>? warnings,
  }) : warnings = warnings ?? [];

  final List<RecognizedPet> pets;
  String teamName;
  String magic;
  List<String> warnings;

  /// 是否全部精灵都反查到了精灵码。有一只看不出来就不该出码。
  bool get allResolved => pets.isNotEmpty && pets.every((p) => p.resolved);
}

/// 18 个合法系别。用于校验模型返回的系别图标名。
const Set<String> kKnownTypes = {
  '普通', '火', '水', '草', '电', '冰', '武', '毒', '地',
  '翼', '萌', '虫', '幻', '幽', '恶', '龙', '机械', '光',
};

/// 血脉图标名 -> 阵容码字母。
///
/// `BLOODLINE` 表的写法是「翼系血脉」「首领血脉」，而图标名是「翼」「首领」，
/// 所以两边都要归一化后再比较：剥掉 `系血脉` / `血脉` / `系`。
///
/// 额外处理「无血脉」类的写法：模型可能返回空串、`无`、`没有`、`None`，
/// 这些都映射成 [noBloodlineLetter]（`'A'`），而不是当成错误。
const String noBloodlineLetter = 'A';

String? bloodlineLetterFromIcon(String iconName, CodecTables tables) {
  final raw = iconName.trim();
  if (raw.isEmpty) return noBloodlineLetter;

  String norm(String s) {
    var v = s;
    for (final suf in const ['系血脉', '血脉', '系']) {
      if (v.endsWith(suf) && v.length > suf.length) {
        return v.substring(0, v.length - suf.length);
      }
    }
    return v;
  }

  final target = norm(raw);
  for (final entry in tables.bloodline.entries) {
    if (norm(entry.value) == target) return entry.key;
  }
  // 已经是字母
  if (tables.bloodline.containsKey(raw)) return raw;
  // 明确表示"没有"
  if (const ['无', '没有', '无血脉', '未识别', 'none', 'None', 'null', '?'].contains(raw)) {
    return noBloodlineLetter;
  }
  return null; // 认不出来 —— 由调用方决定怎么提示
}

/// 从模型 JSON 里取字符串，容忍多种字段名。
String _pick(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return '';
}

List<String> _pickList(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v is List) {
      return v
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (v is String && v.trim().isNotEmpty) {
      // 模型偶尔把数组写成顿号分隔的字符串
      return v
          .split(RegExp(r'[、,，\s]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
  }
  return const [];
}

/// 规整模型输出。`useKb` 为 true 时会用知识库反查名字、校验技能。
RecognizedTeam normalizeVlmOutput(
  Map<String, dynamic> parsed, {
  required TeamCodec codec,
  required CodecTables tables,
  bool useKb = true,
}) {
  final petsRaw = (parsed['pets'] ?? parsed['pokemon'] ?? parsed['team'] ?? [])
      as List;
  final out = <RecognizedPet>[];
  final teamWarnings = <String>[];

  for (var i = 0; i < petsRaw.length; i++) {
    final raw = petsRaw[i];
    if (raw is! Map) continue;
    final m = raw.cast<String, dynamic>();

    final name = _pick(m, ['name', 'pet_name', 'petName', 'resolved_name', '精灵']);
    if (name.isEmpty) continue;

    final pet = RecognizedPet(
      name: name,
      nature: _pick(m, ['nature', 'personality', '性格']),
      evs: _pickList(m, ['evs', 'stat_preference', 'stats', '个体资质', '三围']),
      skills: _pickList(m, ['skills', 'moves', '技能']),
      types: _pickList(m, ['types', 'type', '系别', '属性']),
      bloodline: _pick(m, ['bloodline', '血脉']),
    );

    if (useKb) {
      // ---- 血脉图标 -> 字母 ----
      // 这是从"靠 Python + numpy 做模板匹配"改成"交给多模态模型"的关键一步：
      // 模型直接看图给出图标名，这里只做名字到字母的确定性映射。
      if (pet.bloodline.isNotEmpty) {
        final letter = bloodlineLetterFromIcon(pet.bloodline, tables);
        if (letter != null) {
          // 注意保留 noBloodlineLetter（'A'）这个 sentinel，**不要转成空串** ——
          // 空串在这里的含义是"没识别到"，两者在编码时处理不同：
          // 'A' 是明确的无血脉，空串则要由 toCodecTeam 兜底成 'A'。
          pet.bloodlineLetter = letter;
        } else {
          pet.warnings.add(
            '血脉图标识别为「${pet.bloodline}」，但它不在 24 种血脉里，'
            '已按「无血脉」处理。可以在下面手动指定。',
          );
        }
      }

      // ---- 名字反查 ----
      // 先尝试精确/唯一匹配；若名字有歧义（如「卡瓦重」有 4 个形态），
      // 用图上读到的系别自动消歧；再不行就把候选交给用户选。
      // 这条路径解决了"模型只读到基础名 -> 直接报错 -> 用户卡住"的阻塞。
      try {
        pet.petId = codec.resolvePetId(name);
      } on TeamCodeException catch (e) {
        final dis = tables.variantHints.disambiguate(
          queriedName: name,
          observedTypes: pet.types,
        );
        if (dis.picked != null) {
          pet.petId = dis.picked!;
          pet.warnings.add('名字「$name」有多个形态：${dis.reason}');
        } else {
          pet.variants = dis.candidates;
          if (dis.candidates.isEmpty) {
            pet.warnings.add(e.message);
          } else {
            pet.warnings.add('名字「$name」有 ${dis.candidates.length} 个形态，'
                '${dis.reason}。请在下面选一个。');
          }
        }
      }

      // ---- 技能校验与纠错候选 ----
      // 技能名是卡面上最小的字，读错是常态。候选只在这只精灵**能学的**技能里找。
      // 注意必须在精灵码确定之后做 —— 候选池依赖精灵码。
      final bad = <String>[];
      for (final s in pet.skills) {
        if (tables.skillByName.containsKey(s)) continue;
        bad.add(s);
        if (tables.skillMatcher.isReady) {
          final sug = tables.skillMatcher.suggest(s, pet.petId);
          if (sug.isNotEmpty) {
            pet.skillSuggestions[s] = sug;
          }
        }
      }
      if (bad.isNotEmpty) {
        final fixable = bad.where((s) => pet.skillSuggestions.containsKey(s)).length;
        if (fixable > 0) {
          pet.warnings.add('这些技能名在技能表里找不到，可能是看错了：'
              '${bad.join('、')}。点一下技能名可以改成正确的。');
        } else {
          pet.warnings.add('这些技能名在技能表里找不到：${bad.join('、')}。'
              '点一下技能名可以手动填写。');
        }
      }

      // ---- 系别校验 ----
      final badTypes = pet.types.where((t) => !kKnownTypes.contains(t)).toList();
      if (badTypes.isNotEmpty) {
        pet.warnings.add('系别图标识别出未知属性：${badTypes.join('、')}');
      }

      // ---- 性格 / 三围校验 ----
      if (pet.nature.isNotEmpty && !tables.natureByName.containsKey(pet.nature)) {
        pet.warnings.add('性格「${pet.nature}」不在 30 个性格表内，请核对');
      }
      for (final e in pet.evs) {
        if (!tables.evs.containsKey(e)) {
          pet.warnings.add('个体资质「$e」不是六维之一，请核对');
        }
      }
    }
    out.add(pet);
  }

  if (out.isEmpty) {
    teamWarnings.add('没能从这张图里读出任何精灵。换一张更清晰、卡片更大的截图试试。');
  }
  final unresolved = out.where((p) => !p.resolved).toList();
  if (unresolved.isNotEmpty) {
    teamWarnings.add(
      '有 ${unresolved.length} 只精灵没能对上图鉴：'
      '${unresolved.map((p) => p.name).join('、')}。'
      '为避免生成无效的阵容码，这一版不出码。',
    );
  }

  return RecognizedTeam(
    pets: out,
    teamName: _pick(parsed, ['team_name', 'teamName', 'name', '队伍名']),
    magic: _pick(parsed, ['magic', '魔法']),
    warnings: teamWarnings,
  );
}

/// codec 在血脉字母为 'A' 时会加一条「语义未证实」的技术性提示。
///
/// 对开发者有用（说明这个字母的语义是推断的），但对用户是**噪音**：
/// 「无血脉」是正常状态，界面上的「血脉未识别」已经说清楚了，
/// 不需要用户做任何操作。而且每次重新出码都会重复追加，越堆越多。
///
/// 所以这条在进界面之前被过滤掉。
const String kCodecNoiseBloodlineA = '血脉字母为 A';

/// 判断一条 codec 提示是否属于"用户不需要看到"的噪音。
bool isCodecNoise(String note) {
  if (note.contains(kCodecNoiseBloodlineA)) return true;
  // 性格字母为 A 同理：也是正常状态
  if (note.contains('性格字母为 A')) return true;
  return false;
}

/// 把识别结果转成可编码的 [Team]。
///
/// 只有 [RecognizedTeam.allResolved] 为真时才该调用，否则 [codec.encode]
/// 会因为精灵码对不上而抛错（这是预期行为：宁可报错不出废码）。
///
/// 血脉的优先级：用户手动指定 > 模型从图标识别出的字母 > 无血脉。
///
/// 关键：**必须显式写 [noBloodlineLetter]（'A'）表示无血脉**。
/// codec 的默认值是 `'T'`（首领），一旦留空，没有血脉的精灵会全部变成首领 ——
/// 这是实际发生过的 bug，游戏里六只全显示首领徽章。
///
/// [variantOverrides] 是用户在界面上点选的形态，键为「第几只」（从 1 开始），
/// 值为精灵码。它优先于 [RecognizedPet.petId]。
Team toCodecTeam(
  RecognizedTeam rt,
  Map<int, String> bloodlineOverrides, {
  Map<int, String> variantOverrides = const {},
  Map<int, List<String>> skillOverrides = const {},
  String? magicOverride,
  String? teamNameOverride,
}) {
  final pets = <Pet>[];
  for (var i = 0; i < rt.pets.length; i++) {
    final p = rt.pets[i];
    // 编号从 1 开始，和界面上显示的第 N 只一致
    final override = bloodlineOverrides[i + 1];
    final chosenVariant = variantOverrides[i + 1];
    final petId = (chosenVariant != null && chosenVariant.isNotEmpty)
        ? chosenVariant
        : p.petId;
    // 用户在界面上修正过的技能整表覆盖（OCR 错字纠错的结果）
    final skills = skillOverrides[i + 1] ?? p.skills;

    String letter;
    String name;
    if (override != null) {
      // 用户覆盖：空串表示"无血脉"，其余按名字/字母解析
      if (override.isEmpty) {
        letter = noBloodlineLetter;
        name = '';
      } else {
        letter = _letterForName(override) ?? noBloodlineLetter;
        name = override;
      }
    } else if (p.bloodlineLetter.isNotEmpty) {
      // 模型识别出的字母（含 sentinel 'A'）
      letter = p.bloodlineLetter;
      name = p.bloodline;
    } else if (p.bloodline.isNotEmpty) {
      // 有名字但没字母（理论上不该发生，兜底再解析一次）
      letter = _letterForName(p.bloodline) ?? noBloodlineLetter;
      name = p.bloodline;
    } else {
      letter = noBloodlineLetter; // 明确表示"无血脉"
      name = '';
    }

    pets.add(Pet(
      petId: petId,
      petName: p.name,
      nature: p.nature,
      evsList: p.evs,
      skills: skills,
      bloodline: name,
      bloodlineLetter: letter,
    ));
  }
  return Team(
    // 队伍名：用户手改优先。空则用识别结果，再空则用默认名。
    name: (teamNameOverride != null && teamNameOverride.isNotEmpty)
        ? teamNameOverride
        : (rt.teamName.isNotEmpty ? rt.teamName : '未命名队伍'),
    // 魔法：用户手改优先于模型识别。留空则由 codec 回落到进化之力。
    magic: (magicOverride != null && magicOverride.isNotEmpty)
        ? magicOverride
        : (rt.magic.isNotEmpty ? rt.magic : '进化之力'),
    // 头段必须显式给：为空时 encode 会回落到标准头段，但依赖兜底不如写明。
    header: 'B',
    pets: pets,
  );
}

/// 界面上的血脉名 -> 阵容码字母。认不出返回 null。
String? _letterForName(String name) {
  const known = {
    '普通': 'B', '草': 'C', '火': 'D', '水': 'E', '光': 'F', '地': 'G',
    '冰': 'H', '龙': 'I', '电': 'J', '毒': 'K', '虫': 'L', '武': 'M',
    '翼': 'N', '萌': 'O', '幽': 'P', '恶': 'Q', '机械': 'R', '幻': 'S',
    '首领': 'T', '巨兽': 'U', '黑魔法': 'V', '异核': 'W', '污染': 'X', '奇异': 'Y',
  };
  if (known.containsKey(name)) return known[name];
  for (final e in known.entries) {
    if (name.startsWith(e.key) || e.key.startsWith(name)) return e.value;
  }
  return null;
}

// ---------------------------------------------------------------------------
// 解码方向：阵容码 -> 可展示的识别结果
// ---------------------------------------------------------------------------

/// 把**已解码**的队伍转成界面用的 [RecognizedTeam]。
///
/// 这是 [toCodecTeam] 的逆操作，存在的意义是**复用同一个结果页**：
/// 解析阵容码和识别截图，最终都是"展示一支队伍 + 允许手改 + 重新出码"，
/// 没有理由写两套界面。
///
/// 与识别路径的两个关键差异：
///   * 解码出来的东西**天然是确定的** —— 精灵码、性格字母、血脉字母都来自
///     阵容码本身，不存在"模型读错"，所以 `resolved` 一律为真，
///     也不会产生 [RecognizedPet.variants] 或 `skillSuggestions`。
///   * 但仍有**信息缺失**：阵容码不含系别，所以 [RecognizedPet.types] 为空
///     （界面就不显示系别标签，而不是显示错的）。
///
/// 数据表认不出的码不会让解析失败 —— 会保留原样并记一条 [warnings]。
/// 理由：阵容码可能是新版本游戏出的，旧数据表不认识；此时把认得的部分
/// 正常展示、把不认识的明确标出来，比整串拒绝有用得多。
RecognizedTeam toRecognizedTeam(Team team, CodecTables tables) {
  final pets = <RecognizedPet>[];
  final teamWarnings = <String>[];

  for (final p in team.pets) {
    // 精灵名以数据表为准（阵容码里只有码）；表里没有就用码本身当名字，
    // 这样界面上至少有个可读的东西，而不是空白。
    final name = tables.petNames[p.petId] ??
        (p.petName.isNotEmpty ? p.petName : p.petId);

    // 血脉：**直接用解码器算好的名字**，不要自己从表里查。
    //
    // 这两个来源的形态不同：`codec.bloodline` 表存的是全名「冰系血脉」，
    // 而界面用的是短名「冰」（[_BloodlineControl] 会自己拼上「血脉」二字）。
    // 从表里查会得到全名，拼出来就是「冰系血脉血脉」。
    // `decode` 已经通过别名表把字母转成了短名，这里只做兜底。
    final letter = p.bloodlineLetter;
    var bloodline = p.bloodline;
    if (bloodline.isEmpty && letter.isNotEmpty && letter != noBloodlineLetter) {
      // 兜底路径：调用方给的是手搓的 Team（没有走 decode），
      // 这时才需要从表里查，并剥掉「系血脉」「血脉」后缀。
      final full = tables.bloodline[letter] ?? '';
      bloodline = full
          .replaceAll('系血脉', '')
          .replaceAll('血脉', '')
          .trim();
    }
    if (letter.isNotEmpty &&
        letter != noBloodlineLetter &&
        bloodline.isEmpty) {
      teamWarnings.add('第 ${pets.length + 1} 只的血脉字母「$letter」'
          '不在当前资料库里，可能游戏更新了');
    }

    final warnings = <String>[];
    if (!tables.petNames.containsKey(p.petId)) {
      warnings.add('精灵码「${p.petId}」不在当前资料库里，可能游戏更新了');
    }

    pets.add(RecognizedPet(
      name: name,
      // 解码出来的码一定是"已确定"的，界面据此允许直接出码
      petId: p.petId,
      nature: p.nature,
      evs: p.evsList,
      skills: p.skills,
      // 系别不在阵容码里，留空 —— 界面会因此不显示系别标签
      bloodline: bloodline,
      bloodlineLetter: letter,
      warnings: warnings,
    ));
  }

  return RecognizedTeam(
    pets: pets,
    teamName: team.name,
    magic: team.magic,
    warnings: teamWarnings,
  );
}
