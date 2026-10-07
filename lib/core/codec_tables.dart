/// 编解码器需要的数据表（从 `assets/data/*.json` 载入）。
///
/// 这个文件**刻意不 import Flutter** —— 编解码是纯逻辑，应该能在
/// 纯 Dart 环境（命令行工具、单元测试、服务端）里跑。
/// 需要从 Flutter 资产读取时用 `asset_loader.dart`。
///
/// 表内容由 Python 端 `tools/export_data_for_app.py` 导出，与
/// `roco/teamcode.py` 逐项一致 —— 有 golden 测试盯着，不允许漂移。
library;

import 'skill_matcher.dart';
import 'variant_hints.dart';

class CodecTables {
  CodecTables._(this._raw);

  final Map<String, dynamic> _raw;

  /// 从已解析的 Map 构造（测试与命令行工具用）。
  static CodecTables fromMaps({
    required Map<String, dynamic> pets,
    required Map<String, dynamic> skills,
    required Map<String, dynamic> natures,
    required Map<String, dynamic> codec,
    Map<String, dynamic>? variantTypes,
    Map<String, dynamic>? learnsets,
  }) {
    final raw = <String, dynamic>{
      'pets': pets,
      'skills': skills,
      'natures': natures,
      'codec': codec,
    };
    // 这两个都是可选文件：老数据包没有它们，缺了只影响消歧与纠错，
    // 核心功能（识别 + 出码）不受影响。
    if (variantTypes != null) raw['variantTypes'] = variantTypes;
    if (learnsets != null) raw['learnsets'] = learnsets;
    return CodecTables._(raw);
  }

  Map<String, dynamic> get _pets => _raw['pets'] as Map<String, dynamic>;
  Map<String, dynamic> get _skills => _raw['skills'] as Map<String, dynamic>;
  Map<String, dynamic> get _natures => _raw['natures'] as Map<String, dynamic>;
  Map<String, dynamic> get _codec => _raw['codec'] as Map<String, dynamic>;

  /// 精灵码 -> 名字。
  late final Map<String, String> petNames =
      (_pets['by_code'] as Map<String, dynamic>).cast<String, String>();

  /// 名字 -> 精灵码（同名只留第一个，与 Python 的 setdefault 一致）。
  late final Map<String, String> petByName =
      (_pets['by_name'] as Map<String, dynamic>).cast<String, String>();

  /// 精灵码 -> 系别列表（每只 1~2 个）。
  ///
  /// 用途：**阵容码里不含系别**，所以解析路径靠这张表补上系别标签。
  /// 也是识别路径的对照来源（识别时系别是模型读的，两边不一致说明模型读错）。
  late final Map<String, List<String>> petTypesByCode =
      ((_pets['types_by_code'] as Map<String, dynamic>?) ?? const {})
          .map((k, v) => MapEntry(
                k,
                (v as List).map((e) => e.toString()).toList(),
              ));

  /// 技能名 -> 系别。
  ///
  /// 用途：判断某个血脉技能在当前血脉下还能不能用
  /// （血脉技能只有系别对上才学得了）。
  late final Map<String, String> skillTypeByName = {
    for (final e
        in ((_skills['type_by_code'] as Map<String, dynamic>?) ?? const {})
            .entries)
      if ((skillNames[e.key] ?? '').isNotEmpty && '${e.value}'.isNotEmpty)
        skillNames[e.key]!: '${e.value}',
  };

  late final Map<String, String> skillNames =
      (_skills['by_code'] as Map<String, dynamic>).cast<String, String>();
  late final Map<String, String> skillByName =
      (_skills['by_name'] as Map<String, dynamic>).cast<String, String>();

  /// 性格字母 -> 汉字名。
  late final Map<String, String> natureByLetter =
      (_natures['by_letter'] as Map<String, dynamic>).cast<String, String>();

  /// 汉字名 -> 性格字母。
  late final Map<String, String> natureByName =
      (_natures['by_name'] as Map<String, dynamic>).cast<String, String>();

  /// 30 条性格的六维修正，元素为 `{name, up, down}`。
  late final List<Map<String, String>> natureData = (_natures['data'] as List)
      .map((e) => (e as Map<String, dynamic>).cast<String, String>())
      .toList();

  /// 汉字名 -> `{name, up, down}`，供解码时查性格的增减。
  late final Map<String, Map<String, String>> natureByNameData = {
    for (final e in natureData) e['name']!: e,
  };

  late final Map<String, String> evs =
      (_codec['evs'] as Map<String, dynamic>).cast<String, String>();
  late final Map<String, String> evsRev =
      (_codec['evsRev'] as Map<String, dynamic>).cast<String, String>();
  late final Map<String, String> bloodline =
      (_codec['bloodline'] as Map<String, dynamic>).cast<String, String>();
  late final Map<String, String> bloodlineAlias =
      (_codec['bloodlineAlias'] as Map<String, dynamic>).cast<String, String>();
  late final Map<String, String> magic =
      (_codec['magic'] as Map<String, dynamic>).cast<String, String>();
  late final Map<String, String> magicRev =
      (_codec['magicRev'] as Map<String, dynamic>).cast<String, String>();
  late final Map<String, String> dimLetters =
      (_codec['dimLetters'] as Map<String, dynamic>).cast<String, String>();

