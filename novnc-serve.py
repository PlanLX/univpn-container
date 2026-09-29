#!/usr/bin/env python3
"""启动 websockify, 并给 noVNC 的静态文件补上 no-cache 头。

浏览器会对没有 Cache-Control 的静态文件做启发式缓存。镜像升级换了新版 noVNC 之后,
浏览器可能拿旧的 app/ui.js 配新的 core/*.js, 报
"does not provide an export named ..." 之类的怪错。这里统一让静态资源不缓存。

用法和 websockify 一样, 多余的参数原样透传:
    novnc-serve --web /opt/novnc-web 6901 localhost:5901
"""
import sys

# websockify 各版本的请求处理类都不一样, 逐个试
_HANDLER_CANDIDATES = (
    ("websockify.websockifyserver", ("WebSocketRequestHandler", "WebSockifyRequestHandler")),
    ("websockify.websocketproxy", ("ProxyRequestHandler", "WebSocketProxyRequestHandler")),
)


def _find_handler():
    for module_name, class_names in _HANDLER_CANDIDATES:
        try:
            module = __import__(module_name, fromlist=["*"])
        except Exception:
            continue
        for class_name in class_names:
            handler = getattr(module, class_name, None)
            if handler is not None:
                return handler
    return None


def patch_cache_headers():
    """给所有响应加 no-cache 头。找不到类也不要影响启动。"""
    handler = _find_handler()
    if handler is None:
        print("warn: 没找到 websockify 的请求处理类, 静态文件未加 no-cache 头",
              file=sys.stderr)
        return

    original_end_headers = handler.end_headers

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        original_end_headers(self)

    handler.end_headers = end_headers


patch_cache_headers()

# 入口点在不同版本里位置不同
try:
    from websockify.websockify import websockify_init
except ImportError:
    from websockify.websocketproxy import websockify_init

sys.exit(websockify_init())
