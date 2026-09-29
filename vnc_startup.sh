#!/bin/bash
# 拉起虚拟桌面: TigerVNC(Xtigervnc) + fluxbox + UniVPN 客户端。
# 由 supervisor 的 [program:vnc] 调起, 前台运行(-fg), 退出即代表桌面挂了。
set -euo pipefail

DISPLAY_NUM="${DISPLAY#:}"
RFB_PORT="${VNC_PORT:-$((5900 + DISPLAY_NUM))}"
GEOMETRY="${VNC_RESOLUTION:-1024x768}"
DEPTH="${VNC_DEPTH:-24}"
VNC_PASSWORD="${VNC_PW:-${VNC_PASSWORD:-univpn}}"

log() { echo "[vnc_startup] $*"; }

# 上次没退干净的锁文件/套接字会让 Xtigervnc 起不来
rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}"
rm -f "${HOME}"/.vnc/*"${DISPLAY_NUM}".pid "${HOME}"/.vnc/*:"${RFB_PORT}".log
mkdir -p "${HOME}/.vnc"
chmod 700 "${HOME}/.vnc"

# 挂载进来的 UniVPN 配置目录 owner 可能不是容器用户, 这里兜底放开(客户端要往里写配置)
mkdir -p "${HOME}/UniVPN"
sudo chown -R vpnuser:vpnuser "${HOME}/UniVPN" 2>/dev/null || true

# 口令用 ASCII 模式写进 vncpasswd 文件:
# 不加 -f 时 tigervnc 会按当前 locale(这里是 zh_CN.UTF-8)编码口令,
# 客户端按字节算出来的密钥就不一样, 表现就是"密码明明没错却连不上"。
log "设置 VNC 口令(端口 ${RFB_PORT}, 桌面 ${GEOMETRY}x${DEPTH})"
printf '%s' "${VNC_PASSWORD}" | /usr/bin/vncpasswd -f > "${HOME}/.vnc/passwd"
chmod 600 "${HOME}/.vnc/passwd"

# -localhost no: 容器外的 VNC 客户端(以及 noVNC)才连得上
# -fg: 前台运行, 交给 supervisor 看管; 会话脚本用 /etc/X11/Xtigervnc-session
log "启动 Xtigervnc..."
exec /usr/bin/vncserver ":${DISPLAY_NUM}" \
    -fg \
    -localhost no \
    -geometry "${GEOMETRY}" \
    -depth "${DEPTH}" \
    -SecurityTypes VncAuth \
    -PasswordFile "${HOME}/.vnc/passwd" \
    -AlwaysShared \
    -rfbport "${RFB_PORT}"
