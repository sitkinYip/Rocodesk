/// 阵容码编解码器（Python `roco/teamcode.py` 的 Dart 移植）。
///
/// 目标：与 Python 端**逐字段一致**。由 `test/codec_golden_test.dart` 用
/// 593 条真实线上阵容码 + 构造用例 + 名称解析用例把关，任何漂移都会失败。
library;

import 'codec_tables.dart';
import 'models.dart';

class TeamCodec {
  TeamCodec(this.t);

  final CodecTables t;

  static final RegExp _ws = RegExp(r'\s+');
  static final RegExp _variantRe = RegExp(r'[（(].*?[)）]');

  // 惰性索引
  Map<String, List<String>>? _petByBase;

  static String _normalise(String code) => code.replaceAll(_ws, '');

  /// 去空白 + 把空技能占位符展开成独立段，然后按 `~` 切分。
  List<String> splitSegments(String payload) {
    final x = _normalise(payload).replaceAll(t.emptySkill, '${t.emptySkillSeg}${t.seg}');
    return x.split(t.seg);
  }

  /// 找魔法码所在下标（从后往前，允许多余字符粘连）。
  int _resolveMagicIndex(List<String> segments) {
    for (var i = segments.length - 1; i >= 0; i--) {
      final s = segments[i];
      if (t.magic.containsKey(s)) return i;
      for (final mc in t.magic.keys) {
        if (s.endsWith(mc)) return i;
      }
    }
    return -1;
  }

  // ---------------------------------------------------------------- decode

