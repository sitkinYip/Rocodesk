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
    required this.onOpenBuilder,
  });

  /// 打开一图流生成。由外壳提供（它负责 push 路由）。
  final VoidCallback onOpenGenerator;

  /// 打开阵容码解析。
  final VoidCallback onOpenParser;

  /// 打开自主配队。
  final VoidCallback onOpenBuilder;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        // 页面顶部只留一点点 —— 这一页就是"几个入口"，
        // 任何标题/说明/数据都是在入口前面挡一层。
        // 前两版在这里放了大标题 + 事实条，实测反而更难看：入口被推下去了。
        AppSpacing.lg,
        AppSpacing.page,
        AppSpacing.xxxl,
      ),
      children: [
        _MainToolCard(onTap: onOpenGenerator),
        const SizedBox(height: AppSpacing.md),
        _ToolCard(
          title: '阵容码解析',
          description: '粘贴一串阵容码，反查出这 6 只精灵、性格、个体资质、技能与血脉。'
              '解析结果同样可以逐项手改，改完重新生成码。',
          icon: Icons.qr_code_2_outlined,
          onTap: onOpenParser,
        ),
        const SizedBox(height: AppSpacing.md),
        // 自主配队：不依赖任何输入，所以放在两个"要输入"的功能后面。
        // 它和识别/解析共用同一套编辑界面（`ResultView`），
        // 所以三条路径出来的队伍长得一样、改法也一样。
        _ToolCard(
          title: '自主配队',
          description: '不用截图、不用码，直接从图鉴里选 6 只，'
              '逐只配性格、个体资质、血脉与技能，出阵容码和助手指令。',
          icon: Icons.tune_outlined,
          onTap: onOpenBuilder,
          tags: const [
            ('623 只里搜', Icons.search),
            ('能学什么就选什么', Icons.rule),
            ('改一项码就变', Icons.refresh),
          ],
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
    this.requirement,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  /// 卡片底部的小标签（说明它有什么能力）。
  final List<(String, IconData)> tags;

  /// 主功能：更高、带强调色描边、更大的图标与标题。
  final bool emphasis;

  /// 联网/依赖说明。比能力标签更"硬"的一条边界，所以单独一行、
  /// 配一个锁形小图标 —— 混进能力标签里会读不出"这是限制"。
  final String? requirement;

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
                    if (requirement != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(Icons.key_outlined,
                                size: 12, color: c.textSecondary),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              requirement!,
                              style: TextStyle(
                                fontSize: AppType.sCaption2,
                                color: c.textSecondary,
                                height: 1.4,
                              ),
                            ),
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
        ('结果可逐项调整', Icons.tune_outlined),
      ],
      // ⚠️ 这里原来写的是「离线可用」，**是错的**。
      //
      // 识别那一步要调用视觉模型 API（VlmClient.analyzeImage，需要在设置里
      // 填 baseUrl + apiKey），断网用不了。写「离线可用」会让用户以为
      // 飞行模式下也能识别 —— 那是误导，而且首页最显眼的入口恰恰要联网。
      //
      // 单独一行而不是塞进标签：它是**限制**不是能力，混在一起读不出来。
      requirement: '识别需要联网并填 API Key；识别之后的改配、出码、'
          '助手描述都是本地算，不用联网',
    );
  }
}
