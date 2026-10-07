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
/// ## 为什么是一行"事实条"而不是几个数字
///
/// 第一版这里只放了三段文字（标题 / 副标题 / 一行小数字），观感确实简陋：
/// 三段都是左对齐的纯文字，左半边有内容右半边全空，读起来像文档开头
/// 而不像一个产品页的开场。
///
/// 现在把"能打的地方"做成**等宽三栏的事实条**：每栏一个小标签 + 一个大值，
/// 栏间一条竖直细线分隔。它把整行铺满，有了结构感，而且**信息本身有用**。
///
/// ## ⚠️ 这里曾经写过「离线可用」，是错的
///
/// 一图流生成**必须联网**：它要调用视觉模型 API（`VlmClient.analyzeImage`，
/// 需要 baseUrl + apiKey）。把"离线可用"放在整页最显眼的位置是误导 ——
/// 首页第一个入口恰恰是唯一需要联网的功能。
///
/// 所以现在只说**真正在本地完成**的那部分：「解析 · 改配 · 出码」。
/// 这是实打实的：编码/解码、数据表、图标、纠错全在本地，
/// 断网也能粘贴码反查、把每一项改完、重新出码。
class _ToolsHeader extends StatelessWidget {
  const _ToolsHeader();

  /// 数据体量。**从数据表实际条目数来**，不要手写：
  /// `test/tools_page_test.dart` 会核对它和 pets.json / skills.json 一致。
  static const int kPetCount = 623;
  static const int kSkillCount = 579;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('工具', style: context.texts.displaySmall),
        // 间距阶梯 12 / 16：标题与副标题关系最近，副标题与事实条稍远 ——
        // 先读"是什么"，再读"有多大"。
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
        // 事实条：三栏等宽 + 竖线分隔。
        //
        // 为什么是"标签在上、值在下"而不是一行小字：值是给人看的重点
        // （623 只精灵是个卖点），压成注释体量的细字就变成了纯装饰。
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Fact(label: '收录精灵', value: '$kPetCount', unit: '只'),
            _FactDivider(c: c),
            _Fact(label: '收录技能', value: '$kSkillCount', unit: '个'),
            _FactDivider(c: c),
            // 标签与值都要短：这一栏是三栏里最长的，
            // 原来写「解析 · 改配 · 出码」+「本地完成」，在 390px 上就换行了。
            _Fact(label: '出码与改配', value: '本地', unit: '运行'),
          ],
        ),
      ],
    );
  }
}

/// 事实条里的一栏。
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, required this.unit});

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppType.sCaption2,
              color: c.textSecondary,
              height: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                // 22px 粗体：这一栏是页面最有说服力的信息，值得这个体量。
                style: TextStyle(
                  fontFamilyFallback: AppType.monoFallback,
                  fontSize: AppType.sTitle2,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  unit,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.sCaption,
                    color: c.textSecondary,
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

/// 事实栏之间的竖直细线。
class _FactDivider extends StatelessWidget {
  const _FactDivider({required this.c});
  final AppColors c;

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 34,
        // 边距用 sm(8) 而不是 md(12)：三栏 + 两条分隔线在 320px
        // （iPhone SE 一代）上，12 的话每栏只剩 70px，值会折行。
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        color: c.separator,
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