  Team decode(String code, {String? teamName, String? magicName}) {
    if (code.isEmpty) throw TeamCodeException('载荷为空');
    final raw = _normalise(code);
    if (!raw.contains(t.seg)) {
      throw TeamCodeException("载荷中不含 '~' 分隔符");
    }
    final o = splitSegments(code);

    final magicIdx = _resolveMagicIndex(o);
    var magicCode = '';
    var magic = magicName ?? t.defaultMagicName;
    if (magicIdx >= 0) {
      final seg = o[magicIdx];
      magicCode = seg.length >= 3 && t.magic.containsKey(seg.substring(seg.length - 3))
          ? seg.substring(seg.length - 3)
          : seg;
      magic = t.magic[magicCode] ?? magic;
    }

    final d = (o[0] == '' || o[0] == t.header) ? 1 : 0;
    var countLetter = '';
    final team = Team(
      name: teamName ?? t.defaultTeamName,
      magicCode: magicCode.isEmpty ? 'ZZH' : magicCode,
      magic: magic,
      header: (d == 1 && o[0] == t.header) ? t.header : '',
      payload: raw,
      tailMarker: t.tailMarker,
    );

    final limit = magicIdx >= 0 ? magicIdx : o.length;

    for (var g = 0; g < 6; g++) {
      var base = d + 9 * g;
      if (base + 5 >= limit) break;
      var w = o[base];
      if (g == 0) {
        if (RegExp(r'^[A-Z]').hasMatch(w)) {
          countLetter = w[0];
          w = w.substring(1);
        } else if (w.isEmpty) {
          countLetter = '';
        }
      }
      if (w.isEmpty) continue;

      // 安全网：精灵码不是已知码时向前重同步（容忍未知扩展）
      if (!t.petIds.contains(w) && w != t.emptySkillSeg) {
        int? resync;
        for (var k = base + 1; k < (base + 7 < limit ? base + 7 : limit); k++) {
          var cand = o[k];
          if (g == 0 && RegExp(r'^[A-Z]').hasMatch(cand)) {
            cand = cand.substring(1);
          }
          if (t.petIds.contains(cand)) {
            resync = k;
            break;
          }
        }
        if (resync != null) {
          base = resync;
          w = o[base];
        }
      }
      if (t.magic.containsKey(w) || w == t.emptySkillSeg) break;

      final blLetter = (base + 3 < o.length && o[base + 3].isNotEmpty)
          ? o[base + 3]
          : t.defaultBloodlineLetter;
      final natLetter = (base + 4 < o.length && o[base + 4].isNotEmpty)
          ? o[base + 4]
          : t.defaultNatureLetter;
      final evSeg = (base + 5 < o.length && o[base + 5].isNotEmpty)
          ? o[base + 5]
          : t.defaultEvCode;
      final evCode = evSeg.length >= 6 ? evSeg.substring(0, 6) : t.defaultEvCode;

      final slotRaw = <String>[
        evSeg.length > 6 ? evSeg.substring(6) : '',
      ];
      for (final k in [6, 7, 8]) {
        slotRaw.add((base + k < o.length) ? o[base + k] : '');
      }
      final slots = <String>[];
      final codes = <String>[];
      for (final s in slotRaw) {
        if (s.isEmpty || s == t.emptySkillSeg || s == t.emptySkill) {
          slots.add('');
          continue;
        }
        if (t.skillCodes.contains(s)) {
          slots.add(s);
          codes.add(s);
          continue;
        }
        // 粘连情况（如 '00000a2zI'）：拆开，能识别的保留
        final recovered = s
            .split(t.emptySkill)
            .where((p) => t.skillCodes.contains(p))
            .toList();
        if (recovered.isNotEmpty) {
          slots.add(recovered.last);
          codes.add(recovered.last);
        } else {
          slots.add('');
        }
      }
      final names = codes.map(t.skillNameOf).toList();

      final pname = t.petNameOf(w);
      final fullBl = t.bloodline[blLetter] ?? '';
      final blText = fullBl.isEmpty ? '' : CodecTables.stripBloodline(fullBl);

      final effNatLetter = t.natureByLetter.containsKey(natLetter) ? natLetter : 'A';
      var nature = t.natureByLetter[effNatLetter] ?? '';
      var upLetter = 'A';
      var downLetter = 'A';
      var q = '';
      var tt = '';
      if (magicIdx >= 0) {
        if (g == 0) {
          final first = (magicIdx + 1 < o.length) ? o[magicIdx + 1] : '';
          upLetter = first.length >= 2 ? first[1] : 'A';
          downLetter = (magicIdx + 2 < o.length) ? o[magicIdx + 2] : 'A';
        } else {
          final i1 = magicIdx + 1 + 2 * g;
          final i2 = magicIdx + 2 + 2 * g;
          upLetter = i1 < o.length ? o[i1] : 'A';
          downLetter = i2 < o.length ? o[i2] : 'A';
        }
        if (upLetter.isEmpty) upLetter = 'A';
        if (downLetter.isEmpty) downLetter = 'A';

        // 用「汉字名 -> 六维修正」查，不是 natureByLetter（那是字母->名字）
        final nd = t.natureByNameData[nature];
        q = nd?['up'] ?? '';
        tt = nd?['down'] ?? '';
        if (upLetter != 'A' && t.dimLetters.containsKey(upLetter)) {
          q = t.dimLetters[upLetter]!;
        }
        if (downLetter != 'A' && t.dimLetters.containsKey(downLetter)) {
          tt = t.dimLetters[downLetter]!;
        }
        if (q.isNotEmpty && tt.isNotEmpty && q != tt) {
          for (final e in t.natureData) {
            if (e['up'] == q && e['down'] == tt) {
              nature = e['name']!;
              break;
            }
          }
        }
      }

      final dims = <String>[];
      for (final i in [0, 2, 4]) {
        final nm = t.evsRev[evCode.substring(i, i + 2)];
        if (nm != null) dims.add(nm);
      }
      final evsList = dims.length == 3 ? dims : <String>['生命', '魔攻', '速度'];

      team.pets.add(Pet(
        index: g,
        petId: w,
        petName: pname,
        bloodlineLetter: blLetter,
        bloodline: blText,
        natureLetter: effNatLetter,
        nature: nature,
        natureUp: magicIdx >= 0 ? q : '',
        natureDown: magicIdx >= 0 ? tt : '',
        evCode: evCode,
        evsList: evsList,
        skills: names,
        skillCodes: codes,
        skillSlots: slots,
        tailUp: upLetter,
        tailDown: downLetter,
      ));
    }

    if (team.pets.isEmpty) {
      throw TeamCodeException('未能从载荷中解析出任何精灵');
    }
    // 载荷里没写数量字母时，按实际解析到的精灵数补一个（与 Python 一致）
    team.countLetter =
        countLetter.isNotEmpty ? countLetter : String.fromCharCode(65 + team.pets.length);
    return team;
  }

  // ------------------------------------------------------------ 名称反查

  static String _clean(String s) => s
      .replaceAll(_ws, '')
      .replaceAll('（', '(')
      .replaceAll('）', ')');

