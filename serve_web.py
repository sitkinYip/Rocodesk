#!/usr/bin/env python3
"""Serve the built web app over HTTP - the workflow that actually works here.

## Why not `flutter run`

`flutter run -d chrome` needs to launch a browser AND open a WebSocket debug
channel. In this environment both fail:

    DevHandler: Failed to create WebSocket debug connection:
      WebSocketException: Connection to 'http://127.0.0.1:60823/...=/ws#'
      was not upgraded to websocket

When that happens the dev server serves only a ~7.5 KB bootstrap shell; the real
code is meant to arrive over the debug channel, so the page is blank. A release
build has no such dependency: `main.dart.js` is ~2.8 MB and self-contained.

So: build once, serve statically, refresh to pick up changes.
Trade-off, stated plainly: **no hot reload**. Re-run the build after edits.

## Correct MIME types matter

Flutter web loads `main.dart.js` as a classic script, `flutter_bootstrap.js` as
a module, and `*.wasm`/`*.json` for assets. A wrong Content-Type makes the
browser refuse to execute the script and the page goes blank - which is exactly
the failure this script exists to avoid.
"""
from __future__ import annotations

import functools
import http.server
import socketserver
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

# 相对本脚本定位，不写绝对路径 —— 这样把 app 目录复制/克隆到任何位置都能用。
APP_DIR = Path(__file__).resolve().parent
ROOT = APP_DIR / "build" / "web"


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".js": "text/javascript",
        ".mjs": "text/javascript",
        ".json": "application/json",
        ".wasm": "application/wasm",
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".webp": "image/webp",
        ".svg": "image/svg+xml",
        ".css": "text/css",
        ".html": "text/html",
        ".bin": "application/octet-stream",
        ".ttf": "font/ttf",
        ".otf": "font/otf",
        ".woff": "font/woff",
        ".woff2": "font/woff2",
        ".symbols": "application/octet-stream",
    }

    def log_message(self, fmt, *args):  # noqa: ANN001
        # 只报错，不刷访问日志 —— 控制台要留给构建输出
        if not str(args[1] if len(args) > 1 else "").startswith("2"):
            sys.stderr.write("  %s\n" % (fmt % args))

    def end_headers(self):
        # 开发期禁用缓存，否则刷新看不到新构建（这个坑很浪费时间）
        self.send_header("Cache-Control", "no-store, must-revalidate")
        super().end_headers()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080

    if not (ROOT / "main.dart.js").is_file():
        print(f"[X] 没有构建产物: {ROOT/'main.dart.js'}")
        print("    先跑:  flutter build web --release")
        return 1

    size = (ROOT / "main.dart.js").stat().st_size
    print(f"提供静态构建: {ROOT}")
    print(f"  main.dart.js = {size/1024/1024:.2f} MB")
    if size < 1_000_000:
        print("  [!] 这个体积不像 release 构建（应约 2.8 MB）")
        print("      如果页面空白，先跑 flutter build web --release")
    print(f"  打开: http://127.0.0.1:{port}")
    print("  停止: Ctrl+C")
    print()

    handler = functools.partial(Handler, directory=str(ROOT))
    with Server(("127.0.0.1", port), handler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n已停止。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
