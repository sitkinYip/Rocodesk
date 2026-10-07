/// 自主配队：队伍状态 + 出码。
///
/// ## 为什么单独一个类
///
/// 出码要**六个并列的覆盖 Map** 一起算（换精灵 / 选形态 / 改技能 / 改性格 /
/// 改资质 / 改血脉），散在页面里会让 `setState` 的每一处都要重复一遍
/// "改完重算"。这里把它们收进一个地方，页面只调方法、只读 [code]/[aiText]。
///
/// 这也让"改一项 → 码跟着变"这条规则**只有一个实现**：
/// 任何改动方法末尾都走同一个 [_reencode]。
///
/// ## 为什么默认就是 6 个空槽
///
/// 官方队伍是 6 只（`encode` 支持不足 6 只，`countLetter = 65 + n`），
/// 而"先摆 6 个格子再逐个填"比"先加一只再想下一只"少一层操作。
/// 空槽是可以点的入口，不是错误状态（见 `ResultView.emptySlotLabel`）。
library;

import 'package:flutter/foundation.dart';

import '../../core/codec_tables.dart';
import '../../core/models.dart';
import '../../core/pipeline.dart';
import '../../core/teamcodec.dart';

/// 官方队伍容量。
const int kTeamSize = 6;

/// 一格都没有的空队伍。
///
/// `name` 留空是有意的：`ResultView` 会用 `emptySlotLabel` 显示动作提示
/// （「选择精灵」）。如果这里填「未知宠物」，六个格子会一起显示成红色错误。
RecognizedTeam blankTeam({int size = kTeamSize}) => RecognizedTeam(
      pets: [for (var i = 0; i < size; i++) RecognizedPet(name: '')],
    );

/// 队伍里**真的选了几只**。
///
/// 不能用 `team.pets.length`：自主配队一进来就有 6 个空槽（列表长度是 6，
/// 但一只都没选）。这个区别在"该不该显示报错"上很关键 ——
/// 空槽是等待点选的入口，不是失败。
///
/// 用 `asMap()` 而不是 `indexOf`：后者在两只内容相同的精灵上会返回
/// 第一个的索引（数错），而且是平方复杂度。
int countFilledSlots(
  RecognizedTeam team, {
  Map<int, String> petOverrides = const {},
  Map<int, String> variantOverrides = const {},
}) {
  var n = 0;
  team.pets.asMap().forEach((i, p) {
    final code = effectivePetCode(
      p,
      petOverride: petOverrides[i + 1],
      variantOverride: variantOverrides[i + 1],
    );
    if (code.isNotEmpty) n++;
  });
  return n;
}

@immutable
class TeamDraft {
  const TeamDraft({
    required this.team,
    required this.code,
    required this.codeError,
    required this.aiText,
    required this.bloodlineOverrides,
    required this.variantOverrides,
    required this.skillOverrides,
    required this.petOverrides,
    required this.natureOverrides,
    required this.evOverrides,
    required this.magic,
    required this.teamName,
  });

  final RecognizedTeam team;
  final String code;
  final String codeError;
  final String aiText;

  final Map<int, String> bloodlineOverrides;
  final Map<int, String> variantOverrides;
  final Map<int, List<String>> skillOverrides;
  final Map<int, String> petOverrides;
  final Map<int, String> natureOverrides;
  final Map<int, List<String>> evOverrides;

  final String magic;
  final String teamName;

  /// 6 格里填了几只。出码不受它限制（不足 6 只也能出码），
  /// 但界面上要能一眼看出"还差几只"。
  int get filledCount => countFilledSlots(
        team,
        petOverrides: petOverrides,
        variantOverrides: variantOverrides,
      );

  /// 第 [index] 格（从 1 起）当前用的精灵码。走共享的优先级函数，
  /// 不在这里自己拼一份判断。
  String petCodeOf(int index) {
    final i = index - 1;
    if (i < 0 || i >= team.pets.length) return '';
    return effectivePetCode(
      team.pets[i],
      petOverride: petOverrides[index],
      variantOverride: variantOverrides[index],
    );
  }
}

/// 把一份草稿算出码与助手描述。
///
/// **纯函数**：给同样的输入得到同样的输出，不碰界面状态。
/// 这样"改一项就重算"这件事可以在测试里直接验证，
/// 不用把界面点一遍。
TeamDraft buildDraft(
  RecognizedTeam team,
  CodecTables tables, {
  Map<int, String> bloodlineOverrides = const {},
  Map<int, String> variantOverrides = const {},
  Map<int, List<String>> skillOverrides = const {},
  Map<int, String> petOverrides = const {},
  Map<int, String> natureOverrides = const {},
  Map<int, List<String>> evOverrides = const {},
  String? magicOverride,
  String? teamNameOverride,
}) {
  final codec = TeamCodec(tables);
  String code = '';
  String codeError = '';
  String aiText = '';

  try {
    final t = toCodecTeam(
      team,
      bloodlineOverrides,
      variantOverrides: variantOverrides,
      skillOverrides: skillOverrides,
      petOverrides: petOverrides,
      natureOverrides: natureOverrides,
      evOverrides: evOverrides,
      magicOverride: magicOverride,
      teamNameOverride: teamNameOverride,
      tables: tables,
      // 空槽是"等待点选"的入口，不是精灵。见 toCodecTeam 的参数说明。
      skipBlankSlots: true,
    );
    code = codec.encode(t);
    aiText = codec.toGameText(t);
  } on TeamCodeException catch (e) {
    // **一只都没选**不是错误，是刚进来的正常状态。
    //
    // 所以这里刻意**不把 codec 的报错透出去**：`encode` 对空队伍说的是
    // 「阵容为空，无法编码」，那是给开发者看的措辞，用户看到会以为出了故障。
    // 留空 codeError，界面就会显示 emptyCodeMessage（「把精灵选上就会生成
    // 阵容码。」）—— 同一件事，但是一句人话。
    final anyPicked = countFilledSlots(
          team,
          petOverrides: petOverrides,
          variantOverrides: variantOverrides,
        ) >
        0;
    codeError = anyPicked ? e.message : '';
  }

  return TeamDraft(
    team: team,
    code: code,
    codeError: codeError,
    aiText: aiText,
    bloodlineOverrides: bloodlineOverrides,
    variantOverrides: variantOverrides,
    skillOverrides: skillOverrides,
    petOverrides: petOverrides,
    natureOverrides: natureOverrides,
    evOverrides: evOverrides,
    magic: magicOverride != null && magicOverride.isNotEmpty
        ? magicOverride
        : (team.magic.isNotEmpty ? team.magic : tables.defaultMagicName),
    teamName: teamNameOverride != null && teamNameOverride.isNotEmpty
        ? teamNameOverride
        : (team.teamName.isNotEmpty ? team.teamName : tables.defaultTeamName),
  );
}