  /// 一个名字的多种等价写法。
  ///
  /// 为什么要多种：`_clean()` 把全角括号统一成半角，但 pets 表里的键用的是
  /// **全角括号**。于是「卡瓦重（草地附近的样子）」这种本来精确存在的名字，
  /// 清洗之后反而查不到，最后落到「基础名有多个形态」分支被拒绝解析。
  /// （Python 端也踩过同一个坑，已同步修复。）
  static List<String> _nameForms(String s) {
    final raw = s.replaceAll(_ws, '');
    final out = <String>[raw, _clean(raw)];
    final restored = raw.replaceAll('(', '（').replaceAll(')', '）');
    if (!out.contains(restored)) out.add(restored);
    return out.where((x) => x.isNotEmpty).toList();
  }

  Map<String, List<String>> get _petBaseIndex {
    if (_petByBase != null) return _petByBase!;
    final m = <String, List<String>>{};
    t.petNames.forEach((code, name) {
      final base = name.replaceAll(_variantRe, '').trim();
      m.putIfAbsent(base, () => <String>[]).add(code);
    });
    _petByBase = m;
    return m;
  }

  /// 精灵名（或精灵码）-> pets 表 id。
  ///
  /// 多义时抛错而不是猜 —— 与 Python 端一致（宁可报错也不静默给错码）。
  String resolvePetId(String value, {bool strict = true}) {
    if (value.isEmpty) return '';
    final v = _clean(value);

    // 1) 已经是精灵码
    if (t.petNames.containsKey(v)) return v;

    // 2) 精确同名 —— 尝试所有等价写法（修全角括号查不到的 bug）
    for (final form in _nameForms(value)) {
      final hit = t.petByName[form];
      if (hit != null) return hit;
    }

    // 3) 去掉「（形态）」后的基础名
    for (final form in _nameForms(value)) {
      final base = form.replaceAll(_variantRe, '').trim();
      final hit = t.petByName[base];
      if (hit != null) return hit;
    }

    final base = v.replaceAll(_variantRe, '').trim();
    final cands = _petBaseIndex[base] ?? const <String>[];
    if (cands.length == 1) return cands[0];
    if (cands.length > 1) {
      for (final c in cands) {
        if (t.petNames[c] == base) return c;
      }
      if (!strict) return cands[0];
      final names = cands.take(6).map((c) => '$c=${t.petNames[c]}').join('、');
      throw TeamCodeException('精灵名「$value」不唯一，pets 表中有多个形态：$names；请写完整名称（含形态）');
    }
    if (!strict) return '';
    throw TeamCodeException('pets 表中找不到精灵「$value」');
  }

  /// 性格（汉字名或字母）-> 性格字母。
  String resolveNatureLetter(String value, {bool strict = true}) {
    if (value.isEmpty) return '';
    final v = _clean(value);
    if (t.natureByName.containsKey(v)) return t.natureByName[v]!;
    if (t.natureByLetter.containsKey(v)) return v;
    if (!strict) return '';
    throw TeamCodeException('性格「$value」不在 30 个性格表内');
  }

  /// 血脉（`火系血脉`/`火系`/`火`/字母）-> 血脉字母。
  String resolveBloodlineLetter(String value, {bool strict = true}) {
    if (value.isEmpty) return '';
    final v = _clean(value);
    if (t.bloodline.containsKey(v)) return v;
    if (t.bloodlineAlias.containsKey(v)) return t.bloodlineAlias[v]!;
    if (!strict) return '';
    final avail = t.bloodline.values.map(CodecTables.stripBloodline).join('、');
    throw TeamCodeException('血脉「$value」不在血脉表内（可用：$avail）');
  }

  /// 技能名（或技能码）-> 技能码。
  String resolveSkillCode(String value, {bool strict = true}) {
    if (value.isEmpty) return '';
    final v = _clean(value);
    if (t.skillCodes.contains(v)) return v;
    if (t.skillByName.containsKey(v)) return t.skillByName[v]!;
    if (!strict) return '';
    throw TeamCodeException('技能「$value」不在技能表内');
  }

  /// 魔法名（或魔法码）-> 魔法码。
  String resolveMagicCode(String value, {bool strict = true}) {
    if (value.isEmpty) return '';
    final v = _clean(value);
    if (t.magic.containsKey(v)) return v;
    if (t.magicRev.containsKey(v)) return t.magicRev[v]!;
    if (!strict) return '';
    throw TeamCodeException('魔法「$value」不在 magic 表内');
  }

