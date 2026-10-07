/// 应用外壳：响应式导航。
///
/// Apple HIG 的 iOS 用底部 Tab Bar，iPadOS / macOS 用侧边栏。
/// 所以这里**同一个页面代码**，按可用宽度切换外壳：
///   * 窄屏（< 720）：底部 NavigationBar，符合手机拇指可达
///   * 宽屏（>= 720）：左侧 NavigationRail，符合桌面鼠标操作
///
/// ## 为什么只有两个 tab
///
/// 原来有「生成 / 工具 / 设置」三个，其中「生成」tab 里只有一个功能。
/// 但工具清单会越来越长（克制矩阵、性格对照、技能筛选、图鉴……），
/// 全塞进 tab 会放不下，而且每加一个功能就多一个 tab 是不能持续的。
///
/// 所以：**tab 只留给"分区"，功能作为卡片放进分区里**。
/// 一图流生成是「工具」里的一个功能卡片，点进去用 push 打开 ——
/// 这样功能再多也只是卡片变多，导航结构不变。
library;

import 'package:flutter/material.dart';

import '../core/bloodline_ranks.dart';
import '../core/icon_assets.dart';
import '../theme/tokens.dart';
import '../features/builder/builder_page.dart';
import '../features/generator/generator_page.dart';
import '../features/parser/parse_page.dart';
import '../features/settings/settings_page.dart';
import '../features/tools/tools_page.dart';
import 'settings.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.store});

  final SettingsStore store;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  /// 纠错面板用的参考图标 + 血脉候选排序。
  ///
  /// 提到外壳这一层加载**只做一次**，两个功能页（识别 / 解析）共用。
  /// 放在各自页面里会让每次进入都重新读一遍索引。
  IconAssets _icons = IconAssets.empty();
  BloodlineRanks _bloodlineRanks = BloodlineRanks.empty();

  static const _destinations = <_Destination>[
    _Destination('工具', Icons.grid_view_outlined, Icons.grid_view_rounded),
    _Destination('设置', Icons.settings_outlined, Icons.settings),
  ];

  @override
  void initState() {
    super.initState();
    _loadSharedAssets();
  }

  Future<void> _loadSharedAssets() async {
    try {
      final icons = await IconAssets.load();
      final ranks = await BloodlineRanks.load();
      if (!mounted) return;
      setState(() {
        _icons = icons;
        _bloodlineRanks = ranks;
      });
    } catch (_) {
      // 图标是可选增强：加载失败就退化成纯文字，不影响功能
      if (!mounted) return;
      setState(() {
        _icons = IconAssets.empty();
        _bloodlineRanks = BloodlineRanks.empty();
      });
    }
  }

  /// 打开一图流生成。
  ///
  /// 用 push 而不是内嵌在 tab 里：它是一个**有明确开始与结束的任务**
  /// （选图 → 识别 → 拿码 → 返回），不是常驻分区。
  /// 而且这样返回时自动回到工具页原来的滚动位置。
  void _openGenerator() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GeneratorPage(store: widget.store),
      ),
    );
  }

  /// 打开阵容码解析。
  void _openParser() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ParsePage(
          icons: _icons,
          bloodlineRanks: _bloodlineRanks,
        ),
      ),
    );
  }

  /// 打开自主配队。
  ///
  /// 和另外两个一样是 push：它是一个**有明确起止的任务**
  /// （选 6 只 → 调技能血脉 → 拿码 → 返回），不是常驻分区。
  void _openBuilder() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BuilderPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final pages = <Widget>[
      ToolsPage(
        onOpenGenerator: _openGenerator,
        onOpenParser: _openParser,
        onOpenBuilder: _openBuilder,
      ),
      SettingsPage(store: widget.store),
    ];

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _Sidebar(
              index: _index,
              destinations: _destinations,
              onSelect: (i) => setState(() => _index = i),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
                  child: IndexedStack(index: _index, children: pages),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// 桌面端侧边栏。宽度固定 88，图标 + 小字，和 iPadOS 侧边栏的比例接近。
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.index,
    required this.destinations,
    required this.onSelect,
  });

  final int index;
  final List<_Destination> destinations;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 88,
      color: c.bgBase,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.lg),
            for (var i = 0; i < destinations.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: _SidebarItem(
                  destination: destinations[i],
                  selected: i == index,
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = widget.selected ? c.accent : c.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.instant,
          curve: AppMotion.standard,
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: widget.selected
                ? c.accentSubtle
                : (_hover ? c.surface : Colors.transparent),
            borderRadius: AppRadii.inputR,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.selected
                    ? widget.destination.selectedIcon
                    : widget.destination.icon,
                size: 24,
                color: fg,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.destination.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      widget.selected ? FontWeight.w600 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
