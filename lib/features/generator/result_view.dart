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
import '../../core/icon_assets.dart';
import '../../core/pipeline.dart';
import '../../core/skill_matcher.dart';
import '../../core/variant_hints.dart';
import '../../theme/tokens.dart';
import '../../theme/type_colors.dart';
import '../../theme/typography.dart';
import '../../widgets/common.dart';

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

  /// 用户修正过的技能表，键是「第几只」（从 1 开始）。
  final Map<int, List<String>> skillOverrides;

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
                  onOverride: (letter) =>
                      onOverrideBloodline(i + 1, letter),
                  onChooseVariant: (c) => onChooseVariant(i + 1, c),
                  onSkillsChanged: (list) => onSkillsChanged(i + 1, list),
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
    required this.onOverride,
    required this.onChooseVariant,
    required this.onSkillsChanged,
    required this.icons,
    required this.bloodlineRanks,
  });

  final int index;
  final RecognizedPet pet;
  final String? overrideLetter;
  final String? chosenVariant;

  /// 用户在界面上修正过的技能表。为空表示用识别结果。
  final List<String>? skillOverride;

  /// 这只精灵**能学**的技能名（用于手动填写的提示范围）。
  /// 由上层从知识库取，避免这里再依赖整张表。
  final List<String> learnable;

  final ValueChanged<String?> onOverride;
  final ValueChanged<String> onChooseVariant;
  final ValueChanged<List<String>> onSkillsChanged;

  /// 参考图标（血脉 / 技能）。
  final IconAssets icons;

  /// 血脉候选的本地排序。
  final BloodlineRanks bloodlineRanks;

  /// 当前生效的技能表：用户改过就用改过的，否则用识别结果。
  List<String> get skillList => skillOverride ?? pet.skills;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 用户选过形态就算已解决，哪怕模型没认出来
    final resolved = pet.resolved || (chosenVariant?.isNotEmpty ?? false);
    final effectiveBloodline = overrideLetter ?? pet.bloodline;
    // 头像要跟着"当前生效的精灵码"走：用户选了形态就显示那个形态的头像，
    // 否则认错时头像会和名字不符，反而误导。
    final effectivePetId = (chosenVariant != null && chosenVariant!.isNotEmpty)
        ? chosenVariant
        : pet.petId;
    final chosenName = chosenVariant == null
        ? null
        : pet.variants
            .where((v) => v.code == chosenVariant)
            .map((v) => v.name)
            .firstOrNull;

    /// 把第 slot 个技能换成 newName（空串表示清空该槽）。
    void replaceSkill(int slot, String newName) {
      final next = List<String>.from(skillList);
      while (next.length < 4) {
        next.add('');
      }
      next[slot] = newName;
      onSkillsChanged(next);
    }

    Future<void> pickSkill(int slot, String current) async {
      final chosen = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _SkillFixSheet(
          readName: current,
          suggestions: pet.skillSuggestions[current] ?? const [],
          learnable: learnable,
          icons: icons,
        ),
      );
      if (chosen == null) return;
      replaceSkill(slot, chosen);
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
                    Expanded(
                      child: Text(
                        chosenName ?? pet.name,
                        style: context.texts.titleSmall,
                      ),
                    ),
                    if (!resolved)
                      const SemanticChip(
                        label: '需要对上图鉴',
                        color: Color(0xFFD70015),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (pet.nature.isNotEmpty)
                      _Meta(label: '性格', value: pet.nature),
                    if (pet.evs.isNotEmpty)
                      _Meta(label: '资质', value: pet.evs.join(' ')),
                    // 系别：带**属性图标**，比色点信息量大
                    for (final t in pet.types)
                      SemanticChip(
                        label: t,
                        color: TypeColors.textOf(t, Theme.of(context).brightness),
                        imagePath: icons.typeIcon(t),
                      ),
                    // 血脉：带图标，可点击修改
                    _BloodlineControl(
                      bloodline: effectiveBloodline,
                      overridden: overrideLetter != null,
                      onChanged: onOverride,
                      icons: icons,
                      rankedLetters: bloodlineRanks.forPet(pet.name),
                    ),
                  ],
                ),
                if (skillList.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (var slot = 0; slot < skillList.length; slot++)
                        if (skillList[slot].isNotEmpty)
                          _SkillChip(
                            name: skillList[slot],
                            iconPath: icons.skillIcon(skillList[slot]),
                            // 读不准的（不在技能表里、或有候选）才可点，正常的保持静默
                            suggestions:
                                pet.skillSuggestions[skillList[slot]] ?? const [],
                            suspect: (skillOverride != null &&
                                    skillList[slot] !=
                                        (pet.skills.length > slot
                                            ? pet.skills[slot]
                                            : '')) ||
                                pet.skillSuggestions
                                    .containsKey(skillList[slot]),
                            onTap: () => pickSkill(slot, skillList[slot]),
                          ),
                    ],
                  ),
                ],
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
  });

  final String label;
  final String? iconPath;
  final VoidCallback onTap;

  /// 右上角的小标记（匹配度）。
  final String? badge;

  /// 是否为"推荐候选"（描边高亮）。
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
                RefIcon(assetPath: iconPath, size: 40, fallbackText: label),
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
                color: highlighted ? c.accent : c.textPrimary,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一个技能标签。