  // ---------------------------------------------------------------- encode

  String encode(Team team) {
    if (team.pets.isEmpty) throw TeamCodeException('阵容为空，无法编码');
    _prepare(team);

    final n = team.pets.length;
    final countLetter =
        team.countLetter.isNotEmpty ? team.countLetter : String.fromCharCode(65 + n);

    // 头段必须存在。曾经这里写成 `team.header.isNotEmpty ? ... : ''`，
    // 结果 header 为空时**静默丢掉头段**，整串码前移一段 —— 本地回解看起来
    // 正常（因为解码时 D 的判定兼容两种），但游戏客户端会解析失败。
    // 现在为空就回落到标准头标记，绝不产出畸形码。
    final header = team.header.isNotEmpty ? team.header : t.header;
    var out = '$header${t.seg}';
    for (var i = 0; i < team.pets.length; i++) {
      final pet = team.pets[i];
      var code = pet.petId;
      if (i == 0) code = countLetter + code;
      final bl = pet.bloodlineLetter.isNotEmpty
          ? pet.bloodlineLetter
          : t.defaultBloodlineLetter;
      final nat =
          pet.natureLetter.isNotEmpty ? pet.natureLetter : t.defaultNatureLetter;
      final ev = pet.evCode.length == 6
          ? pet.evCode
          : _evCodeFallback(pet.evsList);
      var blob = '$code${t.seg}${t.seg}${t.seg}$bl${t.seg}$nat${t.seg}$ev';
      var slots = pet.skillSlots.isNotEmpty
          ? List<String>.from(pet.skillSlots)
          : List<String>.from(pet.skillCodes);
      slots = slots.map((s) => t.skillCodes.contains(s) ? s : '').toList();
      while (slots.length < 4) {
        slots.add('');
      }
      if (!slots.any((s) => s.isNotEmpty)) slots = ['', '', '', ''];
      for (final s in slots.take(4)) {
        // 实技能后跟 '~'；空槽写 '00000' 且不带分隔符（会与下一字段粘连）
        blob += s.isNotEmpty ? '$s${t.seg}' : t.emptySkill;
      }
      out += blob;
    }
    final letters = <String>[];
    for (final pet in team.pets) {
      letters.add(pet.tailUp.isNotEmpty ? pet.tailUp : 'A');
      letters.add(pet.tailDown.isNotEmpty ? pet.tailDown : 'A');
    }
    out += '${team.magicCode}${t.seg}${team.tailMarker}${letters[0]}';
    for (final l in letters.skip(1)) {
      out += '${t.seg}$l';
    }
    out += t.seg;
    return out;
  }

  String _evCodeFallback(List<String> dims) {
    final code = dims.take(3).map((d) => t.evs[d] ?? '').join();
    return code.length == 6 ? code : t.defaultEvCode;
  }

