/// 模型客户端：OpenAI 兼容的 Chat Completions，带图片输入。
///
/// 设计要点：
///   * 只依赖 `dart:io` 的 HttpClient —— **不引第三方 HTTP 包**，减少跨端变数；
///     注意 Web 端 `dart:io` 不可用，所以走 `package:http` 会更稳，
///     但为了先跑通链路，这里用条件导入（见 http_client_io.dart / http_client_web.dart）。
///   * 提示词与 Python 端 `roco/vlm.py` 保持一致：把布局讲清楚、
///     给出 30 条「箭头 -> 性格」对照表，模型才不会把「物攻↑魔攻↓」原样吐回来。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'http_client.dart';

/// 系统提示词。与 Python 端 `roco/vlm.py` 的口径保持一致，避免两端识别漂移。
const String kSystemPrompt = '''
你是《洛克王国：世界》的阵容识别助手。用户会给你一张阵容截图。
你需要读出图中每一只精灵的以下信息，并以 JSON 返回：

{
  "team_name": "队伍名，没有就写 未命名队伍",
  "magic": "魔法名，图中没有就写 进化之力",
  "pets": [
    {
      "name": "精灵全名",
      "types": ["冰", "萌"],
      "bloodline": "首领",
      "nature": "固执",
      "evs": ["物攻", "物防", "生命"],
      "skills": ["技能1", "技能2", "技能3", "技能4"]
    }
  ]
}

【图上的布局】
每一张精灵卡片从左到右依次是：
  1. 精灵头像
  2. 精灵名字（可能带「（形态）」后缀）
  3. 名字右边一到三个圆形小图标，代表系别，有时最后一个是血脉
  4. 「性格」标签 + 性格名 + 两个带箭头的小图标（升/降）
  5. 「个体资质」标签 + 三项资质
  6. 一行四个技能图标，图标下方是技能名

【系别与血脉图标（重要）】
名字右边那排小图标没有文字，只能靠图形辨认：
  - 前 1~2 个是**系别**，只可能是这 18 个之一：
    普通、火、水、草、电、冰、武、毒、地、翼、萌、虫、幻、幽、恶、龙、机械、光
    常见特征：冰=蓝色雪花，火=橙红火焰，草=绿色叶子，萌=粉色爱心，
    龙=红色龙首，幽=紫色幽灵，水=蓝色水滴，电=黄色闪电，翼=蓝紫羽翼，
    幻=紫色螺旋，恶=品红独角首，光=金色星光，机械=青色齿轮，地=棕色山岩
  - **最后一个图标是血脉**，它和系别图标长得不一样，通常是**花瓣/徽章形状**。
    血脉也只可能是这 24 个之一（括号内是常见图形）：
    普通 草 火 水 光 地 冰 龙 电 毒 虫 武 翼 萌 幽 恶 机械 幻
    （以上与系别同名），另外 6 个特殊血脉：
    首领（金红色皇冠）、巨兽、黑魔法、异核、污染、奇异
  - 「首领」最容易认：**金/红色的皇冠**形状
  - 如果那排只有系别、没有花瓣状徽章，说明这只精灵**没有血脉**，bloodline 写空字符串

【性格读法（重要）】
图上可能只显示箭头而没写性格名。箭头与性格的对应关系如下，
请务必按这张表把箭头翻译成性格名，不要自己编：

物攻↑物防↓ = 大胆      物攻↑魔攻↓ = 固执      物攻↑魔防↓ = 调皮
物攻↑速度↓ = 勇敢      物防↑物攻↓ = 逞强      物防↑魔攻↓ = 稳重
物防↑魔防↓ = 天真      物防↑速度↓ = 懒散      魔攻↑物攻↓ = 悠闲
魔攻↑物防↓ = 坦率      魔攻↑魔防↓ = 聪明      魔攻↑速度↓ = 专注
魔防↑物攻↓ = 偏执      魔防↑物防↓ = 冷静      魔防↑魔攻↓ = 理性
魔防↑速度↓ = 警惕      速度↑物攻↓ = 温顺      速度↑物防↓ = 害羞
速度↑魔攻↓ = 慎重      速度↑魔防↓ = 焦虑      生命↑物攻↓ = 胆小
生命↑物防↓ = 急躁      生命↑魔攻↓ = 开朗      生命↑魔防↓ = 莽撞
生命↑速度↓ = 热情      物攻↑生命↓ = 沉默      物防↑生命↓ = 忧郁
魔攻↑生命↓ = 平和      魔防↑生命↓ = 粗心      速度↑生命↓ = 踏实

【名字要写完整（重要）】
有些精灵在不同地区有**不同形态**，名字一样、外观和系别不一样，例如：
  - 卡瓦重：草地附近的样子（草）/ 火山附近的样子（草、火）/
            沙地附近的样子（草、地）/ 雪山附近的样子（草、冰）
  - 圣代甜甜、晶石蜗、化蝶 等也有多个形态（共 61 个名字有这种情况）
请**根据卡面上的系别图标判断是哪个形态**，并写进名字的括号里，
例如写「卡瓦重（雪山附近的样子）」。

如果你确实分不出是哪个形态，**只写基础名就好**（例如「卡瓦重」），
并确保 types 字段把看到的系别都写上 —— 后续会用它来推断形态。
千万不要随便挑一个形态写上去。

【个体资质】
「个体资质」后面写的三项就是。只可能是：
生命、物攻、魔攻、物防、魔防、速度

【要求】
- 只输出 JSON，不要任何解释、不要 markdown 代码块围栏。
- 读不出的字段留空字符串或空数组，**不要编造**。
- 技能名必须与图一致，看不清就留空。
- 图标辨认不确定时，**宁可留空也不要猜** —— 猜错的血脉或形态会直接写进阵容码。
''';

