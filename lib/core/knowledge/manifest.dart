/// 知识库版本清单（manifest）。
///
/// 设计目标：**离线可用 + 联网可更新 + 不依赖任何自建服务器**。
///
/// 工作方式：
///   1. App 打包一份内置知识库（`assets/data/*.json`）和它的 manifest。
///   2. 启动时读内置 manifest 拿到版本号，立刻可用（不联网）。
///   3. 后台（可选）请求一个**远程 manifest**（就是个静态 JSON 文件，
///      放在任意静态托管上即可，不需要后端）。
///   4. 远程版本更高 -> 下载对应文件 -> 校验 sha256 -> 存到本地缓存。
///   5. 下次启动优先用缓存；缓存坏了或校验不过就回退到内置。
///
/// 关键原则：
///   * **远程永远不能把 App 弄坏**。任何一步失败都静默回退到内置版本。
///   * **必须校验 sha256**。否则一个下载到一半的文件会让 App 永久不可用。
///   * 版本号必须**单调递增**，不能用时间戳（时钟不准会误判）。
library;

import 'dart:convert';

/// 单个数据文件的清单条目。
class ManifestFile {
  const ManifestFile({
    required this.name,
    required this.sha256,
    required this.bytes,
  });

  final String name;
  final String sha256;
  final int bytes;

  factory ManifestFile.fromJson(Map<String, dynamic> m) => ManifestFile(
        name: m['name'] as String? ?? '',
        sha256: m['sha256'] as String? ?? '',
        bytes: (m['bytes'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'name': name, 'sha256': sha256, 'bytes': bytes};
}

/// 一份知识库清单。
class KnowledgeManifest {
  const KnowledgeManifest({
    required this.version,
    required this.generatedAt,
    required this.files,
  });

  /// 单调递增的整数版本号。远程版本 > 本地版本才会更新。
  final int version;

  /// 生成时间，仅用于展示，**不参与版本比较**。
  final String generatedAt;

  final List<ManifestFile> files;

  ManifestFile? file(String name) {
    for (final f in files) {
      if (f.name == name) return f;
    }
    return null;
  }

  factory KnowledgeManifest.fromJson(Map<String, dynamic> m) {
    final rawFiles = m['files'];
    final files = <ManifestFile>[];
    if (rawFiles is Map) {
      // 内置 manifest 用的是 { "文件名": {sha256, bytes} } 形式
      rawFiles.forEach((k, v) {
        if (v is Map) {
          files.add(ManifestFile.fromJson({
            'name': k.toString(),
            ...v.cast<String, dynamic>(),
          }));
        }
      });
    } else if (rawFiles is List) {
      for (final e in rawFiles) {
        if (e is Map) files.add(ManifestFile.fromJson(e.cast<String, dynamic>()));
      }
    }
    return KnowledgeManifest(
      version: (m['version'] as num?)?.toInt() ?? 0,
      generatedAt: m['generated_at'] as String? ?? '',
      files: files,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'generated_at': generatedAt,
        'files': files.map((f) => f.toJson()).toList(),
      };

  static KnowledgeManifest decode(String text) =>
      KnowledgeManifest.fromJson(jsonDecode(text) as Map<String, dynamic>);
}

/// 一次更新检查的结果。用于界面提示，也让"为什么没更新"可解释。
enum UpdateOutcome {
  /// 本地已是最新。
  upToDate,

  /// 成功更新。
  updated,

  /// 网络失败（离线、超时、DNS）。**不算错误**，静默回退。
  unreachable,

  /// 远程 manifest 格式不对。
  badManifest,

  /// 有文件 hash 校验失败，已放弃本次更新。
  hashMismatch,

  /// 用户在设置里关掉了自动更新。
  disabled,
}

class UpdateReport {
  const UpdateReport({
    required this.outcome,
    this.fromVersion = 0,
    this.toVersion = 0,
    this.message = '',
  });

  final UpdateOutcome outcome;
  final int fromVersion;
  final int toVersion;
  final String message;

  bool get changed => outcome == UpdateOutcome.updated;

  @override
  String toString() =>
      'UpdateReport(${outcome.name}, $fromVersion -> $toVersion, $message)';
}
