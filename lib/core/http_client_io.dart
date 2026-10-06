/// 桌面 / 移动端实现：用 `dart:io` 的 HttpClient。
///
/// 比 `package:http` 好的两点：能设连接与读取超时（大图上传容易卡），
/// 以及能复用连接。Web 端走 `http_client_web.dart`。
library;

import 'dart:convert';
import 'dart:io';

import 'http_client.dart';

/// 大图上传 + 模型推理可能比较慢，给足时间但必须有上限，
/// 否则弱网下界面会一直转圈。
const Duration _timeout = Duration(seconds: 120);

Future<HttpResult> post(
  String url, {
  required Map<String, String> headers,
  required String body,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final req = await client.postUrl(Uri.parse(url)).timeout(_timeout);
    headers.forEach(req.headers.set);
    req.add(utf8.encode(body));
    final resp = await req.close().timeout(_timeout);
    final text = await resp.transform(utf8.decoder).join().timeout(_timeout);
    return HttpResult(statusCode: resp.statusCode, body: text);
  } on SocketException catch (e) {
    throw HttpFailure('网络连不上（${e.osError?.message ?? '无法解析域名'}）。'
        '检查网络，或确认接口地址是否正确。');
  } on HandshakeException {
    throw HttpFailure('HTTPS 握手失败。如果走了代理，请确认代理正常。');
  } finally {
    client.close(force: true);
  }
}

class HttpFailure implements Exception {
  HttpFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
