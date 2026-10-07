/// 识别提示词：从资产加载，不在代码里写。
///
/// ## 为什么提示词要离开代码
///
/// 它是**领域内容**，不是逻辑：
///
///   * 改动频率远高于调用它的代码 —— 调措辞、加例子、修歧义，
///     每次都要的人"懂 Dart 才能改"是不必要的门槛
///   * 它是这个项目里最长的中文文本（原来占 `vlm_client.dart` 76 行）
///   * 它和识别**逻辑**没有任何耦合：换一套完全不同的措辞，
///     HTTP 调用、JSON 解析、错误处理一行都不用动
///
/// 所以这里出现一个真实的 **seam**：提示词会变、客户端不会。
///
/// ## 为什么不让 VlmClient 自己去读资产
///
/// 「**接受依赖，不要创建依赖**」（codebase-design 的可测性原则）。
/// 如果 `VlmClient` 内部去 `rootBundle.loadString`，那它就：
///
///   * 在单元测试里不可用（要 Flutter binding）
///   * 把"提示词从哪来"这件事焊死在客户端里，将来想按精灵/按场景换提示词都难
///
/// 所以：**这里负责加载，`VlmClient` 只接受一个字符串。**
/// 调用方（生成页）在加载数据表的时候顺手把提示词也加载好。
///
/// 万一资产缺失（老包、打包漏了），[load] 返回 [fallback] ——
/// 一个最小可用的提示词，功能不至于整个不能跑，但会明确记录在
/// [Prompts.loadedFromAsset] 里便于排查。
library;

import 'package:flutter/services.dart' show rootBundle;

/// 提示词资产路径。改文件名要同时改 `pubspec.yaml` 的 assets 段。
const String kRecognizePromptAsset = 'assets/prompts/recognize_team.txt';

class Prompts {
  const Prompts._({
    required this.recognizeTeam,
    required this.loadedFromAsset,
  });

  /// 系统提示词：告诉模型图上的布局、图标含义、性格箭头表。
  final String recognizeTeam;

  /// 是否真的从资产读到了。
  ///
  /// 为 false 说明用了 [fallback] —— 识别大概率仍能跑，但准确率会明显下降，
  /// 所以界面可以据此提示"提示词没加载到"。
  final bool loadedFromAsset;

  /// 资产缺失时的兜底。**故意写得很短**：
  /// 与其塞一份会在两边漂移的完整副本，不如给最小指令 + 让排查有据可依。
  static const String fallback = '你是《洛克王国：世界》的阵容识别助手。'
      '读出图中每只精灵的名字、性格、个体资质、系别、血脉与技能，'
      '以 JSON 返回。只输出 JSON，不要解释。读不出的字段留空，不要编造。';

  /// 载入提示词（幂等，全局只读一次）。
  static Prompts? _cache;

  static Future<Prompts> load({bool useCache = true}) async {
    final cached = _cache;
    if (useCache && cached != null) return cached;

    try {
      final text = await rootBundle.loadString(kRecognizePromptAsset);
      if (text.trim().isEmpty) {
        return _cache = const Prompts._(
          recognizeTeam: fallback,
          loadedFromAsset: false,
        );
      }
      return _cache = Prompts._(
        recognizeTeam: text.trimRight(),
        loadedFromAsset: true,
      );
    } catch (_) {
      return _cache = const Prompts._(
        recognizeTeam: fallback,
        loadedFromAsset: false,
      );
    }
  }

  /// 测试用：不碰资产，直接给一份提示词。
  static Prompts forTest(String prompt) =>
      Prompts._(recognizeTeam: prompt, loadedFromAsset: true);
}
