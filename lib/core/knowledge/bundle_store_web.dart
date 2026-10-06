/// Web 端的知识库缓存：内存 + localStorage。
///
/// 浏览器没有可写文件系统。知识库 JSON 有几 MB，**超过 localStorage 的
/// 典型 5 MB 配额**，所以策略是：
///   * 优先用内存缓存（本次会话有效）；
///   * 尝试写 localStorage，失败（配额满 / 隐私模式）就静默忽略；
///   * 读不到就回退到内置资产 —— 这正是设计里"远程永远不能把 App 弄坏"的体现。
///
/// 结果：Web 端每次刷新可能重新拉一次远程数据，但**功能始终可用**。
library;

import 'dart:convert';

// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart' as web;

import 'bundle_store.dart';

Future<BundleStore> openBundleStore() async => WebBundleStore();

class WebBundleStore implements BundleStore {
  final Map<String, String> _memory = {};
  static const _prefix = 'roco_kb_';

  @override
  String get location => '浏览器 localStorage（可能因配额不足而失效）';

  @override
  Future<String?> read(String name) async {
    final cached = _memory[name];
    if (cached != null) return cached;
    try {
      final v = web.window.localStorage.getItem('$_prefix$name');
      if (v != null && v.isNotEmpty) {
        _memory[name] = v;
        return v;
      }
    } catch (_) {
      // 隐私模式或存储被禁用
    }
    return null;
  }

  @override
  Future<void> write(String name, String content) async {
    _memory[name] = content;
    try {
      web.window.localStorage.setItem('$_prefix$name', content);
    } catch (_) {
      // 配额满是最常见的情况（知识库通常 5 MB 上下）。
      // 内存缓存已经写入，本次会话够用；下次刷新会重新拉取。
    }
  }

  @override
  Future<void> clear() async {
    final keys = _memory.keys.toList();
    _memory.clear();
    for (final k in keys) {
      try {
        web.window.localStorage.removeItem('$_prefix$k');
      } catch (_) {
        // 忽略
      }
    }
  }

  /// 供调试：当前缓存了哪些文件。
  String describe() => jsonEncode(_memory.keys.toList());
}
