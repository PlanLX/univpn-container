#!/bin/bash
# 启动 noVNC 网页入口(websockify 把浏览器接到容器内的 5901 上)。
# 由 supervisor 的 [program:novnc] 调起。
#
#   - 明文 HTTP: 不需要自签证书, 浏览器也不会拦
#   - 前端用 /opt/novnc-web 里的上游最新 noVNC
#   - 根路径和 /vnc.html 都是跳板页: 打开就自动连上, 密码自动填
set -euo pipefail

WEBROOT="${WEBROOT:-/opt/novnc-web}"
NOVNC_PORT="${NOVNC_PORT:-6901}"
VNC_TARGET="${VNC_TARGET:-localhost:${VNC_PORT:-5901}}"
NOVNC_PATH="$(cat "${WEBROOT}/.novnc-path" 2>/dev/null || true)"
# 镜像里 VNC 密码的环境变量叫 VNC_PW(vnc_startup.sh 读的就是它)
PASSWORD="${VNC_PW:-${VNC_PASSWORD:-}}"

if [ -z "${NOVNC_PATH}" ]; then
    echo "[noVNC] 找不到 ${WEBROOT}/.novnc-path, 镜像不完整" >&2
    exit 1
fi

# 跳板页: 带上 autoconnect / resize / 密码, 打开根路径就直接进桌面
for entry in index.html vnc.html; do
    cat > "${WEBROOT}/${entry}" <<HTML
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>UniVPN</title>
<script>
  // 打开根路径就自动连, 不用记 /vnc.html, 也不用手输密码
  var p = new URLSearchParams(location.search);
  p.set('autoconnect', '1');
  p.set('resize', 'scale');
  p.set('reconnect', '1');
  if (!p.has('password')) p.set('password', ${PASSWORD@Q});
  location.replace('${NOVNC_PATH}/vnc.html?' + p.toString());
</script>
</head>
<body style="background:#1b1b1b;color:#ccc;font-family:sans-serif">
正在进入桌面... 如果没有自动跳转, 请点击
<a style="color:#6cf" href="${NOVNC_PATH}/vnc.html?autoconnect=1&resize=scale">这里</a>。
</body>
</html>
HTML
done

echo "[noVNC] http://0.0.0.0:${NOVNC_PORT}/ -> ${VNC_TARGET} (${NOVNC_PATH})"
# novnc-serve 只是给静态文件补 no-cache 头的 websockify 包装, 参数原样透传
exec novnc-serve --web "${WEBROOT}" "${NOVNC_PORT}" "${VNC_TARGET}"
