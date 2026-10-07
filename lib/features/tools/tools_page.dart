/// 「工具」页：功能入口的容器。
///
/// ## 为什么不把功能做成 tab
///
/// 原来「生成」独占一个 tab，但工具清单会越来越长（克制矩阵、性格对照、
/// 技能筛选、图鉴……），全做成 tab 会放不下。
/// 所以 **tab 只留给分区，功能是分区里的卡片**：加功能只是卡片变多，
/// 导航结构不变。
///
/// ## 两条原则
///
/// 1. **不列还没做的假功能可点**。计划中的项明确标注「计划中」并说明它
///    需要什么，不做成能点但点进去是空的。
/// 2. **每张卡片给出"你能得到什么"**，而不是只说功能名。
library;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/common.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({
    super.key,
    required this.onOpenGenerator,
    required this.onOpenParser,
  });

  /// 打开一图流生成。由外壳提供（它负责 push 路由）。
  final VoidCallback onOpenGenerator;

  /// 打开阵容码解析。
  final VoidCallback onOpenParser;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        AppSpacing.xxxl,
      ),
      children: [
        const _ToolsHeader(),
        const SizedBox(height: AppSpacing.xl),

        const SectionHeader(title: '可用', subtitle: '点进去就能用'),
        _MainToolCard(onTap: onOpenGenerator),
        const SizedBox(height: AppSpacing.md),
        _ToolCard(
          title: '阵容码解析',
          description: '粘贴一串阵容码，反查出这 6 只精灵、性格、个体资质、技能与血脉。'
              '解析结果同样可以逐项手改，改完重新生成码。',
          icon: Icons.qr_code_2_outlined,
          onTap: onOpenParser,
        ),
        const SizedBox(height: AppSpacing.xl),

        const SectionHeader(
          title: '计划中',
          subtitle: '还没实现。列出来是为了让你知道规划，不是在假装已经有了',
        ),
        AppGroup(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _planned('属性克制查询',
                  '18×18 克制矩阵本地就有数据，直接用，不需要联网'),
              const Divider(height: 1),
              _planned('性格与个体资质对照', '30 个性格的六维修正，可用本地知识库直接算'),
              const Divider(height: 1),
              _planned('技能查询与筛选',
                  '584 个技能，按属性 / 威力 / 类别筛选，数据已就绪'),
              const Divider(height: 1),
              _planned('精灵图鉴',
                  '621 只精灵的六维、特性、可学技能、进化链'),
              const Divider(height: 1),
              _planned('伤害估算器',
                  '需要先确认官方伤害公式；目前没有可靠来源，所以暂不做'),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _planned(String title, String note) {
    return Builder(
      builder: (context) {
        final c = context.colors;
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.bgGrouped,
                  borderRadius: AppRadii.thumbR,
                ),
                child: Icon(Icons.schedule_outlined,
                    size: 18, color: c.textTertiary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: AppType.sCallout,
                        color: c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      note,
                      style: TextStyle(
                        fontSize: AppType.sCaption,
                        color: c.textTertiary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 工具页头部。
///
/// ## 为什么这么改
///
/// 原来只有「工具 / 配队相关的一站式工具」两行，问题有三个：
///
///   1. **层级塌陷** —— 34px 的标题下面直接就是 15px 的卡片标题，中间空着，
///      读起来像两个不相干的元素叠在一起
///   2. **读完不知道"能干什么"** —— 副标题是元信息（"一站式工具"），
///      没有回答新用户最关心的问题
///   3. **没有落点** —— 页面从纯文字开始，视线无处安放
///
/// 所以这里建立**三级层次**，并用一行真实数据把"这东西有多能打"讲清楚：
///
///   一级  工具            34px 粗体，唯一的视觉锚点
///   二级  一句话说清定位     15px 次要色
///   三级  623 只 · 579 技能 · 离线可用   11px 三级色，数字用等宽
///
/// ## 为什么用"数据规模"而不是口号
///
/// 「离线可用」是本项目**唯一真正区别于同类工具**的点（数据全内置、不联网），
/// 但空说一句"离线可用"没人会信。配上真实体量（623 只精灵 / 579 个技能）
/// 才有说服力 —— 而且这两个数字是从数据表里取的，不是文案。
///
/// 将来数据更新导致数字变化时，这里会跟着变（见 [kPetCount] / [kSkillCount]）。
class _ToolsHeader extends StatelessWidget {
  const _ToolsHeader();

  /// 数据体量。**从数据表实际条目数来**，不要手写：
  /// tests/asset_naming_test.dart 会核对图标索引，数字对不上会被发现。
  static const int kPetCount = 623;
  static const int kSkillCount = 579;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('工具', style: context.texts.displaySmall),
        // 间距阶梯刻意做成 12 / 16：
        // 标题与副标题关系最近，副标题与事实行稍远 —— 先读"是什么"，
        // 再读"有多大"。之前是 8 / 12，三段挤成一坨，没有呼吸。
        const SizedBox(height: AppSpacing.md),
        Text(
          '截图直接出阵容码，粘贴码反查出全队配置',
          style: TextStyle(
            fontSize: AppType.sSubhead,
            color: c.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // 三级：事实行。用 · 分隔而不是三个卡片 ——
        // 它是"定性说明"不是"可点的指标"，做成卡片会误导成入口。
        //
        // 用 Wrap 而不是 Row：三段中文放在 320px（iPhone SE 一代）上
        // 实测溢出 19px，换成 Wrap 让它自己折行。
        Wrap(
          spacing: 0,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Facet(value: '$kPetCount', unit: '只精灵'),
            _FacetDot(c: c),
            _Facet(value: '$kSkillCount', unit: '个技能'),
            _FacetDot(c: c),
            _Facet(value: '离线', unit: '不联网也能用'),
          ],
        ),
      ],
    );
  }
}

/// 事实行里的一个数字 + 单位。数字用等宽，扫描时更容易对齐。
///
/// ⚠️ 单位与分隔点**必须用 textSecondary，不能用 textTertiary**。
/// 实测（`tools/check_contrast.py`）：亮色模式下 textTertiary 在 11px 上
/// 只有 3.26:1，低于 WCAG AA 的 4.5:1（暗色模式 6.44:1 达标）。
/// 小字用 textSecondary 是 5.07:1，两个模式都过。
class _Facet extends StatelessWidget {
  const _Facet({required this.value, required this.unit});

  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          // 17px 而不是 13px：这行是**证据**（"它到底装了多少东西"），
          // 压成注释体量的细字就变成了纯装饰，说服力全丢。
          style: TextStyle(
            fontFamilyFallback: AppType.monoFallback,
            fontSize: AppType.sHeadline,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
            height: 1.1,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          unit,
          style: TextStyle(
            fontSize: AppType.sCaption,
            color: c.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _FacetDot extends StatelessWidget {
  const _FacetDot({required this.c});
  final AppColors c;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        // 同 _Facet：小字用 textSecondary 才过对比度
        child: Text('·',
            style: TextStyle(fontSize: AppType.sCaption, color: c.textSecondary)),
      );
}

/// 工具卡：一个可用功能的入口。
///
/// ## 为什么现在有 [emphasis] 这个变体
///
/// 原来所有卡片视觉权重一致，理由是"用户不需要判断哪个更重要"。
/// 但实测这不成立：**一图流生成的能力明显强于阵容码解析**
/// （识别 + 纠错 + 全字段编辑 + 出码，而解析只是反查）。
/// 两张长得一模一样的卡，反而让新用户不知道从哪开始。
///
/// 现在主功能用 [emphasis]：更高的卡片、强调色描边、更大的图标与标题。
/// **只用来表达真实的功能分量差，不是为了好看** —— 所以只允许一个工具用它。
class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
    this.tags = const [],
    this.emphasis = false,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  /// 卡片底部的小标签（说明它有什么能力）。
  final List<(String, IconData)> tags;

  /// 主功能：更高、带强调色描边、更大的图标与标题。
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pad = emphasis ? AppSpacing.lg + 2 : AppSpacing.lg;
    final iconBox = emphasis ? 52.0 : 46.0;

    return Material(
      color: emphasis ? c.surfaceElevated : c.surface,
      borderRadius: AppRadii.cardR,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.cardR,
        child: Container(
          padding: EdgeInsets.all(pad),
          decoration: BoxDecoration(
            borderRadius: AppRadii.cardR,
            border: Border.all(
              color: emphasis
                  ? c.accent.withValues(alpha: 0.35)
                  : c.separator,
              width: emphasis ? 1.5 : 1,
            ),
            // 阴影只给主卡：层级靠它一眼区分，二级卡纯描边即可
            boxShadow: emphasis ? AppShadows.card(c) : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: iconBox,
                height: iconBox,
                decoration: BoxDecoration(
                  color: emphasis ? c.accent : c.accentSubtle,
                  borderRadius: AppRadii.inputR,
                ),
                child: Icon(
                  icon,
                  size: emphasis ? 28 : 24,
                  color: emphasis ? c.onAccent : c.accent,
                ),
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
                            title,
                            style: emphasis
                                ? context.texts.titleMedium
                                : context.texts.titleSmall,
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            size: 20, color: c.textTertiary),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: emphasis
                            ? AppType.sFootnote
                            : AppType.sCaption,
                        color: c.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (final (label, tagIcon) in tags)
                            SemanticChip(
                              label: label,
                              color: c.accent,
                              icon: tagIcon,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一图流生成的卡片。只是 [_ToolCard] 的一个具体实例。
class _MainToolCard extends StatelessWidget {
  const _MainToolCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ToolCard(
      title: '一图流生成阵容码',
      // 主卡描述压短：它是"看一眼就点"的入口，不是需求文档。
      // 能力细节交给下面的标签行，扫读比读长句快。
      description: '上传阵容截图，自动识别全队配置并生成可直接导入游戏的阵容码。',
      icon: Icons.auto_awesome,
      emphasis: true,
      onTap: onTap,
      tags: const [
        ('读系别与血脉图标', Icons.image_outlined),
        ('识别错了可手改', Icons.edit_outlined),
        ('离线可用', Icons.cloud_off_outlined),
      ],
    );
  }
}
