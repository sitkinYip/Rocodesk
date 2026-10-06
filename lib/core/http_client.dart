/// HTTP 客户端的跨端抽象。
///
/// 为什么不让调用方直接 import：Web 端没有 `dart:io`，桌面与移动端用
/// `dart:io` 的 HttpClient 能更好地控制超时与连接复用。
/// 用**条件导入**在编译期选实现，调用方只看到 [httpPost] 一个函数。
///
/// 同时这个函数签名也是可注入的（`HttpPost`），便于单元测试里塞假实现，
/// 不真的发网络请求。
library;

import 'http_client_io.dart'
    if (dart.library.js_interop) 'http_client_web.dart' as impl;

/// 一次 HTTP 响应的最小信息。
class HttpResult {
  const HttpResult({required this.statusCode, required this.body});
  final int statusCode;
  final String body;
}

/// 发一个 POST 请求。抛出的异常由调用方包成用户可读的提示。
typedef HttpPost = Future<HttpResult> Function(
  String url, {
  required Map<String, String> headers,
  required String body,
});

/// 当前平台的实现。
Future<HttpResult> httpPost(
  String url, {
  required Map<String, String> headers,
  required String body,
}) =>
    impl.post(url, headers: headers, body: body);
