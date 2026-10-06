/// Web 端实现：用 `package:http`。
///
/// Web 上没法用 `dart:io`，而且浏览器有自己的超时与 CORS 策略。
///
/// **重要限制（必须让用户知道）**：浏览器会对跨域请求做 CORS 检查。
/// 多数模型服务商**不允许**浏览器直接带 Key 调用，所以 Web 版可能报
/// "被浏览器拦截"。桌面与移动端没有这个限制。
/// 遇到这种情况的解法是自己搭一个转发，或改用桌面 / 移动端。
library;

import 'package:http/http.dart' as http;

import 'http_client.dart';

const Duration _timeout = Duration(seconds: 120);

Future<HttpResult> post(
  String url, {
  required Map<String, String> headers,
  required String body,
}) async {
  try {
    final resp = await http
        .post(Uri.parse(url), headers: headers, body: body)
        .timeout(_timeout);
    return HttpResult(statusCode: resp.statusCode, body: resp.body);
  } catch (e) {
    throw HttpFailure('请求失败：$e\n'
        '浏览器可能因为跨域（CORS）拦截了这次请求。'
        '多数模型服务商不允许网页直接调用，建议改用桌面端或移动端。');
  }
}

class HttpFailure implements Exception {
  HttpFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