/// 识别结果。
class VlmResult {
  const VlmResult({required this.raw, required this.parsed});
  final String raw;
  final Map<String, dynamic> parsed;
}

class VlmException implements Exception {
  VlmException(this.message);
  final String message;
  @override
  String toString() => message;
}

class VlmClient {
  VlmClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    HttpPost? poster,
  }) : _post = poster ?? httpPost;

  final String baseUrl;
  final String apiKey;
  final String model;
  final HttpPost _post;

  /// 把图片字节转成 data URL。按魔数判断 MIME，避免模型因格式不符拒收。
  static String toDataUrl(Uint8List bytes) {
    final mime = sniffMime(bytes);
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  static String sniffMime(Uint8List b) {
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return 'image/png';
    }
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return 'image/webp';
    }
    if (b.length >= 4 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
      return 'image/gif';
    }
    return 'image/png';
  }

  Future<VlmResult> analyzeImage(Uint8List imageBytes,
      {String? extraHint}) async {
    if (apiKey.trim().isEmpty) {
      throw VlmException('还没填 API Key，请先到「设置」里填写');
    }
    if (baseUrl.trim().isEmpty) {
      throw VlmException('接口地址为空，请先到「设置」里填写');
    }

    final userContent = <Map<String, dynamic>>[
      {
        'type': 'text',
        'text': extraHint == null || extraHint.isEmpty
            ? '请识别这张阵容截图。'
            : '请识别这张阵容截图。\n\n$extraHint',
      },
      {
        'type': 'image_url',
        'image_url': {'url': toDataUrl(imageBytes)},
      },
    ];

    final body = jsonEncode({
      'model': model,
      'temperature': 0,
      'max_tokens': 2000,
      'messages': [
        {'role': 'system', 'content': kSystemPrompt},
        {'role': 'user', 'content': userContent},
      ],
    });

    final url = '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
    final resp = await _post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: body,
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw VlmException(_explainError(resp.statusCode, resp.body));
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw VlmException('模型没有返回内容');
    }
    final message = (choices.first as Map)['message'] as Map?;
    var content = message?['content'];
    // 有的服务商会返回 content 数组（多模态回复），拼起来
    if (content is List) {
      content = content
          .whereType<Map>()
          .map((e) => e['text'] ?? '')
          .join();
    }
    final text = (content as String?) ?? '';
    if (text.trim().isEmpty) {
      throw VlmException('模型返回了空内容，请重试或换一个模型');
    }
    return VlmResult(raw: text, parsed: parseJsonLoose(text));
  }

  /// 把服务端的报错翻译成用户能看懂的中文。
  static String _explainError(int code, String body) {
    final snippet = body.length > 300 ? '${body.substring(0, 300)}…' : body;
    return switch (code) {
      401 => 'API Key 无效或已过期（401）。请到「设置」里检查。',
      403 => '没有权限或额度不足（403）。请检查服务商后台。',
      404 => '接口地址不对（404）。自定义服务商要填到 /v1 这一层。',
      429 => '请求太频繁或超出配额（429）。等一会再试。',
      >= 500 => '服务商暂时不可用（$code）。稍后重试。',
      _ => '请求失败（$code）：$snippet',
    };
  }

  /// 宽松解析 JSON：模型有时会套一层 markdown 围栏或夹杂解释文字。
  static Map<String, dynamic> parseJsonLoose(String text) {
    var t = text.trim();
    // 去掉 ```json ... ``` 围栏
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(t);
    if (fence != null) t = fence.group(1)!.trim();
    // 直接就是 JSON
    try {
      final v = jsonDecode(t);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {
      // 继续尝试截取第一个 { 到最后一个 }
    }
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final v = jsonDecode(t.substring(start, end + 1));
        if (v is Map<String, dynamic>) return v;
      } catch (_) {
        // 落到下面统一报错
      }
    }
    throw VlmException('模型返回的不是有效 JSON，无法解析。原始内容开头：'
        '${text.length > 120 ? text.substring(0, 120) : text}');
  }
}