  /// 把人类可读字段补全成可编码字段（就地修改），与 Python `prepare()` 对应。
  void _prepare(Team team, {bool strict = true}) {
    final notes = List<String>.from(team.notes);
    if (team.magicCode.isNotEmpty && !t.magic.containsKey(team.magicCode)) {
      throw TeamCodeException('魔法码「${team.magicCode}」不在 magic 表内');
    }
    if (team.magicCode.isEmpty) {
      team.magicCode = team.magic.isNotEmpty
          ? resolveMagicCode(team.magic, strict: strict)
          : 'ZZH';
    }
    if (team.magic.isEmpty) {
      team.magic = t.magic[team.magicCode] ?? t.defaultMagicName;
    }

    for (var i = 0; i < team.pets.length; i++) {
      final pet = team.pets[i];
      final where = '第 ${i + 1} 只精灵(${pet.petName.isNotEmpty ? pet.petName : (pet.petId.isNotEmpty ? pet.petId : '?')})';
      pet.notes = List<String>.from(pet.notes);

      // 1) 精灵码
      if (pet.petId.isEmpty) {
        pet.petId = resolvePetId(pet.petName, strict: strict);
      }
      if (!t.petNames.containsKey(pet.petId)) {
        throw TeamCodeException('$where 的精灵码「${pet.petId}」不在 pets 表内');
      }
      if (pet.petName.isEmpty || pet.petName == t.unknownPet) {
        pet.petName = t.petNames[pet.petId]!;
      }

      // 2) 血脉
      if (pet.bloodlineLetter.isEmpty) {
        if (pet.bloodline.isNotEmpty) {
          pet.bloodlineLetter = resolveBloodlineLetter(pet.bloodline, strict: strict);
        } else {
          pet.bloodlineLetter = t.defaultBloodlineLetter;
          pet.notes.add('未提供血脉，按小程序默认写首领血脉(T)（低置信默认值）');
        }
      } else if (pet.bloodlineLetter == 'A') {
        pet.notes.add('血脉字母为 A（未设置）——原样透传，语义未证实');
      } else if (!t.bloodline.containsKey(pet.bloodlineLetter)) {
        throw TeamCodeException('$where 的血脉字母「${pet.bloodlineLetter}」不在血脉表内');
      }
      if (pet.bloodline.isEmpty && t.bloodline.containsKey(pet.bloodlineLetter)) {
        pet.bloodline = CodecTables.stripBloodline(t.bloodline[pet.bloodlineLetter]!);
      }

      // 3) 性格
      if (pet.natureLetter.isEmpty) {
        if (pet.nature.isEmpty) {
          pet.natureLetter = t.defaultNatureLetter;
          pet.notes.add('未提供性格，按小程序默认写胆小(V)（低置信默认值）');
        } else {
          pet.natureLetter = resolveNatureLetter(pet.nature, strict: strict);
        }
      } else if (pet.natureLetter == 'A') {
        pet.notes.add('性格字母为 A（未设置）——原样透传，语义未证实');
      } else if (!t.natureByLetter.containsKey(pet.natureLetter)) {
        throw TeamCodeException('$where 的性格字母「${pet.natureLetter}」不是合法性格字母');
      }
      if (pet.nature.isEmpty || !t.natureByName.containsKey(pet.nature)) {
        pet.nature = t.natureByLetter[pet.natureLetter] ?? (pet.nature.isNotEmpty ? pet.nature : '胆小');
      }

      // 4) 个体资质（6 位）
      if (pet.evCode.length != 6) {
        pet.evCode = _evCodeFromDims(pet.evsList, pet.notes, where, pet);
      }
      if (pet.evsList.isEmpty) {
        pet.evsList = [
          for (final j in [0, 2, 4]) t.evsRev[pet.evCode.substring(j, j + 2)] ?? '',
        ].where((s) => s.isNotEmpty).toList();
      }

      // 5) 技能（4 槽）
      if (pet.skillSlots.isEmpty) {
        var codes = <String>[];
        for (final nm in pet.skills) {
          if (nm == t.unknownSkill || nm.isEmpty) {
            throw TeamCodeException('$where 的技能「$nm」无法反查技能码；请给出真实技能名');
          }
          codes.add(resolveSkillCode(nm, strict: strict));
        }
        if (codes.isEmpty && pet.skillCodes.isNotEmpty) {
          codes = pet.skillCodes.where(t.skillCodes.contains).toList();
        }
        if (codes.length > 4) {
          throw TeamCodeException('$where 给了 ${codes.length} 个技能，格式只支持 4 个');
        }
        if (codes.isEmpty) {
          pet.notes.add('该精灵没有任何技能，4 个技能槽将写 00000');
        }
        pet.skillCodes = codes;
        pet.skillSlots = List<String>.from(codes);
        while (pet.skillSlots.length < 4) {
          pet.skillSlots.add('');
        }
      }
      if (pet.skills.isEmpty) {
        pet.skills = pet.skillCodes.map(t.skillNameOf).toList();
      }
    }
    team.notes = notes;
  }

