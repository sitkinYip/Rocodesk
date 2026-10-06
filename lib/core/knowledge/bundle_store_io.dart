/// 桌面 / 移动端的知识库缓存：真实文件系统。
///
/// 用 `path_provider` 的应用支持目录，例如
///   Windows: `%APPDATA%\com.rocodesk\app\`（由应用的包标识决定）
///   Android: `/data/data/com.rocodesk.app/files/`
/// 不用 `shared_preferences`：知识库是几 MB 的 JSON，
/// 放进偏好存储会拖慢启动、也可能触发平台大小限制。
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'bundle_store.dart';

Future<BundleStore> openBundleStore() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}${Platform.pathSeparator}kb');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return FileBundleStore(dir);
}

class FileBundleStore implements BundleStore {
  FileBundleStore(this.dir);

  final Directory dir;

  @override
  String get location => dir.path;

  File _f(String name) => File('${dir.path}${Platform.pathSeparator}$name');

  @override
  Future<String?> read(String name) async {
    final f = _f(name);
    if (!f.existsSync()) return null;
    try {
      return await f.readAsString();
    } catch (_) {
      // 文件损坏（比如上次写到一半断电）-> 当作不存在，回退内置版本
      return null;
    }
  }

  @override
  Future<void> write(String name, String content) async {
    // 先写临时文件再原子重命名：避免写到一半崩溃导致缓存永久损坏。
    final tmp = File('${_f(name).path}.tmp');
    await tmp.writeAsString(content, flush: true);
    if (_f(name).existsSync()) await _f(name).delete();
    await tmp.rename(_f(name).path);
  }

  @override
  Future<void> clear() async {
    if (!dir.existsSync()) return;
    for (final e in dir.listSync()) {
      try {
        e.deleteSync(recursive: true);
      } catch (_) {
        // 单个文件删不掉不影响整体
      }
    }
  }
}
