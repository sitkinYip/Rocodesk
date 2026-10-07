/// 模型客户端：OpenAI 兼容的 Chat Completions，带图片输入。
///
/// 设计要点：
///   * 只依赖 `dart:io` 的 HttpClient —— **不引第三方 HTTP 包**，减少跨端变数；
///     注意 Web 端 `dart:io` 不可用，所以走 `package:http` 会更稳，
///     但为了先跑通链路，这里用条件导入（见 http_client_io.dart / http_client_web.dart）。
///   * **系统提示词不在这个文件里** —— 它由调用方通过 [systemPrompt] 传进来。
///     理由见 `prompts.dart`：提示词是领域内容，改动频率远高于客户端，
///     而且"接受依赖、不要创建依赖"能让这个类在单元测试里直接可用。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'http_client.dart';

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
    required this.systemPrompt,
    HttpPost? poster,
  }) : _post = poster ?? httpPost;

  final String baseUrl;
  final String apiKey;
  final String model;

  /// 系统提示词。**由调用方提供**（见 `prompts.dart`）。
  ///
  /// 必传而不是内部读资产：这样这个类在纯 Dart 单元测试里就能用，
  /// 而且"提示词从哪来"不被焊死在这里。
  final String systemPrompt;

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
        {'role': 'system', 'content': systemPrompt},
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
