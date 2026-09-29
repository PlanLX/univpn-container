#!/bin/bash
# 容器入口: 解析 VNC 密码并打印访问信息, 然后交给 supervisord 拉起全部进程。
#
# VNC 密码行为与 baidupan 镜像一致:
#   - 设置了 VNC_PASSWORD / VNC_PW ── 用它
#   - 没设 ── 从挂载卷 ./data/univpn/.vnc-password 读, 有则沿用
#   - 都没有 ── 随机生成并保存到上面那个文件, 容器重启后沿用
set -euo pipefail

PASSWORD_FILE="${HOME}/UniVPN/.vnc-password"

# 兼容 VNC_PW 与 VNC_PASSWORD 两个变量名(VNC_PW 是镜像里沿用的旧名)
VNC_PASSWORD="${VNC_PASSWORD:-${VNC_PW:-}}"

if [ -z "${VNC_PASSWORD}" ]; then
    if [ -s "${PASSWORD_FILE}" ]; then
        VNC_PASSWORD="$(<"${PASSWORD_FILE}")"
        PASSWORD_NOTE="  (未指定 VNC_PASSWORD, 沿用上次随机生成的密码)"
    else
        VNC_PASSWORD="$(head -c 9 /dev/urandom | base64 | tr -d '/+=' | head -c 8)"
        PASSWORD_NOTE="  (未指定 VNC_PASSWORD, 已随机生成并保存到挂载卷)"
        if printf '%s' "${VNC_PASSWORD}" > "${PASSWORD_FILE}" 2>/dev/null; then
            chmod 600 "${PASSWORD_FILE}" 2>/dev/null || true
        fi
    fi
else
    PASSWORD_NOTE=""
fi

# 让 vnc_startup.sh / novnc_launch.sh 都能读到统一后的密码
export VNC_PW="${VNC_PASSWORD}"
export VNC_PASSWORD="${VNC_PASSWORD}"

NOVNC_PORT="${NOVNC_PORT:-6901}"
VNC_PORT="${VNC_PORT:-5901}"

cat <<BANNER
============================================================
 UniVPN 容器已就绪

 浏览器打开 : http://localhost:<宿主端口>/
   宿主端口  : docker compose port univpn ${NOVNC_PORT}   (例如 9863)
 原生 VNC   : vnc://localhost:${VNC_PORT}
 VNC 密码   : ${VNC_PASSWORD}${PASSWORD_NOTE}

 SOCKS5 代理: 127.0.0.1:1081
 HTTP 代理  : 127.0.0.1:8889
 配置目录   : ./data/univpn  (挂载宿主机目录, 保存登录信息)
============================================================
BANNER

exec "$@"