  /// 为缺失的资质维度给出统计最优猜测（与 Python `_pick_fill` 一致）。
  (String, String) _pickFill(List<String> given) {
    if (given.length >= 2) {
      List<dynamic>? best;
      List<String>? bestPair;
      for (final pair in [
        [given[0], given[1]],
        [given[1], given[0]],
      ]) {
        final e = t.evThirdByPair['${pair[0]}|${pair[1]}'];
        if (e != null) {
          final cnt = e[2] as int;
          if (best == null || cnt > (best[2] as int)) {
            best = e;
            bestPair = pair;
          }
        }
      }
      if (best != null && !given.contains(best[0])) {
        final dim = best[0] as String;
        final rate = (best[1] as num).toDouble();
        final cnt = best[2] as int;
        return (
          dim,
          '已知 ${bestPair!.join('、')} 的 $cnt 条真实配队里，'
              '第三项有 ${(rate * 100).round()}% 选 $dim'
        );
      }
    }
    if (given.length == 1) {
      final e = t.evSecondByFirst[given[0]];
      if (e != null && !given.contains(e[0])) {
        final dim = e[0] as String;
        final rate = (e[1] as num).toDouble();
        final cnt = e[2] as int;
        return (dim, '首项 ${given[0]} 的 $cnt 条真实配队里，第二项有 ${(rate * 100).round()}% 选 $dim');
      }
    }
    for (final row in t.evThirdGlobal) {
      final dim = row[0] as String;
      final rate = (row[1] as num).toDouble();
      if (!given.contains(dim)) {
        return (dim, '全局第三项分布里最常见的 $dim（${(rate * 100).round()}%）');
      }
    }
    for (final dim in t.evOrder) {
      if (!given.contains(dim)) return (dim, '按 EVS 表顺序兜底');
    }
    throw TeamCodeException('努力值维度不足 3 项，且找不到可用的补位值');
  }

  String _evCodeFromDims(List<String> dims, List<String> notes, String where, Pet pet) {
    final given = dims.where((d) => d.isNotEmpty).toList();
    for (final d in given) {
      if (!t.evs.containsKey(d)) {
        throw TeamCodeException('$where 的个体资质「$d」不是六维之一（可用：${t.evs.keys.join('、')}）');
      }
    }
    if (given.isEmpty) {
      notes.add('$where 未提供个体资质，整段按默认 生命/魔攻/速度 编码（默认值，非用户数据，进游戏后请核对）');
      return t.defaultEvCode;
    }
    if (given.length > 3) {
      throw TeamCodeException('$where 的个体资质给了 ${given.length} 项，最多 3 项');
    }
    final work = List<String>.from(given);
    while (work.length < 3) {
      final (dim, why) = _pickFill(work);
      work.add(dim);
      notes.add('$where 只提供了 ${given.length} 项个体资质；第 ${work.length} 项 「$dim」是**系统补的**'
          '（依据：$why）—— 进游戏后请核对');
    }
    return work.map((d) => t.evs[d]!).join();
  }

  // ------------------------------------------------------- AI 助手文本

  /// 生成给官方 AI 助手用的文本。
  ///
  /// ## 与小程序 `exportToGame` 的**刻意差异**
  ///
  /// 小程序把队伍名当标题、末尾附上阵容码。这里两条都不要：
  ///
  ///   * **不含阵容码** —— 官方助手是用来"讨论怎么配队"的，
  ///     把码塞给它既没用（它不导入码），又会干扰它理解意图。
  ///     码在 App 里单独展示，用户自己复制。
  ///   * **不含队伍名** —— 名字是玩家自己起的（「队伍3」之类），
  ///     对助手理解阵容没有任何信息量。
  ///
  /// 开头明确给出**任务指令**（"按以下要求组一支队伍"），
  /// 而不是只丢一堆数据 —— 否则助手容易回一句"好的，收到了"。
  String toGameText(Team team) {
    final magic = team.magic.isNotEmpty ? team.magic : t.defaultMagicName;
    final b = StringBuffer()
      ..writeln('按以下要求组一支队伍：')
      ..writeln()
      ..writeln('魔法：$magic')
      ..writeln()
      ..writeln('精灵与配置：');
    for (final pet in team.pets) {
      // 没有血脉时写「无血脉」而不是默认文案「默认血脉」——
      // 后者会让人以为有某种叫"默认"的血脉，前者才符合界面上的说法。
      final bl = pet.bloodline.isNotEmpty ? pet.bloodline : '无血脉';
      final parts = <String>[];
      if (pet.nature.isNotEmpty) parts.add('性格 ${pet.nature}');
      if (pet.evsList.isNotEmpty) parts.add('个体资质 ${pet.evsList.join('、')}');
      parts.add('血脉 $bl');
      if (pet.skills.where((s) => s.isNotEmpty).isNotEmpty) {
        parts.add('技能 {${pet.skills.where((s) => s.isNotEmpty).join('、')}}');
      }
      b.writeln('- ${pet.petName}：${parts.join('；')}');
    }
    return b.toString().trimRight();
  }
}
