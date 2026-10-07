/// 识别结果展示：精灵清单 + 阵容码 + 助手描述。
///
/// 排版要点（Apple HIG 的信息层级）：
///   * 每只精灵一行，名字是主信息，性格/资质/血脉是次要信息
///   * 属性与血脉用**小面积**色点标识，不用大面积色块
///   * 阵容码用等宽字体，因为它要被逐字核对
///   * 有一处需要用户确认的地方就明确标出来，不藏在折叠里
library;

import 'package:flutter/material.dart';

import '../../core/bloodline_ranks.dart';
import '../../core/codec_tables.dart';
import '../../core/icon_assets.dart';
import '../../core/pipeline.dart';
import '../../core/skill_matcher.dart';
import '../../core/variant_hints.dart';
import '../../theme/tokens.dart';
import '../../theme/type_colors.dart';
import '../../theme/typography.dart';
import '../../widgets/common.dart';
import '../../widgets/search_picker.dart';

class ResultView extends StatelessWidget {
  const ResultView({
    super.key,
    required this.team,
    required this.code,
    required this.codeError,
    required this.aiText,
    required this.bloodlineOverrides,
    required this.variantOverrides,
    required this.skillOverrides,
    required this.learnableSkills,
    required this.magic,
    required this.magicOptions,
    required this.teamName,
    required this.onEditTeamName,
    required this.icons,
    required this.bloodlineRanks,
    required this.onChooseMagic,
    required this.onChooseVariant,
    required this.onSkillsChanged,
    required this.onOverrideBloodline,
    required this.onCopy,
    // ---- 整队可编辑：这些不给就退回只读展示 ----
    this.petOverrides = const {},
    this.natureOverrides = const {},
    this.evOverrides = const {},
    this.tables,
    this.onPetChanged,
    this.onNatureChanged,
    this.onEvsChanged,
    // ---- 阵容码区块：两个页面语义不同，所以可配置 ----
    this.codeTitle = '阵容码',
    this.codeSubtitle = '复制后粘进游戏，在好友队伍那一栏导入',
    this.primaryActionLabel = '重新识别',
    this.onPrimaryAction,
    this.onCopyCode,
  });

  final RecognizedTeam team;
  final String code;
  final String codeError;
  final String aiText;

  /// 用户手动纠正过的血脉，键是「第几只」（从 1 开始）。
  final Map<int, String> bloodlineOverrides;

  /// 用户手动选定的形态（精灵码），键是「第几只」（从 1 开始）。
  final Map<int, String> variantOverrides;

  /// 用户在界面上修正过的技能表，键是「第几只」（从 1 开始）。
  final Map<int, List<String>> skillOverrides;

  /// 用户换掉的精灵（精灵码），键是「第几只」。
  final Map<int, String> petOverrides;

  /// 用户改过的性格，键是「第几只」。
  final Map<int, String> natureOverrides;

  /// 用户改过的个体资质（三个维度），键是「第几只」。
  final Map<int, List<String>> evOverrides;

  /// 数据表。换精灵 / 换性格 / 换技能都需要它提供候选。
  ///
  /// 为 null 时**整块编辑能力关闭**（卡片回到只读展示）——
  /// 这是刻意的降级：宁可少几个能点的东西，也不要一个点了没反应的按钮。
  final CodecTables? tables;

  /// 用户改了某一项之后回调，交给页面重新出码。
  final void Function(int index, String petId)? onPetChanged;
  final void Function(int index, String nature)? onNatureChanged;
  final void Function(int index, List<String> evs)? onEvsChanged;

  /// 取某只精灵**能学**的技能名，供手动填写时提示范围。
  /// 返回空列表表示没有可学数据（此时界面不限制输入）。
  final List<String> Function(RecognizedPet) learnableSkills;

  /// 当前生效的魔法名（模型识别或用户手改）。
  final String magic;

  /// 可选的魔法（来自知识库的 magic 表）。
  final List<String> magicOptions;

  /// 当前生效的队伍名（模型识别或用户手改）。
  final String teamName;

  final ValueChanged<String?> onEditTeamName;

  /// 参考图标（血脉 / 技能）。为空资源时纠错面板退化成纯文字。
  final IconAssets icons;

  /// 血脉候选的本地排序（每张图生成）。空则按字母序。
  final BloodlineRanks bloodlineRanks;

  // ---- 阵容码区块的可配置项 ----
  //
  // 这些不是"样式开关"，而是**两个页面语义不同**的落点：
  // 识别页的码是产出，解析页的码是输入。

  /// 阵容码区块的标题。
  final String codeTitle;

  /// 阵容码区块的说明。
  final String codeSubtitle;

  /// 主按钮的文案（识别页是「重新识别」，解析页不用）。
  final String primaryActionLabel;

  /// 主按钮的回调。为 null 表示这个页面不需要主按钮。
  final VoidCallback? onPrimaryAction;

  /// 「复制阵容码」按钮的回调。为 null 表示不显示这个按钮 ——
  /// 解析页属于这种情况：用户刚刚才把码粘进来，再给他一个复制按钮是多余的。
  final Future<void> Function(String text, String label)? onCopyCode;

  final ValueChanged<String?> onChooseMagic;
  final void Function(int index, String code) onChooseVariant;
  final void Function(int index, List<String> skills) onSkillsChanged;
  final void Function(int index, String? letter) onOverrideBloodline;
  final Future<void> Function(String text, String label) onCopy;

