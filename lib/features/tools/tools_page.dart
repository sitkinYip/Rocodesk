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
  const ToolsPage({super.key, required this.onOpenGenerator});

  /// 打开一图流生成。由外壳提供（它负责 push 路由）。
  final VoidCallback onOpenGenerator;

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
        Text('工具', style: context.texts.displaySmall),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '配队相关的一站式工具',
          style: TextStyle(
            fontSize: AppType.sSubhead,
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        const SectionHeader(title: '可用', subtitle: '点进去就能用'),
        _MainToolCard(onTap: onOpenGenerator),
        const SizedBox(height: AppSpacing.md),
        AppGroup(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SettingsRow(
                title: '阵容码解析',
                subtitle: '粘贴阵容码反查是哪 6 只、什么性格与三围',
                leading: _toolIcon(Icons.qr_code_2_outlined),
                trailing: const _SoonChip(),
              ),
            ],
          ),
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

  static Widget _toolIcon(IconData icon) {
    return Builder(
      builder: (context) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: context.colors.bgGrouped,
          borderRadius: AppRadii.thumbR,
        ),
        child: Icon(icon, size: 18, color: context.colors.textTertiary),
      ),
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

/// 主工具卡：一图流生成。
///
/// 用大卡片而不是普通列表行 —— 它是当前**唯一完整可用**的功能，
/// 视觉权重应当和"计划中"的列表项明显不同，用户一眼知道该点这里。
class _MainToolCard extends StatelessWidget {
  const _MainToolCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      borderRadius: AppRadii.cardR,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.cardR,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: AppRadii.cardR,
            border: Border.all(color: c.separator),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: c.accentSubtle,
                  borderRadius: AppRadii.inputR,
                ),
                child: Icon(Icons.auto_awesome, size: 24, color: c.accent),
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
                            '一图流生成阵容码',
                            style: context.texts.titleSmall,
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            size: 20, color: c.textTertiary),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '上传阵容截图，自动识别精灵、性格、个体资质、技能与血脉，'
                      '生成可直接导入游戏的阵容码，以及给官方 AI 助手的描述。',
                      style: TextStyle(
                        fontSize: AppType.sCaption,
                        color: c.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: const [
                        SemanticChip(
                          label: '读系别与血脉图标',
                          color: Color(0xFF007AFF),
                          icon: Icons.image_outlined,
                        ),
                        SemanticChip(
                          label: '识别错了可手改',
                          color: Color(0xFF007AFF),
                          icon: Icons.edit_outlined,
                        ),
                        SemanticChip(
                          label: '离线可用',
                          color: Color(0xFF007AFF),
                          icon: Icons.cloud_off_outlined,
                        ),
                      ],
                    ),
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

/// 「未实现」标记。
class _SoonChip extends StatelessWidget {
  const _SoonChip();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.bgGrouped,
        borderRadius: AppRadii.pillR,
      ),
      child: Text(
        '计划中',
        style: TextStyle(
          fontSize: AppType.sCaption,
          color: c.textTertiary,
        ),
      ),
    );
  }
}
