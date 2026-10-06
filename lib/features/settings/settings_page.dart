/// 设置页：主题模式、模型服务商、API Key、模型名。
///
/// 纯前端架构下这些是**用户自己的凭据**，所以要写清楚存哪、有什么风险。
library;

import 'package:flutter/material.dart';

import '../../app/settings.dart';
import '../../core/knowledge/knowledge_base.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/common.dart';

/// 清除已下载的知识库缓存，回到内置版本。
Future<void> _confirmResetKb(BuildContext context, SettingsStore store) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('清除已下载的数据？'),
      content: const Text(
        '会删掉本机缓存的资料库，改用应用内置的那份。\n\n'
        '应用内置数据永远可用，所以这一步是安全的。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('清除'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await KnowledgeBase().resetToBundled();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清除。重启应用后使用内置数据。')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('清除失败：$e')),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.store});

  final SettingsStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.lg,
          AppSpacing.page,
          AppSpacing.xxxl,
        ),
        children: [
          Text('设置', style: context.texts.displaySmall),
          const SizedBox(height: AppSpacing.xl),

          // ---------------- 外观 ----------------
          const SectionHeader(
            title: '外观',
            subtitle: '深色模式跟随系统，也可以强制指定',
          ),
          AppGroup(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _ThemeModePicker(store: store),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---------------- 模型服务 ----------------
          const SectionHeader(
            title: '模型服务',
            subtitle: '识别截图需要能看图的模型。密钥只存在本机，不经任何服务器',
          ),
          AppGroup(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Field(
                  label: '服务商',
                  child: _ProviderPicker(store: store),
                ),
                const SizedBox(height: AppSpacing.lg),
                _Field(
                  label: 'API Key',
                  helper: '在服务商控制台创建。留空则无法识别图片',
                  child: _ApiKeyField(store: store),
                ),
                const SizedBox(height: AppSpacing.lg),
                _Field(
                  label: '模型',
                  helper: '留空用服务商默认：${store.provider.defaultModel}',
                  child: _TextSetting(
                    value: store.settings.modelOverride,
                    hint: store.provider.defaultModel,
                    onSubmitted: store.setModelOverride,
                  ),
                ),
                if (store.provider == ModelProvider.custom) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _Field(
                    label: '接口地址',
                    helper: 'OpenAI 兼容的 /v1 地址，例如 https://example.com/v1',
                    child: _TextSetting(
                      value: store.settings.baseUrlOverride,
                      hint: 'https://...',
                      onSubmitted: store.setBaseUrlOverride,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (!store.isReady)
                  const InlineNotice(
                    message: '还没填 API Key，暂时无法识别图片。填好之后回到「生成」页选图即可。',
                    severity: NoticeSeverity.info,
                  )
                else
                  InlineNotice(
                    message: '已就绪：${store.provider.label} · ${store.settings.effectiveModel}',
                    severity: NoticeSeverity.success,
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---------------- 知识库 ----------------
          const SectionHeader(
            title: '资料库',
            subtitle: '精灵、技能、性格数据。内置一份，联网时可自动更新',
          ),
          AppGroup(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsRow(
                  title: '启动时检查更新',
                  subtitle: '关闭后只用本机数据，不产生任何网络请求',
                  trailing: Switch(
                    value: store.settings.checkKnowledgeUpdates,
                    onChanged: store.setCheckKnowledgeUpdates,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _Field(
                  label: '更新地址',
                  helper: '留空表示不检查。填一个静态 manifest.json 的地址即可，'
                      '不需要自建服务器',
                  child: _TextSetting(
                    value: store.settings.knowledgeUrl,
                    hint: 'https://.../manifest.json',
                    onSubmitted: store.setKnowledgeUrl,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                InlineNotice(
                  message: store.settings.canCheckKnowledge
                      ? '已开启：启动时会在后台检查，成功也只提示"重启后生效"，'
                          '不会打断你当前的操作。'
                      : '当前不会检查更新，使用打包在应用里的数据。功能完全可用。',
                  severity: store.settings.canCheckKnowledge
                      ? NoticeSeverity.info
                      : NoticeSeverity.success,
                ),
                const SizedBox(height: AppSpacing.lg),
                // 恢复途径：万一某次更新引入了坏数据，用户能自己回到内置版本，
                // 不需要重装应用。这是"远程永远不能把 App 弄坏"原则的用户侧兜底。
                SettingsRow(
                  title: '清除已下载的数据',
                  subtitle: '回到应用内置版本。更新出问题时用它恢复',
                  leading: Icon(Icons.restore_outlined,
                      size: 20, color: context.colors.textSecondary),
                  onTap: () => _confirmResetKb(context, store),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---------------- 行为 ----------------
          const SectionHeader(title: '行为'),
          AppGroup(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SettingsRow(
                  title: '选图后自动识别',
                  subtitle: '关闭后需要手动点「开始识别」',
                  trailing: Switch(
                    value: store.settings.autoAnalyze,
                    onChanged: store.setAutoAnalyze,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---------------- 安全说明 ----------------
          const SectionHeader(title: '关于密钥安全'),
          const AppGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Bullet('密钥保存在本设备的本地存储里，不会上传到任何服务器。'),
                _Bullet('它没有加密，同一台设备上的其他程序理论上可以读到。'),
                _Bullet('不要在公用电脑或网吧设备上填写密钥。'),
                _Bullet('建议单独创建一个密钥专供本应用，随时可以在服务商后台吊销。'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---------------- 危险操作 ----------------
          AppGroup(
            padding: EdgeInsets.zero,
            child: SettingsRow(
              title: '清除本机保存的密钥',
              subtitle: store.settings.hasApiKey ? '当前已保存一个密钥' : '当前没有保存密钥',
              leading: Icon(Icons.key_off_outlined,
                  size: 20, color: context.colors.danger),
              onTap: store.settings.hasApiKey
                  ? () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('清除密钥？'),
                          content: const Text('清除后需要重新填写才能识别图片。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('清除'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) await store.clearApiKey();
                    }
                  : null,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          Center(
            child: Text(
              'Rocodesk · 洛克王国：世界配队工具',
              style: TextStyle(
                fontSize: AppType.sFootnote,
                color: context.colors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.helper});

  final String label;
  final Widget child;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    // 标签在上、帮助文字在下 —— 不用 placeholder 充当标签
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppType.sSubhead,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
        if (helper != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            helper!,
            style: TextStyle(
              fontSize: AppType.sCaption,
              color: context.colors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}

class _ThemeModePicker extends StatelessWidget {
  const _ThemeModePicker({required this.store});
  final SettingsStore store;

  @override
  Widget build(BuildContext context) {
    const options = <(ThemeMode, String, IconData)>[
      (ThemeMode.system, '跟随系统', Icons.brightness_auto_outlined),
      (ThemeMode.light, '浅色', Icons.light_mode_outlined),
      (ThemeMode.dark, '深色', Icons.dark_mode_outlined),
    ];
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          for (final (mode, label, icon) in options)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: mode == ThemeMode.dark ? 0 : AppSpacing.sm,
                ),
                child: _SegmentTile(
                  label: label,
                  icon: icon,
                  selected: store.settings.themeMode == mode,
                  onTap: () => store.setThemeMode(mode),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.inputR,
      child: AnimatedContainer(
        duration: AppMotion.instant,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? c.accentSubtle : Colors.transparent,
          borderRadius: AppRadii.inputR,
          border: Border.all(
            color: selected ? c.accent : c.separator,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: selected ? c.accent : c.textSecondary),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: TextStyle(
                fontSize: AppType.sCaption,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? c.accent : c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderPicker extends StatelessWidget {
  const _ProviderPicker({required this.store});
  final SettingsStore store;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadii.inputR,
        border: Border.all(color: c.separator),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ModelProvider>(
          value: store.provider,
          isExpanded: true,
          borderRadius: AppRadii.inputR,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          items: [
            for (final p in ModelProvider.values)
              DropdownMenuItem(value: p, child: Text(p.label)),
          ],
          onChanged: (p) {
            if (p != null) store.setProvider(p);
          },
        ),
      ),
    );
  }
}

class _ApiKeyField extends StatefulWidget {
  const _ApiKeyField({required this.store});
  final SettingsStore store;

  @override
  State<_ApiKeyField> createState() => _ApiKeyFieldState();
}

class _ApiKeyFieldState extends State<_ApiKeyField> {
  late final TextEditingController _c =
      TextEditingController(text: widget.store.apiKey);
  bool _obscure = true;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      obscureText: _obscure,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        hintText: 'sk-...',
        suffixIcon: IconButton(
          tooltip: _obscure ? '显示' : '隐藏',
          icon: Icon(
            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 20,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      onChanged: widget.store.setApiKey,
    );
  }
}

class _TextSetting extends StatefulWidget {
  const _TextSetting({
    required this.value,
    required this.hint,
    required this.onSubmitted,
  });

  final String value;
  final String hint;
  final ValueChanged<String> onSubmitted;

  @override
  State<_TextSetting> createState() => _TextSettingState();
}

class _TextSettingState extends State<_TextSetting> {
  late final TextEditingController _c =
      TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(hintText: widget.hint),
      onChanged: widget.onSubmitted,
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: c.textTertiary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppType.sFootnote,
                color: c.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