///
/// - 正常读出的技能：静态灰底，不可点
/// - 读不准的（有候选或不在技能表里）：描边高亮 + 可点，点开纠错面板
class _SkillChip extends StatelessWidget {
  const _SkillChip({
    required this.name,
    required this.iconPath,
    required this.suggestions,
    required this.suspect,
    required this.onTap,
  });

  final String name;

  /// 技能图标。有图时直接显示图 + 名字，一眼能核对。
  final String? iconPath;

  final List<SkillSuggestion> suggestions;
  final bool suspect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: suspect ? c.warning.withValues(alpha: 0.10) : c.bgGrouped,
        borderRadius: AppRadii.pillR,
        border: suspect
            ? Border.all(color: c.warning.withValues(alpha: 0.4))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 图标在最前：读名字之前先看图，认错时视觉上立刻有反应
          if (iconPath != null)
            RefIcon(assetPath: iconPath, size: 18, fallbackText: name),
          if (suspect) ...[
            const SizedBox(width: 4),
            Icon(Icons.spellcheck, size: 11, color: c.warning),
          ],
          const SizedBox(width: 5),
          Text(
            name,
            style: TextStyle(
              fontSize: AppType.sCaption,
              color: suspect ? c.textPrimary : c.textSecondary,
              fontWeight: suspect ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );

    if (!suspect) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.pillR,
      child: body,
    );
  }
}

/// 技能纠错面板：候选优先，实在没有就手动填。
///
/// 候选带**图标** —— 图标是 128px 的绘制图，名字是 10px 的扭曲汉字，
/// 看图比读字靠谱得多。这也是「二轮图标比对」那个思路真正有用的落点：
/// 让**人**比对，而不是让模型比对（后者实测更差，见 PASS2_FINDINGS.md）。
class _SkillFixSheet extends StatefulWidget {
  const _SkillFixSheet({
    required this.readName,
    required this.suggestions,
    required this.learnable,
    required this.icons,
  });

  /// 模型读到的名字（可能是错的）。
  final String readName;

  /// 近似候选（已按匹配度排序）。
  final List<SkillSuggestion> suggestions;

  /// 这只精灵能学的全部技能名（用于手动填写的候选池）。
  final List<String> learnable;

  /// 参考图标（可为空：没有图标资源时功能照常）。
  final IconAssets icons;

  @override
  State<_SkillFixSheet> createState() => _SkillFixSheetState();
}

class _SkillFixSheetState extends State<_SkillFixSheet> {
  late final TextEditingController _c =
      TextEditingController(text: widget.readName);
  String _filter = '';

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 手动填写时的候选池：按输入过滤这只精灵能学的技能
    final pool = _filter.isEmpty
        ? widget.learnable.take(12).toList()
        : widget.learnable.where((s) => s.contains(_filter)).take(12).toList();

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      // 必须给高度上限：SingleChildScrollView 本身不会约束高度，
      // 内容高于可用空间时会直接溢出（黄黑条纹），而不是变成可滚动。
      // 键盘弹出时可用空间更小，这个上限尤其要紧。
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text('修正技能', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '图上读到的是「${widget.readName}」',
              style: TextStyle(fontSize: AppType.sCaption, color: c.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),

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
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final s in widget.suggestions)
                    _IconChoice(
                      label: s.name,
                      badge: '${s.percent}%',
                      iconPath: widget.icons.skillIcon(s.name),
                      highlighted: true,
                      onTap: () => Navigator.pop(context, s.name),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
            ] else ...[
              InlineNotice(
                message: '没有找到相近的技能。可能是图上字太小看错了，'
                    '也可能这个技能本来就不在它的可学列表里。',
                severity: NoticeSeverity.info,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            Text(
              '手动填写',
              style: TextStyle(
                fontSize: AppType.sCaption,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _c,
              autofocus: false,
              decoration: InputDecoration(
                hintText: '技能名',
                suffixIcon: IconButton(
                  tooltip: '确定',
                  icon: const Icon(Icons.check, size: 20),
                  onPressed: () => Navigator.pop(context, _c.text.trim()),
                ),
              ),
              onChanged: (v) => setState(() => _filter = v.trim()),
              onSubmitted: (v) => Navigator.pop(context, v.trim()),
            ),
            if (pool.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _filter.isEmpty ? '它能学的技能（前 12 个）' : '匹配的技能',
                style: TextStyle(fontSize: AppType.sCaption, color: c.textTertiary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final s in pool)
                    _IconChoice(
                      label: s,
                      iconPath: widget.icons.skillIcon(s),
                      onTap: () => Navigator.pop(context, s),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
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

/// 一个"标签 + 值"的小单元。
class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
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
            color: c.textPrimary,
          ),
        ),
      ],
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