  late final String seg = _codec['seg'] as String;
  late final String emptySkill = _codec['emptySkill'] as String;
  late final String emptySkillSeg = _codec['emptySkillSeg'] as String;
  late final String tailMarker = _codec['tailMarker'] as String;
  late final String header = _codec['header'] as String;

  late final Map<String, String> defaults =
      (_codec['defaults'] as Map<String, dynamic>).cast<String, String>();

  String get defaultEvCode => defaults['evCode']!;
  String get defaultNatureLetter => defaults['natureLetter']!;
  String get defaultBloodlineLetter => defaults['bloodlineLetter']!;
  String get defaultBloodlineText => defaults['bloodlineText']!;
  String get defaultMagicName => defaults['magicName']!;
  String get defaultTeamName => defaults['teamName']!;
  String get unknownPet => defaults['unknownPet']!;
  String get unknownSkill => defaults['unknownSkill']!;

  late final List<String> evOrder =
      (_codec['evOrder'] as List).cast<String>();

  /// 全局第三项分布：`[[dim, rate], ...]`
  late final List<List<dynamic>> evThirdGlobal =
      (_codec['evThirdGlobal'] as List).map((e) => e as List).toList();

  /// 首项 -> 第二项 的统计。
  late final Map<String, List<dynamic>> evSecondByFirst =
      (_codec['evSecondByFirst'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as List));

  /// `'第一项|第二项'` -> 第三项 的统计。
  late final Map<String, List<dynamic>> evThirdByPair =
      (_codec['evThirdByPair'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as List));

  /// 所有合法精灵码，用于解码时的重同步判断。
  late final Set<String> petIds = petNames.keys.toSet();

  /// 所有合法技能码。
  late final Set<String> skillCodes = skillNames.keys.toSet();

  /// 形态歧义的消歧线索（精灵码 -> 名字与系别）。
  ///
  /// 可选：老版本数据包没有这个文件时返回空的 [VariantHints]，
  /// 形态消歧退化成"让用户选"，核心功能不受影响。
  late final VariantHints variantHints = VariantHints.fromJson(
    (_raw['variantTypes'] as Map<String, dynamic>?) ?? const {},
  );

  /// 技能名纠错器。候选只在这只精灵的可学技能里找，准确率远高于全表搜索。
  ///
  /// 可选依赖 `learnsets.json`；缺了会退回"在全部技能名里找"。
  ///
  /// ⚠️ 这里要传 [skillByName]（**技能名 -> 技能码**），不是 [skillNames]。
  ///
  /// 这个参数名（`skillsByName`）读起来含糊，我因此传反过一次，
  /// 而且**没有立刻暴露**：
  ///   * 纠错 `suggest()` 靠"这只精灵的可学列表"决定候选池，
  ///     而那个列表本来就是名字 —— 所以主干功能看着正常
  ///   * 但两处静默坏了：① 精确命中判断 `_byName[q]` 永远 miss；
  ///     ② "没有可学数据时退回全表" 拿到的是**技能码**而不是名字，
  ///     等于在码上做模糊匹配，永远匹配不上
  ///   * 后来新增的 `isAvailable()` 用 `_byName[技能名]` 取码，
  ///     取到 null 就直接 return true —— 于是"血脉变了要清技能"完全失效
  ///
  /// 所以：方向是**名字 -> 码**。改这里之前先看 `SkillMatcher._byName` 的语义。
  late final SkillMatcher skillMatcher = SkillMatcher(
    skillsByName: skillByName,
    skillsByCode: skillNames,
    learnsets: (_learnsets['by_pet'] as Map<String, dynamic>? ?? const {})
        .map((k, v) => MapEntry(
              k,
              (v as List).map((e) => e.toString()).toList(),
            )),
    // 按来源拆分（level / stone / bloodline）—— 血脉技能要靠它过滤
    learnsetsBySource:
        (_learnsets['by_source'] as Map<String, dynamic>? ?? const {}).map(
      (pet, v) => MapEntry(
        pet,
        (v as Map<String, dynamic>).map(
          (src, codes) => MapEntry(
            src,
            (codes as List).map((e) => e.toString()).toList(),
          ),
        ),
      ),
    ),
    skillTypesByName: skillTypeByName,
  );

  Map<String, dynamic> get _learnsets =>
      (_raw['learnsets'] as Map<String, dynamic>?) ?? const {};

  String petNameOf(String code) => petNames[code] ?? unknownPet;
  String skillNameOf(String code) => skillNames[code] ?? unknownSkill;

  /// 去掉血脉后缀，如 `火系血脉` -> `火`。
  static String stripBloodline(String full) {
    for (final suffix in const ['系血脉', '血脉', '系']) {
      if (full.endsWith(suffix) && full.length > suffix.length) {
        return full.substring(0, full.length - suffix.length);
      }
    }
    return full;
  }
}