  /// 编辑队伍名。
  ///
  /// 用对话框而不是底部抽屉：只有一个输入框，抽屉反而多一层动作。
  Future<void> _editTeamName(BuildContext context) async {
    final c = context.colors;
    final ctrl = TextEditingController(text: teamName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('队伍名'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(
            hintText: '给这支队伍起个名字',
            counterText: '',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(
              '确定',
              style: TextStyle(color: c.accent, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    onEditTeamName(result.trim());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---------- 队伍信息：队伍名 + 魔法 ----------
        // 魔法会写进阵容码（段 55），读错整支队伍的魔法就错了，所以必须能核对与手改。
        // 队伍名**不进阵容码**，只影响展示和导出的文本，所以单独标注清楚。
        const SectionHeader(
          title: '队伍信息',
          subtitle: '魔法会写进阵容码；队伍名只用于展示，不影响码',
        ),
        AppGroup(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SettingsRow(
                title: '队伍名',
                subtitle: teamName,
                leading: Icon(Icons.groups_outlined,
                    size: 20, color: c.textSecondary),
                trailing: Icon(Icons.edit_outlined,
                    size: 18, color: c.textTertiary),
                onTap: () => _editTeamName(context),
              ),
              const Divider(height: 1),
              _MagicRow(
                magic: magic,
                options: magicOptions,
                onChanged: onChooseMagic,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // ---------- 需要留意的问题 ----------
        if (team.warnings.isNotEmpty) ...[
          for (final w in team.warnings) ...[
            InlineNotice(message: w, severity: NoticeSeverity.warning),
            const SizedBox(height: AppSpacing.md),
          ],
        ],

        // ---------- 阵容码 ----------
        //
        // 两个页面对这块的处理不同，所以标题与动作都可配置：
        //   * 识别页：码是**产出**，重点是"复制走" + "识别错了重来"
        //   * 解析页：码是**输入**，用户刚粘过一串；这里显示的是改过之后的结果，
        //     作用只是"确认改动生效了"。所以既不需要复制按钮（他本来就有码），
        //     也不该有"重新识别"（解析页没有识别这一步）。
        SectionHeader(
          title: codeTitle,
          subtitle: codeSubtitle,
        ),
        AppGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (code.isNotEmpty) ...[
                SelectableText(code, style: AppType.code(context)),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    if (onCopyCode != null)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => onCopy(code, '阵容码'),
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('复制阵容码'),
                        ),
                      ),
                    if (onCopyCode != null && onPrimaryAction != null)
                      const SizedBox(width: AppSpacing.sm),
                    if (onPrimaryAction != null)
                      Expanded(
                        flex: onCopyCode == null ? 1 : 0,
                        child: OutlinedButton(
                          onPressed: onPrimaryAction,
                          child: Text(primaryActionLabel),
                        ),
                      ),
                  ],
                ),
              ] else
                InlineNotice(
                  message: codeError.isEmpty ? '没能生成阵容码。' : codeError,
                  severity: NoticeSeverity.error,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // ---------- 精灵清单 ----------
        SectionHeader(
          title: '识别结果',
          subtitle: '共 ${team.pets.length} 只',
        ),
        AppGroup(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < team.pets.length; i++) ...[
                _PetRow(
                  index: i + 1,
                  pet: team.pets[i],
                  overrideLetter: bloodlineOverrides[i + 1],
                  chosenVariant: variantOverrides[i + 1],
                  skillOverride: skillOverrides[i + 1],
                  learnable: learnableSkills(team.pets[i]),
                  petOverride: petOverrides[i + 1],
                  natureOverride: natureOverrides[i + 1],
                  evOverride: evOverrides[i + 1],
                  tables: tables,
                  onOverride: (letter) =>
                      onOverrideBloodline(i + 1, letter),
                  onChooseVariant: (c) => onChooseVariant(i + 1, c),
                  onSkillsChanged: (list) => onSkillsChanged(i + 1, list),
                  onPetChanged: onPetChanged == null
                      ? null
                      : (id) => onPetChanged!(i + 1, id),
                  onNatureChanged: onNatureChanged == null
                      ? null
                      : (n) => onNatureChanged!(i + 1, n),
                  onEvsChanged: onEvsChanged == null
                      ? null
                      : (e) => onEvsChanged!(i + 1, e),
                  icons: icons,
                  bloodlineRanks: bloodlineRanks,
                ),
                if (i < team.pets.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // ---------- 助手描述 ----------
        if (aiText.isNotEmpty) ...[
          const SectionHeader(
            title: '给官方助手的描述',
            subtitle: '粘贴给游戏里的 AI 助手，它会结合性格与资质给建议',
          ),
          AppGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  aiText,
                  style: TextStyle(
                    fontFamilyFallback: AppType.monoFallback,
                    fontSize: AppType.sCaption,
                    height: 1.65,
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => onCopy(aiText, '助手描述'),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('复制描述'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PetRow extends StatelessWidget {
  const _PetRow({
    required this.index,
    required this.pet,
    required this.overrideLetter,
    required this.chosenVariant,
    required this.skillOverride,
    required this.learnable,
    required this.petOverride,
    required this.natureOverride,
    required this.evOverride,
    required this.tables,
    required this.onOverride,
    required this.onChooseVariant,
    required this.onSkillsChanged,
    required this.onPetChanged,
    required this.onNatureChanged,
    required this.onEvsChanged,
    required this.icons,
    required this.bloodlineRanks,
  });

  final int index;
  final RecognizedPet pet;
  final String? overrideLetter;
  final String? chosenVariant;

  /// 用户在界面上修正过的技能表。为空表示用识别结果。
  final List<String>? skillOverride;

  /// 用户换掉的精灵码。为空表示用识别/解析结果。
  final String? petOverride;

  /// 用户改过的性格。
  final String? natureOverride;

  /// 用户改过的个体资质（三个维度）。
  final List<String>? evOverride;

  /// 数据表；为 null 时编辑能力关闭。
  final CodecTables? tables;

  /// 这只精灵**能学**的技能名（用于手动填写的提示范围）。
  /// 由上层从知识库取，避免这里再依赖整张表。
  final List<String> learnable;

  final ValueChanged<String?> onOverride;
  final ValueChanged<String> onChooseVariant;
  final ValueChanged<List<String>> onSkillsChanged;

  /// 换精灵 / 改性格 / 改个体资质的回调。为 null 表示只读。
  final ValueChanged<String>? onPetChanged;
  final ValueChanged<String>? onNatureChanged;
  final ValueChanged<List<String>>? onEvsChanged;

  /// 参考图标（血脉 / 技能）。
  final IconAssets icons;

  /// 血脉候选的本地排序。
  final BloodlineRanks bloodlineRanks;

  /// 当前生效的技能表：用户改过就用改过的，否则用识别结果。
  List<String> get skillList => skillOverride ?? pet.skills;

  /// 当前生效的精灵码。
  String get effectivePetId =>
      (petOverride != null && petOverride!.isNotEmpty)
          ? petOverride!
          : pet.petId;

  /// 当前生效的性格。
  String get effectiveNature => natureOverride ?? pet.nature;

  /// 当前生效的个体资质。
  List<String> get effectiveEvs => evOverride ?? pet.evs;

  /// 这只精灵能不能编辑（数据表在且回调给了）。
  bool get canEditPet => tables != null && onPetChanged != null;
  bool get canEditNature => tables != null && onNatureChanged != null;
  bool get canEditEvs => tables != null && onEvsChanged != null;

  /// 当前精灵的**特性名**（跟着换精灵走，不可编辑）。
  ///
  /// 特性是精灵的固有被动 —— 换精灵就换特性，用户改不了。
  String? get traitName => tables?.abilityOf(effectivePetId);

  /// 特性描述（可能为空）。
  String? get traitDesc => tables?.abilityDescOf(effectivePetId);

  /// 当前血脉对应的系别（用于过滤血脉技能）。
  ///
  /// 血脉的 24 条里，18 条 elemental 各自对应一个系别；
  /// 6 条 special（首领/巨兽/黑魔法/异核/污染/奇异）不对应任何系别 ——
  /// 所以选了它们时没有血脉技能可用。
  ///
  /// 返回 null 表示"不知道血脉"（没识别出来），此时不排除任何技能。
  String? get currentBloodlineType {
    final bl = overrideLetter ?? pet.bloodline;
    if (bl.isEmpty) return null;
    final t = tables;
    if (t == null) return null;
    final letter = _bloodlineLetterOf(bl);
    if (letter == null) return null;
    final full = t.bloodline[letter] ?? '';
    final short = CodecTables.stripBloodline(full);
    // 只有 elemental 的才是系别；special 的（首领等）返回名字本身，
    // 但它在 skillTypeByName 里匹配不到任何技能，效果等同"没有可用血脉技能"
    return short.isEmpty ? null : short;
  }

  /// 界面上的血脉名/字母 -> 阵容码字母。
  String? _bloodlineLetterOf(String nameOrLetter) {
    // ⚠️ 这里**不能**用 `length == 1` 判断"已经是字母"。
    //
    // 中文系别名也是单字符（「冰」「火」「龙」…），会被误判成字母直接返回，
    // 于是 `bloodline['冰']` 查不到 -> 类型为 null -> "血脉锁定"整块失效。
    // 我这么错过一次，症状是"被锁的技能没有标记"，但功能看着还在。
    if (nameOrLetter.length == 1 &&
        nameOrLetter.codeUnitAt(0) < 128 &&
        RegExp(r'[A-Za-z]').hasMatch(nameOrLetter)) {
      return nameOrLetter.toUpperCase();
    }

    const known = {
      '普通': 'B', '草': 'C', '火': 'D', '水': 'E', '光': 'F', '地': 'G',
      '冰': 'H', '龙': 'I', '电': 'J', '毒': 'K', '虫': 'L', '武': 'M',
      '翼': 'N', '萌': 'O', '幽': 'P', '恶': 'Q', '机械': 'R', '幻': 'S',
      '首领': 'T', '巨兽': 'U', '黑魔法': 'V', '异核': 'W', '污染': 'X',
      '奇异': 'Y',
    };
    final n = nameOrLetter.endsWith('血脉')
        ? nameOrLetter.substring(0, nameOrLetter.length - 2)
        : nameOrLetter;
    return known[n];
  }

  /// 这只精灵**能学的全部技能名**（= level + stone + 全部 18 个血脉技能）。
  ///
  /// ⚠️ 这里刻意**不按当前血脉过滤**。
  ///
  /// 我一开始过滤了，结果被用户指出"技能池少了"：雪影娃娃一共能学 50 个，
  /// 但冰血脉下只显示 33 个，「贪婪」（恶系血脉技能）根本不出现 ——
  /// 而用户正是要"先看见有哪些可能，再决定换成什么血脉"。
  ///
  /// 所以候选池给全量，**哪些当前不可用由 [lockedSkills] 标记**。
  List<String> get currentLearnable {
    final t = tables;
    if (t == null) return learnable;
    final m = t.skillMatcher;
    if (!m.hasSourceData) return learnable;
    return m.allNamesForPet(effectivePetId);
  }

  /// 当前血脉下**用不了**的技能名集合。
  ///
  /// 用来在选择器里给这些技能打个标记（如"需 X 血脉"），
  /// 而不是把它们藏起来。
  Set<String> get lockedSkills {
    final t = tables;
    if (t == null) return const {};
    final m = t.skillMatcher;
    if (!m.hasSourceData) return const {};
    final type = currentBloodlineType;
    if (type == null || type.isEmpty) return const {};
    return currentLearnable
        .where((s) => !m.isAvailable(s, effectivePetId, type))
        .toSet();
  }

  /// 某个技能因血脉不可用时，提示用户需要什么血脉。
  ///
  /// 返回 null 表示可用（或不知道）。
  String? lockedReason(String skillName) {
    final t = tables;
    if (t == null) return null;
    if (!lockedSkills.contains(skillName)) return null;
    final ty = t.skillTypeByName[skillName];
    return ty == null ? '当前血脉下不可用' : '需$ty系血脉';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 用户选过形态就算已解决，哪怕模型没认出来
    final resolved = pet.resolved ||
        (chosenVariant?.isNotEmpty ?? false) ||
        (petOverride?.isNotEmpty ?? false);
    final effectiveBloodline = overrideLetter ?? pet.bloodline;
    // 取到局部变量 —— traitName 是 getter，Dart 的类型提升对它不生效
    final trait = traitName;
    // 头像要跟着"当前生效的精灵码"走：用户选了形态或换了精灵就显示那个的头像，
    // 否则认错时头像会和名字不符，反而误导。
    final chosenName = chosenVariant == null
        ? null
        : pet.variants
            .where((v) => v.code == chosenVariant)
            .map((v) => v.name)
            .firstOrNull;
    // 名字优先级：换精灵后的新名 > 选形态的名 > 识别/解析出的名
    final displayName = (petOverride != null && petOverride!.isNotEmpty)
        ? (tables?.petNames[petOverride] ?? petOverride!)
        : (chosenName ?? pet.name);
    // 系别也要跟着换精灵走 —— 换完之后还显示旧精灵的系别是误导
    final displayTypes = (petOverride != null &&
            petOverride!.isNotEmpty &&
            tables != null)
        ? (tables!.petTypesByCode[petOverride] ?? const <String>[])
        : pet.types;

    /// 把第 slot 个技能换成 newName（空串表示清空该槽）。
    void replaceSkill(int slot, String newName) {
      final next = List<String>.from(skillList);
      while (next.length < 4) {
        next.add('');
      }
      next[slot] = newName;
      onSkillsChanged(next);
    }

    /// 选了一个**当前血脉学不了**的技能（如雪影娃娃选恶系的「贪婪」）。
    ///
    /// 用户明确要求的行为：**自动把血脉切过去，并清掉占位的血脉技能**。
    /// 否则这个技能选进去也是个废配置（游戏里学不了）。
    ///
    /// 顺序不能换：
    ///   1. **先捕获**当前的技能布局 —— 回调会让 widget 重建，
    ///      那时再读 skillList 拿到的可能已经是剪过的版本
    ///   2. 算出这条技能需要哪个系别的血脉
    ///   3. 切血脉（`changeBloodline` 会把学不了的血脉技能剪掉）
    ///   4. 把选中的技能**写回目标槽位** —— 用第 1 步捕获的布局做底，
    ///      剪掉别的槽位里失效的技能，再把目标槽位换成新技能。
    ///      这样用户点的那一格一定是他要的技能，不会莫名其妙挪到别处。
    ///
    /// 这是同步完成的：三个回调各触发一次重新出码，但都只是写 map，
    /// 所以最终状态确定、不会互相覆盖。
    ///
    /// ⚠️ 全部逻辑写在这一个函数里、不抽子函数 —— 局部函数在 Dart 里
    /// **必须先声明后使用**，拆开会引入一堆顺序约束（踩过）。
    void addLockedSkill(String skillName) {
      final t = tables;
      final m = t?.skillMatcher;
      if (t == null || m == null) return;

      // 这条技能需要哪个系别的血脉（技能表里带 type）
      final type = t.skillTypeByName[skillName];
      if (type == null) return;
      const letterByType = {
        '普通': 'B', '草': 'C', '火': 'D', '水': 'E', '光': 'F', '地': 'G',
        '冰': 'H', '龙': 'I', '电': 'J', '毒': 'K', '虫': 'L', '武': 'M',
        '翼': 'N', '萌': 'O', '幽': 'P', '恶': 'Q', '机械': 'R', '幻': 'S',
      };
      final letter = letterByType[type];
      if (letter == null) {
        // 「首领」「巨兽」这类特殊血脉没有对应的系别技能，理论上到不了这里
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('没有「$type系」血脉，换不了')),
        );
        return;
      }

      // 1) 先留住这一只当前的技能布局
      final before = List<String>.from(skillList);
      // 用户点的是空槽就用那个空槽，否则覆盖最后一格
      final slot = before.indexWhere((s) => s.isEmpty);
      final target = slot >= 0 ? slot : (before.isEmpty ? 0 : before.length - 1);

      // 3) 切血脉。直接用 onOverride 而不是 changeBloodline：
      //    第 4 步会自己把失效的技能剪掉并整体写回，
      //    走 changeBloodline 会多剪一次、多出一次重新出码。
      //
      // ⚠️ onOverride 收的是**血脉名**（'恶'），不是字母（'Q'）。
      //    传字母的话界面会直接显示 "Q血脉"。踩过一次。
      onOverride(type);

      // 4) 写回目标槽位
      final after = List<String>.from(before);
      while (after.length <= target) {
        after.add('');
      }
      for (var i = 0; i < after.length; i++) {
        if (i != target &&
            after[i].isNotEmpty &&
            !m.isAvailable(after[i], effectivePetId, type)) {
          after[i] = '';
        }
      }
      after[target] = skillName;
      onSkillsChanged(after);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已把血脉改成「$type」，并学会「$skillName」'),
          duration: const Duration(seconds: 2),
        ),
      );
    }


    /// 选技能。**任何技能都能点** —— 不只是"可疑"的那些。
    ///
    /// 用户明确要求"拿到一图流后还可以自己搭配"，所以这里给完整能力：
    ///   * 有纠错候选时，候选排在最前（OCR 错字场景下最快）
    ///   * 同时给这只精灵的完整可学列表 + 全表搜索（重新搭配场景）
    ///   * 以及"清空这个槽"
    Future<void> pickSkill(int slot, String current) async {
      final t = tables;
      final chosen = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _SkillFixSheet(
          readName: current,
          suggestions: pet.skillSuggestions[current] ?? const [],
          // 完整候选池（含全部 18 个血脉技能）；不可用的那些由 locked 标记
          learnable: currentLearnable,
          locked: lockedSkills,          lockedReasonOf: lockedReason,
          icons: icons,
          // 换技能/重新搭配需要全部 579 个技能，不只是这只精灵能学的
          allSkills: t == null
              ? null
              : (t.skillNames.values.toList()..sort()),
          // 选了"当前血脉学不了"的技能 -> 自动切血脉并清掉占位的血脉技能。
          // 抽屉自己关掉，因为交互路径比"选一个可用技能"长得多。
          onPickLocked: (s) {
            Navigator.pop(context);
            addLockedSkill(s);
          },
        ),
      );
      if (chosen == null) return;
      replaceSkill(slot, chosen);
    }

    /// 改血脉。**并且清掉因换血脉而学不了的血脉技能。**
    ///
    /// 为什么必须清：血脉技能只有系别对上才学得了（实测每只精灵 18 个
    /// 血脉技能恰好覆盖 18 个系别）。换了血脉之后，原来学的那几个
    /// 血脉技能就不成立了 —— 留着会出一串游戏里无效的配置。
    ///
    /// 只影响**血脉技能**：level / stone 来源的技能任何血脉下都可用，
    /// 不会被清掉。用户从"全部技能"里硬选的（这只根本学不了的）
    /// 也不清 —— 那是他有意为之，不该被系统推翻。
    void changeBloodline(String? nameOrLetter) {
      onOverride(nameOrLetter);

      final t = tables;
      final letter = nameOrLetter == null || nameOrLetter.isEmpty
          ? null
          : _bloodlineLetterOf(nameOrLetter);
      if (t == null) return;

      final newType = letter == null
          ? null
          : CodecTables.stripBloodline(t.bloodline[letter] ?? '');
      final m = t.skillMatcher;
      if (!m.hasSourceData) return;

      final kept = skillList
          .where((s) => s.isEmpty || m.isAvailable(s, effectivePetId, newType))
          .toList();
      if (kept.length != skillList.length) {
        onSkillsChanged(kept);
      }
    }

    /// 换精灵：在全部 623 个精灵码里搜。
    Future<void> pickPet() async {
      final t = tables;
      if (t == null) return;
      final items = <PickerItem>[
        for (final e in t.petNames.entries)
          PickerItem(
            value: e.key,
            label: e.value,
            subtitle: (t.petTypesByCode[e.key] ?? const []).join(' · '),
            iconPath: icons.petIcon(e.key),
          ),
      ];
      final chosen = await showSearchPicker(
        context,
        title: '换精灵',
        subtitle: '第 $index 只。搜索名字即可，共 ${items.length} 只可选',
        items: items,
        selected: effectivePetId,
        searchHint: '搜索精灵名，如「卡瓦重」',
      );
      if (chosen != null) onPetChanged?.call(chosen);
    }

    /// 改性格：30 条。
    Future<void> pickNature() async {
      final t = tables;
      if (t == null) return;
      final items = <PickerItem>[
        for (final e in t.natureByName.entries)
          PickerItem(value: e.key, label: e.key),
      ]..sort((a, b) => a.label.compareTo(b.label));
      final chosen = await showSearchPicker(
        context,
        title: '选择性格',
        subtitle: '共 ${items.length} 种',
        items: items,
        selected: effectiveNature,
        searchHint: '搜索性格名',
      );
      if (chosen != null) onNatureChanged?.call(chosen);
    }

    /// 改个体资质：从 6 个维度里选 3 个。
    ///
    /// 不限制重复次数 —— 阵容码里存的是三个维度字母，具体合法性由 encode 校验。
    Future<void> pickEvs() async {
      final t = tables;
      if (t == null) return;
      final chosen = await showEvPicker(
        context,
        dims: t.evOrder,
        current: effectiveEvs,
      );
      if (chosen != null) onEvsChanged?.call(chosen);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- 精灵头像 ----
          // 这是**最有价值的一处图片**：认错精灵时一眼就能看出来，
          // 不用去读名字或核对系别。
          _PetPortrait(
            imagePath: icons.petIcon(effectivePetId),
            index: index,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 特性紧贴名字 —— 它是精灵的固有属性（不可改），
                    // 和名字一样属于"这只精灵是谁"的一部分。
                    // 放在下面血脉那一行会混淆：血脉是可改的，特性不是。
                    Flexible(
                      child: _EditableTitle(
                        text: displayName,
                        // 换了精灵用不同颜色标出，让用户知道自己动过什么
                        changed: petOverride != null && petOverride!.isNotEmpty,
                        onTap: canEditPet ? pickPet : null,
                      ),
                    ),
                    // 特性：精灵自带的被动，**不可改**，所以只展示。
                    // 先取到局部变量：traitName 是 getter，Dart 的类型提升
                    // 对它不生效，直接判空会报 unchecked_use_of_nullable_value。
                    if (trait != null && trait.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: _TraitChip(
                          name: trait,
                          desc: traitDesc,
                          iconPath: icons.traitIcon(trait),
                        ),
                      ),
                    ],
                    if (!resolved) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const SemanticChip(
                        label: '需要对上图鉴',
                        color: Color(0xFFD70015),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // 性格与个体资质都可以点开改 ——
                    // 用户要的是"拿到一图流之后自己搭配"，而不只是修正识别错误
                    if (effectiveNature.isNotEmpty)
                      _Meta(
                        label: '性格',
                        value: effectiveNature,
                        changed: natureOverride != null,
                        onTap: canEditNature ? pickNature : null,
                      ),
                    if (effectiveEvs.isNotEmpty)
                      _Meta(
                        label: '资质',
                        value: effectiveEvs.join(' '),
                        changed: evOverride != null,
                        onTap: canEditEvs ? pickEvs : null,
                      ),
                    // 系别：带**属性图标**，比色点信息量大
                    for (final t in displayTypes)
                      SemanticChip(
                        label: t,
                        color: TypeColors.textOf(t, Theme.of(context).brightness),
                        imagePath: icons.typeIcon(t),
                      ),
                    // 血脉：带图标，可点击修改。
                    // 注意走的是 changeBloodline（会连带清掉失效的血脉技能），
                    // 不是直接 onOverride。
                    _BloodlineControl(
                      bloodline: effectiveBloodline,
                      overridden: overrideLetter != null,
                      onChanged: changeBloodline,
                      icons: icons,
                      rankedLetters: bloodlineRanks.forPet(displayName),
                    ),
                  ],
                ),
                // 技能：**每一个都能点**（不只是"可疑"的）。
                // 用户要的是"拿到一图流之后自己搭配"，所以正常的技能也要能换。
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (var slot = 0;
                        slot < (skillList.length > 4 ? skillList.length : 4);
                        slot++)
                      if (slot < skillList.length && skillList[slot].isNotEmpty)
                        _SkillChip(
                          name: skillList[slot],
                          iconPath: icons.skillIcon(skillList[slot]),
                          suggestions:
                              pet.skillSuggestions[skillList[slot]] ?? const [],
                          // 「可疑」只用来提示"这个可能是读错了"，
                          // 不再决定"能不能点" —— 所有技能都能点。
                          suspect: pet.skillSuggestions
                              .containsKey(skillList[slot]),
                          changed: skillOverride != null &&
                              skillList[slot] !=
                                  (pet.skills.length > slot
                                      ? pet.skills[slot]
                                      : ''),
                          onTap: () => pickSkill(slot, skillList[slot]),
                        )
                      else if (slot >= skillList.length ||
                          skillList[slot].isEmpty)
                        // 空槽：给一个明确的"添加"入口。
                        // 技能数可以少于 4，所以这个入口要一直在。
                        _AddSkillChip(
                          onTap: () => pickSkill(slot, ''),
                        ),
                  ],
                ),
                for (final w in pet.warnings) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 13, color: c.warning),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          w,
                          style: TextStyle(
                            fontSize: AppType.sCaption,
                            color: c.textSecondary,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                // 名字有多个形态且自动消歧失败 -> 让用户点一下选。
                // 这是"模型只读到基础名 -> 直接报错 -> 用户卡住"的解法：
                // 不重新识别、不重新调模型，点一下就地解决。
                if (pet.needsVariantChoice) ...[
                  const SizedBox(height: AppSpacing.md),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '选择形态',
                        style: TextStyle(
                          fontSize: AppType.sCaption,
                          fontWeight: FontWeight.w600,
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final v in pet.variants)
                            _VariantChip(
                              variant: v,
                              selected: v.code == chosenVariant,
                              onTap: () => onChooseVariant(v.code),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 精灵头像 + 左上角序号。
///
/// 序号跟着头像走（原来在名字前面），这样"第几只"和"长什么样"是一个整体，
/// 视线不用来回横跳。
class _PetPortrait extends StatelessWidget {
  const _PetPortrait({required this.imagePath, required this.index});

  final String? imagePath;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const size = 52.0;
    return SizedBox(
      width: size,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: c.bgGrouped,
                  borderRadius: AppRadii.thumbR,
                ),
                clipBehavior: Clip.antiAlias,
                child: imagePath == null
                    ? Icon(Icons.catching_pokemon,
                        size: 24, color: c.textTertiary)
                    : Image.asset(
                        imagePath!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) => Icon(
                          Icons.catching_pokemon,
                          size: 24,
                          color: c.textTertiary,
                        ),
                      ),
              ),
              // 序号压在头像左下角，用底色描一圈保证任何图片上都看得清
              Positioned(
                left: -2,
                bottom: -2,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.textPrimary,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.surface, width: 1.5),
                  ),
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: c.surface,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 魔法一行。可点开改成另外两个（或手动填写）。
///
/// 魔法表只有 3 个：进化之力(ZZH) / 光合治愈(ZZB) / 愿力强化(ZZC)。
/// 名字容易记混（例如把「愿力强化」记成「愿力冲击」），所以列表来自知识库
/// 而不是写死在界面里。
class _MagicRow extends StatelessWidget {
  const _MagicRow({
    required this.magic,
    required this.options,
    required this.onChanged,
  });

  final String magic;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 识别到的魔法不在合法表里 -> 标出来，让用户知道要核对
    final valid = options.isEmpty || options.contains(magic);

    return SettingsRow(
      title: '魔法',
      subtitle: valid ? magic : '「$magic」不在魔法表里，请核对',
      leading: Icon(
        valid ? Icons.auto_fix_high_outlined : Icons.warning_amber_rounded,
        size: 20,
        color: valid ? c.textSecondary : c.warning,
      ),
      trailing: Icon(Icons.edit_outlined, size: 18, color: c.textTertiary),
      onTap: () => _pick(context),
    );
  }

  void _pick(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cc = Theme.of(ctx).extension<AppColors>()!;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('选择魔法', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '会直接写进阵容码，选错了整支队伍的魔法就错了',
                  style: TextStyle(
                    fontSize: AppType.sCaption,
                    color: cc.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final m in options)
                      ChoiceChip(
                        label: Text(m),
                        selected: m == magic,
                        onSelected: (_) {
                          onChanged(m);
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 带参考图的可选项。图标让用户**看图选**，比读名字靠谱。
class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.label,
    required this.iconPath,
    required this.onTap,
    this.badge,
    this.highlighted = false,
    this.lockedNote,
  });

  final String label;
  final String? iconPath;
  final VoidCallback onTap;

  /// 右上角的小标记（匹配度）。
  final String? badge;

  /// 是否为"推荐候选"（描边高亮）。
  final bool highlighted;

  /// 因血脉不可用时的说明（如"需恶系血脉"）。
  ///
  /// 有这个标记的技能**仍然可点** —— 用户可以先去改血脉。
  /// 这里只做提示，不做拦截：拦住了用户反而不知道有这条路径。
  final String? lockedNote;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final locked = lockedNote != null;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.inputR,
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: highlighted ? c.accentSubtle : c.surface,
          borderRadius: AppRadii.inputR,
          border: Border.all(
            color: highlighted ? c.accent.withValues(alpha: 0.4) : c.separator,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Opacity(
                  // 不可用的压暗一点，一眼能和可用的区分开
                  opacity: locked ? 0.45 : 1.0,
                  child: RefIcon(
                    assetPath: iconPath,
                    size: 40,
                    fallbackText: label,
                  ),
                ),
                if (badge != null)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: AppRadii.pillR,
                      ),
                      child: Text(
                        badge!,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: c.onAccent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppType.sCaption,
                fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
                color: locked
                    ? c.textTertiary
                    : (highlighted ? c.accent : c.textPrimary),
                height: 1.25,
              ),
            ),
            if (locked) ...[
              const SizedBox(height: 2),
              // 说明"为什么现在不能用"，而不是只说"不可用"
              Text(
                lockedNote!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  color: c.textTertiary,
                  height: 1.1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一个技能标签。**每一个都能点开改**。
///
/// 三种视觉状态：
///   * 正常：静态灰底
///   * 可疑（模型可能读错了）：橙色描边 + 放大镜图标
///   * 改过：强调色描边，让用户知道自己动过哪些
///
/// 曾经只有"可疑"的才能点 —— 那样用户拿到识别结果后**没法自由搭配**，
/// 只能修正错误。现在点击不再由状态决定。
class _SkillChip extends StatelessWidget {
  const _SkillChip({
    required this.name,
    required this.iconPath,
    required this.suggestions,
    required this.suspect,
    required this.changed,
    required this.onTap,
  });

  final String name;

  /// 技能图标。有图时直接显示图 + 名字，一眼能核对。
  final String? iconPath;

  final List<SkillSuggestion> suggestions;

  /// 模型可能读错了（有纠错候选）。
  final bool suspect;

  /// 用户改过这一格。
  final bool changed;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 改过 > 可疑 > 正常，优先级高的决定配色
    final Color bg;
    final Color border;
    final Color fg;
    if (changed) {
      bg = c.accentSubtle;
      border = c.accent.withValues(alpha: 0.45);
      fg = c.accent;
    } else if (suspect) {
      bg = c.warning.withValues(alpha: 0.10);
      border = c.warning.withValues(alpha: 0.4);
      fg = c.textPrimary;
    } else {
      bg = c.bgGrouped;
      border = Colors.transparent;
      fg = c.textSecondary;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.pillR,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadii.pillR,
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图标在最前：读名字之前先看图，认错时视觉上立刻有反应
            if (iconPath != null)
              RefIcon(assetPath: iconPath, size: 18, fallbackText: name),
            if (suspect && !changed) ...[
              const SizedBox(width: 4),
              Icon(Icons.spellcheck, size: 11, color: c.warning),
            ],
            const SizedBox(width: 5),
            Text(
              name,
              style: TextStyle(
                fontSize: AppType.sCaption,
                color: fg,
                fontWeight: (suspect || changed) ? FontWeight.w600 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空技能槽的「添加」入口。
///
/// 存在的意义：技能可以少于 4 个，所以必须有地方点着加回来 ——
/// 否则用户删掉一个技能之后就再也加不回去了。
class _AddSkillChip extends StatelessWidget {
  const _AddSkillChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.pillR,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: AppRadii.pillR,
          border: Border.all(color: c.separator, style: BorderStyle.solid),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 13, color: c.textTertiary),
            const SizedBox(width: 3),
            Text(
              '加技能',
              style: TextStyle(
                fontSize: AppType.sCaption,
                color: c.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 可点击的精灵名。
class _EditableTitle extends StatelessWidget {
  const _EditableTitle({
    required this.text,
    required this.changed,
    required this.onTap,
  });

  final String text;
  final bool changed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            text,
            style: context.texts.titleSmall?.copyWith(
              color: changed ? c.accent : null,
            ),
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 5),
          Icon(Icons.swap_horiz, size: 15, color: c.textTertiary),
        ],
      ],
    );
    if (onTap == null) return label;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.thumbR,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: label,
      ),
    );
  }
}

/// 技能选择面板。
///
/// 两个用途共用（这也是同一个面板能同时服务"纠错"和"重新搭配"的原因）：
///   * **纠错**：模型读错了 -> 顶部给近似候选，点一下就好
///   * **重新搭配**：用户想换 -> 切到"全部技能"搜索，579 个都能选
///
/// 候选带**图标** —— 图标是 128px 的绘制图，名字是 10px 的扭曲汉字，
/// 看图比读字靠谱得多。这也是「二轮图标比对」那个思路真正有用的落点：
/// 让**人**比对，而不是让模型比对（后者实测更差，见 PASS2_FINDINGS.md）。
class _SkillFixSheet extends StatefulWidget {
  const _SkillFixSheet({
    required this.readName,
    required this.suggestions,
    required this.learnable,
    required this.locked,
    required this.lockedReasonOf,
    required this.icons,
    this.allSkills,
    this.onPickLocked,
  });

  /// 当前的技能名（可能是模型读错的）。
  final String readName;

  /// 近似候选（已按匹配度排序）。
  final List<SkillSuggestion> suggestions;

  /// 这只精灵能学的全部技能名（含全部血脉技能）。
  final List<String> learnable;

  /// 当前血脉下用不了的技能名。
  ///
  /// 它们**仍然可选**（用户可以换血脉），只是标出来免得困惑。
  final Set<String> locked;

  /// 不可用的原因文案（如"需恶系血脉"）。
  final String? Function(String) lockedReasonOf;

  /// 参考图标（可为空：没有图标资源时功能照常）。
  final IconAssets icons;

  /// 全部技能名（579 个）。为 null 时不给"全部技能"这个范围。
  final List<String>? allSkills;

  /// 选了一个"当前血脉学不了"的技能。参数是技能名。
  ///
  /// 由 `_PetRow` 实现：**自动把血脉改成这条技能需要的系别**，
  /// 并清掉原本占位的血脉技能。为 null 时锁住的技能不可选。
  final void Function(String skill)? onPickLocked;

  @override
  State<_SkillFixSheet> createState() => _SkillFixSheetState();
}

class _SkillFixSheetState extends State<_SkillFixSheet> {
  late final TextEditingController _c =
      TextEditingController(text: widget.readName);
  String _filter = '';

  /// false = 只列这只精灵能学的；true = 全部 579 个。
  bool _allScope = false;

  /// 当前的候选源。
  List<String> get _source => (_allScope && widget.allSkills != null)
      ? widget.allSkills!
      : widget.learnable;

  /// 过滤后的候选 —— **不再截断**。
  ///
  /// 曾经取前 24 个（理由是"再多的用搜索"），结果是**用户根本看不到想要的技能**：
  /// 雪影娃娃能学 50 个，「贪婪」按名字排序在第 40 位，所以它虽然在数据里、
  /// 也在候选池里，界面上却完全看不到。
  ///
  /// 现在交给懒加载的 GridView（只建可见的那些），所以可以放心给全量。
  /// 匹配的排在前面（按首次出现位置），让搜索更有用。
  List<String> get _pool {
    final f = _filter;
    if (f.isEmpty) return _source;
    final hits = _source.where((s) => s.contains(f)).toList();
    hits.sort((a, b) => a.indexOf(f).compareTo(b.indexOf(f)));
    return hits;
  }

  /// 匹配总数。
  int get _matchCount => _pool.length;

  /// 点击一个候选技能。三种情况分开处理，**不能有"静默写进去"的路径**：
  ///
  ///   1. 可用             -> 直接选，关抽屉
  ///   2. 这只精灵能学、但当前血脉学不了
  ///                      -> 自动切血脉 + 清掉占位的血脉技能（onPickLocked）
  ///   3. **这只精灵压根学不了**（"全部技能"范围里选了个它没有的技能）
  ///                      -> 拦下来，提示不可学。
  ///                         切血脉也解决不了，写进去只会生成废配置。
  ///
  /// [learnable] 是"能学的全部"（含血脉技能），所以它是判断 2 和 3 的分界。
  void _tapSkill(String s) {
    final canLearn = widget.learnable.contains(s);
    final lockedNow = widget.locked.contains(s);

    // 情况 3：彻底学不了
    if (!canLearn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('「$s」不在这个精灵能学的技能里，选了游戏里也用不了'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // 情况 1：当前就能用
    if (!lockedNow) {
      Navigator.pop(context, s);
      return;
    }

    // 情况 2：能学，但要先改血脉
    final pick = widget.onPickLocked;
    if (pick == null) {
      // 没接回调就别放行 —— 写进去是废配置，不如让用户知道原因
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.lockedReasonOf(s) ?? '当前血脉下不可用')),
      );
      return;
    }
    // 由父级负责切血脉 + 清占位；它会自己关抽屉
    pick(s);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 候选池由 _pool 计算（支持"它能学的 / 全部技能"两种范围）
    final pool = _pool;
    // 键盘弹出时要让位，否则搜索框会被挡住
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height - keyboard;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: keyboard,
      ),
      // 固定高度（不是 maxHeight）：底部按钮要**钉在底部**，
      // 只有中间那块滚动。用 maxHeight + 整体滚动会让按钮跟着滚走 ——
      // 候选多的时候用户得先滚到底才能点"清空"。
      child: SizedBox(
        height: maxH * 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ================= 固定区：标题 / 候选 / 范围 / 搜索 =================
            Text('修正技能', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '图上读到的是「${widget.readName}」',
              style: TextStyle(fontSize: AppType.sCaption, color: c.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),

            if (widget.suggestions.isNotEmpty) ...[
              Text(
                '可能是这些',
                style: TextStyle(
                  fontSize: AppType.sCaption,
                  fontWeight: FontWeight.w600,
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // 候选可能有很多（最多 4 个），横向滚动避免把固定区撑高
              SizedBox(
                height: 88,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.suggestions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (_, i) {
                    final s = widget.suggestions[i];
                    return _IconChoice(
                      label: s.name,
                      badge: '${s.percent}%',
                      iconPath: widget.icons.skillIcon(s.name),
                      highlighted: true,
                      onTap: () => Navigator.pop(context, s.name),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ] else ...[
              InlineNotice(
                message: '没有找到相近的技能。可能是图上字太小看错了，'
                    '也可能这个技能本来就不在它的可学列表里。',
                severity: NoticeSeverity.info,
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // 范围切换：默认只列"它能学的"，需要自由搭配时切到全表。
            //
            // 为什么默认限定范围：纠错场景下这只能学的比全表 579 个快得多。
            // 为什么要能切到全表：用户可能就想配一个它学不了的技能
            // （游戏允许，阵容码也存得下），不能因为"不在可学列表"就挡住。
            if (widget.allSkills != null)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('它能学的')),
                  ButtonSegment(value: true, label: Text('全部技能')),
                ],
                selected: {_allScope},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
                onSelectionChanged: (s) =>
                    setState(() => _allScope = s.first),
              ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _c,
              autofocus: false,
              decoration: InputDecoration(
                hintText: '搜索或直接输入技能名',
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: '确定',
                  icon: const Icon(Icons.check, size: 20),
                  onPressed: () => Navigator.pop(context, _c.text.trim()),
                ),
              ),
              onChanged: (v) => setState(() => _filter = v.trim()),
              onSubmitted: (v) => Navigator.pop(context, v.trim()),
            ),

            // ================= 滚动区（懒加载）=================
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  _filter.isEmpty
                      ? (_allScope ? '全部 ${pool.length} 个' : '它能学的 ${pool.length} 个')
                      : '匹配「$_filter」的 $_matchCount 个',
                  style: TextStyle(
                      fontSize: AppType.sCaption, color: c.textTertiary),
                ),
                if (!_allScope && widget.locked.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.xs),
                  // 压缩成一行，把纵向空间留给候选
                  Flexible(
                    child: Text(
                      '· 灰掉的 ${widget.locked.length} 个要先改血脉',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: AppType.sCaption, color: c.textTertiary),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Expanded(
              child: pool.isEmpty
                  ? Center(
                      child: Text(
                        '没有匹配的技能',
                        style: TextStyle(
                            fontSize: AppType.sCaption, color: c.textTertiary),
                      ),
                    )
                  : GridView.builder(
                      // 懒加载：只构建可见的行。所以给全量也不会卡。
                      padding: EdgeInsets.zero,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 88,
                        mainAxisSpacing: AppSpacing.xs,
                        crossAxisSpacing: AppSpacing.xs,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: pool.length,
                      itemBuilder: (_, i) {
                        final s = pool[i];
                        return _IconChoice(
                          label: s,
                          iconPath: widget.icons.skillIcon(s),
                          // 因血脉不可用的标出来；点它会自动切血脉（见 _tapSkill）
                          lockedNote: widget.locked.contains(s)
                              ? widget.lockedReasonOf(s)
                              : null,
                          onTap: () => _tapSkill(s),
                        );
                      },
                    ),
            ),

            // ================= 固定底部按钮栏 =================
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, ''),
                    child: const Text('清空这个技能'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


/// 一个形态候选。显示「后缀 + 系别」，因为系别正是区分它们的依据。
class _VariantChip extends StatelessWidget {
  const _VariantChip({
    required this.variant,
    required this.selected,
    required this.onTap,
  });

  final VariantCandidate variant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 自动消歧时算出的分数：>0 表示与图上系别有重合，值得给用户一个视觉提示
    final hint = variant.score > 0 && variant.score < 1 ? ' (${(variant.score * 100).round()}% 匹配)' : '';

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.pillR,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? c.accentSubtle : Colors.transparent,
          borderRadius: AppRadii.pillR,
          border: Border.all(
            color: selected ? c.accent : c.separator,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              variant.suffix.isEmpty ? variant.name : variant.suffix,
              style: TextStyle(
                fontSize: AppType.sCaption,
                fontWeight: FontWeight.w600,
                color: selected ? c.accent : c.textPrimary,
              ),
            ),
            if (variant.types.isNotEmpty) ...[
              const SizedBox(width: 6),
              for (final t in variant.types) ...[
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(
                    color: TypeColors.of(t),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
            if (hint.isNotEmpty)
              Text(
                hint,
                style: TextStyle(fontSize: AppType.sCaption, color: c.textTertiary),
              ),
          ],
        ),
      ),
    );
  }
}

/// 特性芯片：图标 + 名字，点开看完整描述。
///
/// 特性是**精灵固有**的（不在阵容码里、不可改），所以这个芯片
/// **没有编辑入口** —— 与旁边可点的性格/资质/血脉形成对比，一眼能分清
/// "哪些是我能改的"。
///
/// 描述默认不显示：特性描述动辄 30+ 字，6 只精灵全铺开会把卡片撑爆，
/// 而用户多数时候只想确认"特性对不对"。要看说明点一下即可。
class _TraitChip extends StatelessWidget {
  const _TraitChip({
    required this.name,
    required this.desc,
    required this.iconPath,
  });

  final String name;

  /// 为空表示数据包里没有这个特性的描述（仍显示名字）。
  final String? desc;

  final String? iconPath;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasDesc = desc != null && desc!.isNotEmpty;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: c.bgGrouped,
        borderRadius: AppRadii.pillR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (iconPath != null)
            RefIcon(assetPath: iconPath, size: 16, fallbackText: name),
          if (iconPath != null) const SizedBox(width: 4),
          Text(
            name,
            style: TextStyle(
              fontSize: AppType.sCaption,
              color: c.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hasDesc) ...[
            const SizedBox(width: 3),
            Icon(Icons.info_outline, size: 11, color: c.textTertiary),
          ],
        ],
      ),
    );

    if (!hasDesc) return chip;
    return InkWell(
      onTap: () => _showTraitSheet(context, name: name, desc: desc!),
      borderRadius: AppRadii.pillR,
      child: chip,
    );
  }
}

Future<void> _showTraitSheet(
  BuildContext context, {
  required String name,
  required String desc,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: AppSpacing.sm),
              // 明确写出来，免得用户找"怎么改特性"
              Text(
                '精灵固有 · 不可改',
                style: TextStyle(
                  fontSize: AppType.sCaption,
                  color: context.colors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(desc, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    ),
  );
}

/// 一个"标签 + 值"的小单元。[onTap] 不为 null 时可点开修改。
class _Meta extends StatelessWidget {
  const _Meta({
    required this.label,
    required this.value,
    this.onTap,
    this.changed = false,
  });

  final String label;
  final String value;

  /// 点开修改。为 null 时只读。
  final VoidCallback? onTap;

  /// 用户改动过。用强调色标出，让用户知道自己动过什么。
  final bool changed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppType.sCaption,
            color: c.textTertiary,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          value,
          style: TextStyle(
            fontSize: AppType.sCaption,
            fontWeight: FontWeight.w600,
            color: changed ? c.accent : c.textPrimary,
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 3),
          Icon(Icons.edit_outlined, size: 11, color: c.textTertiary),
        ],
      ],
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.thumbR,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: row,
      ),
    );
  }
}

/// 个体资质选择器：从 6 个维度里选 3 个。
///
/// 为什么不用可搜索列表：只有 6 个选项，静态网格更快。
/// 用「顺序敏感」的三个槽而不是三个下拉 —— 阵容码里三个维度的顺序是有意义的
/// （首项/次项/第三项的统计分布不同），顺序错了码就不同。
Future<List<String>?> showEvPicker(
  BuildContext context, {
  required List<String> dims,
  required List<String> current,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _EvPickerSheet(dims: dims, current: current),
  );
}

class _EvPickerSheet extends StatefulWidget {
  const _EvPickerSheet({required this.dims, required this.current});

  final List<String> dims;
  final List<String> current;

  @override
  State<_EvPickerSheet> createState() => _EvPickerSheetState();
}

class _EvPickerSheetState extends State<_EvPickerSheet> {
  late final List<String?> _picked = [
    for (var i = 0; i < 3; i++)
      i < widget.current.length ? widget.current[i] : null,
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('选择个体资质',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '三项，顺序有意义（顺序不同阵容码也不同）',
                style: TextStyle(
                  fontSize: AppType.sCaption,
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              for (var slot = 0; slot < 3; slot++) ...[
                Text(
                  switch (slot) { 0 => '第一项', 1 => '第二项', _ => '第三项' },
                  style: TextStyle(
                    fontSize: AppType.sCaption,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final d in widget.dims)
                      ChoiceChip(
                        label: Text(d),
                        selected: _picked[slot] == d,
                        onSelected: (_) => setState(() {
                          // 点已选中的就取消这一项（允许少于 3 个）
                          _picked[slot] = _picked[slot] == d ? null : d;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final out = _picked.whereType<String>().toList();
                        // 三项必须齐 —— 阵容码里就是三个字母
                        if (out.length != 3) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('三项都要选')),
                          );
                          return;
                        }
                        Navigator.pop(context, out);
                      },
                      child: const Text('确定'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 血脉显示与修改。
///
/// 为什么这块要可交互：图标识别在「恶 / 龙」这类小尺寸下有真实歧义，
/// 与其让程序猜，不如把结果摆出来让用户点一下改掉。
///
/// 选择器里带**血脉图标**：24 个图标的形状差异很明显（首领是金红皇冠、
/// 翼是青蓝羽翼），看图选比读名字快得多。
class _BloodlineControl extends StatelessWidget {
  const _BloodlineControl({
    required this.bloodline,
    required this.overridden,
    required this.onChanged,
    required this.icons,
    this.rankedLetters = const [],
  });

  final String bloodline;
  final bool overridden;
  final ValueChanged<String?> onChanged;
  final IconAssets icons;

  /// 本地匹配给的候选顺序（最可能的在前）。空则按字母表顺序。
  ///
  /// 实测自动判定不可靠（本地匹配单独作答只有 0-2/6），
  /// 但**排序**有用（正确项进前 3 的比例 5/6）。所以用它把候选排前面，
  /// 而不是让它替用户决定 —— 用户从「24 个里找」变成「3 个里挑」。
  final List<String> rankedLetters;

  /// 全部 24 条血脉，按字母表顺序（与阵容码一致）。
  static const _all = [
    ('B', '普通'), ('C', '草'), ('D', '火'), ('E', '水'), ('F', '光'),
    ('G', '地'), ('H', '冰'), ('I', '龙'), ('J', '电'), ('K', '毒'),
    ('L', '虫'), ('M', '武'), ('N', '翼'), ('O', '萌'), ('P', '幽'),
    ('Q', '恶'), ('R', '机械'), ('S', '幻'), ('T', '首领'), ('U', '巨兽'),
    ('V', '黑魔法'), ('W', '异核'), ('X', '污染'), ('Y', '奇异'),
  ];

  /// 当前血脉名对应的字母；不在 24 条里返回 null。
  ///
  /// 图标索引是按**字母**键的，而界面这里拿到的是名字（如「首领」）。
  String? get _bloodlineLetter {
    final n = bloodline.endsWith('血脉')
        ? bloodline.substring(0, bloodline.length - 2)
        : bloodline;
    for (final (letter, name) in _all) {
      if (name == n) return letter;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final has = bloodline.isNotEmpty;

    return InkWell(
      borderRadius: AppRadii.pillR,
      onTap: () => _showPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: has
              ? BloodlineColors.subtleOf(bloodline)
              : c.bgGrouped,
          borderRadius: AppRadii.pillR,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 有图标就用图标（一眼认出是哪个血脉），没有才退回色点
            if (has && _bloodlineLetter != null &&
                icons.bloodlineIcon(_bloodlineLetter!) != null)
              RefIcon(
                assetPath: icons.bloodlineIcon(_bloodlineLetter!),
                size: 15,
                fallbackText: bloodline,
              )
            else
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: has
                      ? BloodlineColors.of(bloodline)
                      : c.textTertiary,
                  shape: BoxShape.circle,
                ),
              ),
            const SizedBox(width: 5),
            Text(
              has ? '$bloodline血脉' : '血脉未识别',
              style: TextStyle(
                fontSize: AppType.sCaption,
                fontWeight: FontWeight.w600,
                color: has
                    ? BloodlineColors.textOf(
                        bloodline, Theme.of(context).brightness)
                    : c.textSecondary,
              ),
            ),
            if (overridden) ...[
              const SizedBox(width: 4),
              Icon(Icons.edit, size: 11, color: c.textTertiary),
            ],
          ],
        ),
      ),
    );
  }

  /// 推荐候选里**有效**的那些（去掉不在 24 条血脉里的字母）。
  ///
  /// 取前 3：实测正确答案进前 3 的比例是 5/6，取更多就失去"缩小范围"的意义。
  ///
  /// ⚠️ **这个列表必须和下面"其余全部"的排除条件用同一个**。
  /// 曾经踩过的 bug：推荐位取前 3（如 `[S,H,I]`），但排除用的是完整排序
  /// (`[S,H,I,N,J,Y]`)，于是排第 4~6 的血脉既不在推荐里、又不在其余列表里，
  /// **凭空消失** —— 每只精灵少 9 个可选血脉，用户直接发现「翼 没了」。
  /// 所以"推荐集"只应有一个定义，就是这里。
  List<String> get _rankedInOrder =>
      rankedLetters.where((l) => _nameOf(l) != null).take(3).toList();

  /// 字母 -> 血脉名；不在表里返回 null。
  static String? _nameOf(String letter) {
    for (final (l, name) in _all) {
      if (l == letter) return name;
    }
    return null;
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // 手机上 25 个格子放不下，必须允许内容滚动
      isScrollControlled: true,
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('选择血脉', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '图标识别在这个位置可能有歧义，你可以直接指定',
                  style: TextStyle(
                    fontSize: AppType.sCaption,
                    color: Theme.of(ctx).extension<AppColors>()!.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                // 限制高度并允许滚动：不设上限时 Column 会顶出屏幕，
                // 底部的血脉（污染/奇异）就点不到了。
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: media.size.height * 0.6,
                    ),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          // 「无血脉」放在最前：它是常见状态，也最容易被误设成别的
                          _IconChoice(
                            label: '无血脉',
                            iconPath: null,
                            onTap: () {
                              onChanged(null);
                              Navigator.pop(ctx);
                            },
                          ),

                          // ---- 本地匹配推荐的候选（排前面，带编号）----
                          // 它们只是"最可能的几个"，不是判定结果。看一眼图基本就能定。
                          for (final letter in _rankedInOrder)
                            if (_nameOf(letter) != null)
                              _IconChoice(
                                label: _nameOf(letter)!,
                                iconPath: icons.bloodlineIcon(letter),
                                highlighted: bloodline == _nameOf(letter),
                                badge: '推荐',
                                onTap: () {
                                  onChanged(_nameOf(letter));
                                  Navigator.pop(ctx);
                                },
                              ),

                          // ---- 其余全部（按字母表，方便自己找）----
                          // 排除条件必须用 _rankedInOrder（实际渲染出来的推荐集），
                          // 不能用完整的 rankedLetters —— 否则排名靠后的会被吞掉。
                          for (final (letter, name) in _all)
                            if (!_rankedInOrder.contains(letter))
                              _IconChoice(
                                label: name,
                                iconPath: icons.bloodlineIcon(letter),
                                highlighted: bloodline == name,
                                onTap: () {
                                  onChanged(name);
                                  Navigator.pop(ctx);
                                },
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
