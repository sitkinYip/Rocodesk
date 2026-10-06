/// 应用入口。
///
/// 启动顺序：先载入设置（决定主题模式），再构建 UI。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app_shell.dart';
import 'app/settings.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

/// 启动期如果出意外，至少让用户看到错误，而不是一片白。
///
/// 为什么要这个：白屏是最糟的失败方式 —— 用户不知道发生了什么，也没法反馈。
/// Flutter 默认会把未捕获异常打到控制台，但**页面上什么都不显示**。
/// 这里把它变成一个可读的界面。
void _installErrorSurface() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    previous?.call(details);
    // 开发时仍然完整打到控制台，便于排查
    if (kDebugMode) {
      FlutterError.presentError(details);
    }
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorSurface();

  try {
    final store = await SettingsStore.load();
    runApp(RocodeskApp(store: store));
  } catch (e, stack) {
    // 连设置都读不出来（例如本地存储被禁用）—— 用一个最小可用的内存设置启动，
    // 而不是让用户对着白屏。
    debugPrint('设置载入失败，改用内存设置: $e\n$stack');
    runApp(RocodeskApp(store: SettingsStore.inMemory()));
  }
}

class RocodeskApp extends StatelessWidget {
  const RocodeskApp({super.key, required this.store});

  final SettingsStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => MaterialApp(
        // 窗口/任务栏标题。应用内显示用的是「Rocodesk」，
        // 中文副标题由各页面自己组织，避免平台标题被截断。
        title: 'Rocodesk',
        debugShowCheckedModeBanner: false,
        themeMode: store.themeMode,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        // 兜底错误页：任何 build 期异常都会走这里，而不是白屏
        builder: (context, child) {
          ErrorWidget.builder = (details) => _StartupError(details: details);
          return child ?? const SizedBox.shrink();
        },
        home: AppShell(store: store),
      ),
    );
  }
}

/// 出问题时显示的界面。**要给出可操作信息**，不是一句"出错了"。
class _StartupError extends StatelessWidget {
  const _StartupError({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: c.bgGrouped,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '界面加载出错',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '这通常是应用数据没加载上导致的。\n'
                  '先在「设置」里点一次「清除已下载的数据」，再重启应用试试。\n'
                  '如果还不行，把这个界面截图反馈。',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  details.exceptionAsString(),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: c.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
