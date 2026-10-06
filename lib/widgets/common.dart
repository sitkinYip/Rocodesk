/// 跨页复用的基础组件。
///
/// 原则：**能用留白和分隔线解决的就不要用卡片**。
/// Apple 风格靠层级（字号/颜色/间距）表达结构，而不是靠给每样东西套盒子。
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// 分组标题（大标题 + 可选说明）。用于页面内的章节分隔。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        right: AppSpacing.xs,
        bottom: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.texts.titleSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: AppType.sFootnote,
                      color: c.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 分组容器。用极淡的边框而非重阴影表达层级。
class AppGroup extends StatelessWidget {
  const AppGroup({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: c.separator),
      ),
      child: child,
    );
  }
}

/// 可点击的设置行（iOS 的 inset grouped list 风格）。
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.texts.bodyMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: AppType.sFootnote,
                      color: c.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ],
          if (onTap != null)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Icon(Icons.chevron_right,
                  size: 20, color: c.textTertiary),
            ),
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.cardR,
      child: row,
    );
  }
}

/// 属性 / 血脉小标签：淡底 + 同色文字。
/// 这是**唯一**允许出现属性色的地方，且面积很小。
class SemanticChip extends StatelessWidget {
  const SemanticChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.imagePath,
    this.imageSize = 14,
  });

  final String label;
  final Color color;

  /// 图标字体。与 [imagePath] 二选一，[imagePath] 优先。
  final IconData? icon;

  /// 真实图片（如属性图标）。比色点信息量大 —— 一眼能认出是哪个系。
  final String? imagePath;
  final double imageSize;

  @override
  Widget build(BuildContext context) {
    final img = imagePath;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: AppRadii.pillR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (img != null) ...[
            RefIcon(assetPath: img, size: imageSize, fallbackText: label),
            const SizedBox(width: 5),
          ] else if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: AppType.sCaption,
              fontWeight: FontWeight.w600,
              color: color,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// 参考图标（血脉 / 技能）。纠错面板里让用户**看图选**。
///
/// 图标是可选资源：取不到就用首字兜底，不影响功能。
///
/// 为什么兜底要显示首字而不是空框：24 条血脉里有 3 条（巨兽 / 黑魔法 / 异核）
/// 官方 CDN 上根本没有图标。画个灰框会让人以为是图坏了，显示首字则看起来
/// 是有意的设计（而且它确实还能帮用户定位）。
class RefIcon extends StatelessWidget {
  const RefIcon({
    super.key,
    required this.assetPath,
    this.size = 32,
    this.fallbackText,
  });

  final String? assetPath;
  final double size;

  /// 没有图标时显示的字（通常是名字首字）。
  final String? fallbackText;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final path = assetPath;

    Widget fallback() {
      final t = fallbackText;
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.bgGrouped,
          borderRadius: BorderRadius.circular(size * 0.22),
        ),
        child: t == null || t.isEmpty
            ? null
            : Text(
                t.characters.first,
                style: TextStyle(
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.w600,
                  color: c.textTertiary,
                ),
              ),
      );
    }

    if (path == null) return fallback();
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        path,
        width: size,
        height: size,
        fit: BoxFit.contain,
        // 缺图标时不要报错刷屏，安静地退化成首字
        errorBuilder: (context, error, stack) => fallback(),
      ),
    );
  }
}

/// 空状态。要求：**构图完整 + 明确告知如何填充**，不是一句"暂无数据"。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: c.accentSubtle,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: c.accent),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: context.texts.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                description,
                style: TextStyle(
                  fontSize: AppType.sSubhead,
                  color: c.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 错误提示条（页内，不是 toast）。用于需要用户读到并处理的问题。
class InlineNotice extends StatelessWidget {
  const InlineNotice({
    super.key,
    required this.message,
    this.severity = NoticeSeverity.info,
    this.action,
  });

  final String message;
  final NoticeSeverity severity;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (color, icon) = switch (severity) {
      NoticeSeverity.info => (c.info, Icons.info_outline),
      NoticeSeverity.warning => (c.warning, Icons.warning_amber_rounded),
      NoticeSeverity.error => (c.danger, Icons.error_outline),
      NoticeSeverity.success => (c.success, Icons.check_circle_outline),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadii.inputR,
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: AppType.sFootnote,
                color: c.textPrimary,
                height: 1.45,
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(width: AppSpacing.sm), action!],
        ],
      ),
    );
  }
}

enum NoticeSeverity { info, warning, error, success }
