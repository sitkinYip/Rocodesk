/// 可搜索的单选列表抽屉。
///
/// 为什么单独抽出来：换精灵要在**542 条**里挑，换技能要在**579 条**里挑，
/// 静态的 Wrap 候选列表（纠错面板用的那种）在这两个场景下不可用 ——
/// 用户没法从 542 个格子里找到想要的那只。
///
/// 所以这里给的是「搜索框 + 滚动列表」，和纠错面板的分工是：
///   * 纠错面板：候选少（这只精灵能学的几十个），目标是"点一下就好"
///   * 这个抽屉：候选多（全部精灵/技能），目标是"搜出来再点"
library;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/common.dart';

/// 抽屉里的一个候选项。
class PickerItem {
  const PickerItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.iconPath,
    this.trailing,
  });

  /// 选中后回传的值（精灵码 / 技能名 / 性格名…）。
  final String value;

  /// 主文字。
  final String label;

  /// 次要说明（如系别、可学技能数）。
  final String? subtitle;

  /// 头像 / 图标。
  final String? iconPath;

  /// 右侧附加内容（如系别标签）。
  final Widget? trailing;
}

/// 打开可搜索的单选抽屉，返回选中的值；取消返回 null。
Future<String?> showSearchPicker(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<PickerItem> items,
  String? selected,
  String searchHint = '搜索',
  /// 上限：候选上万时不至于卡住（精灵 542 / 技能 579 都远低于此）。
  int maxResults = 200,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _SearchPickerSheet(
      title: title,
      subtitle: subtitle,
      items: items,
      selected: selected,
      searchHint: searchHint,
      maxResults: maxResults,
    ),
  );
}

class _SearchPickerSheet extends StatefulWidget {
  const _SearchPickerSheet({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.selected,
    required this.searchHint,
    required this.maxResults,
  });

  final String title;
  final String? subtitle;
  final List<PickerItem> items;
  final String? selected;
  final String searchHint;
  final int maxResults;

  @override
  State<_SearchPickerSheet> createState() => _SearchPickerSheetState();
}

class _SearchPickerSheetState extends State<_SearchPickerSheet> {
  final TextEditingController _q = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<PickerItem> get _filtered {
    final f = _filter.trim();
    if (f.isEmpty) return widget.items.take(widget.maxResults).toList();
    // 简单子串匹配：中文没有词形变化，够用；按"越靠前越相关"排一下
    final hits = widget.items
        .where((it) => it.label.contains(f) || (it.subtitle?.contains(f) ?? false))
        .toList();
    hits.sort((a, b) => a.label.indexOf(f).compareTo(b.label.indexOf(f)));
    return hits.take(widget.maxResults).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = _filtered;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        // 键盘弹出时把内容顶上去，否则搜索框被遮住
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: ConstrainedBox(
        // 必须给上限：抽屉内容是不定长的列表，不限制会直接顶出屏幕
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            if (widget.subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.subtitle!,
                style: TextStyle(
                  fontSize: AppType.sCaption,
                  color: c.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),

            TextField(
              controller: _q,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _filter.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _q.clear();
                          setState(() => _filter = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: AppSpacing.sm),

            // 结果计数：让用户知道"搜出来多少"，而不是盯着一个长列表
            Text(
              _filter.isEmpty
                  ? '共 ${widget.items.length} 个，显示前 ${list.length} 个'
                  : '匹配 ${list.length} 个',
              style: TextStyle(fontSize: AppType.sCaption, color: c.textTertiary),
            ),
            const SizedBox(height: AppSpacing.xs),

            Flexible(
              child: list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xxl),
                      child: Center(
                        child: Text(
                          '没找到「$_filter」',
                          style: TextStyle(
                            fontSize: AppType.sCallout,
                            color: c.textTertiary,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final it = list[i];
                        final on = it.value == widget.selected;
                        return InkWell(
                          onTap: () => Navigator.pop(context, it.value),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm,
                              horizontal: AppSpacing.xs,
                            ),
                            child: Row(
                              children: [
                                if (it.iconPath != null) ...[
                                  RefIcon(
                                    assetPath: it.iconPath,
                                    size: 34,
                                    fallbackText: it.label,
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        it.label,
                                        style: TextStyle(
                                          fontSize: AppType.sCallout,
                                          fontWeight: on
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: on ? c.accent : c.textPrimary,
                                        ),
                                      ),
                                      if (it.subtitle != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          it.subtitle!,
                                          style: TextStyle(
                                            fontSize: AppType.sCaption,
                                            color: c.textTertiary,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (it.trailing != null) it.trailing!,
                                if (on) ...[
                                  const SizedBox(width: AppSpacing.xs),
                                  Icon(Icons.check,
                                      size: 18, color: c.accent),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
