/// 知识库文件的存放位置抽象。
///
/// 为什么需要抽象：各端可写目录不一样，而且**Web 端没有文件系统**。
///   * 桌面 / 移动：用 `path_provider` 拿应用支持目录
///   * Web：没有真实文件系统，退化成"只在内存 + localStorage 里缓存"
///
/// 用条件导入在编译期选实现，调用方只看到 [BundleStore] 这一个接口。
library;

import 'bundle_store_io.dart'
    if (dart.library.js_interop) 'bundle_store_web.dart' as impl;

/// 一个可读写的键值存储，专用于知识库 JSON 文件。
abstract class BundleStore {
  /// 读一个缓存文件；不存在返回 null。
  Future<String?> read(String name);

  /// 写一个缓存文件。
  Future<void> write(String name, String content);

  /// 清空所有缓存（回到内置版本）。
  Future<void> clear();

  /// 缓存目录的可读描述，用于在设置页展示"数据存在哪"。
  String get location;
}

/// 当前平台的实现。
Future<BundleStore> openBundleStore() => impl.openBundleStore();
