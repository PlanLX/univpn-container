#!/bin/bash
# 看护 UniVPN 客户端: 崩了就拉起来, 可选断线自动重连。
#
# 由 /etc/X11/Xtigervnc-session 在桌面起来后调用, 所以它跑在 vpnuser 的 X 会话里。
#
# AUTO_RECONNECT=true 时的逻辑:
#   启动 -> 等 RECONNECT_GRACE_PERIOD 秒(留时间给你输账号/密码/短信)
#        -> 每 10 秒 ping 一次 RECONNECT_PING_TARGET
#        -> 连续两次不通就杀掉客户端, 让下面的循环重新拉起
#
# 注意: 如果这个目标 IP 在 VPN 连上后本来就不通(比如 VPN 只放内网), 客户端会被
# 反复重启。所以默认关着, 要开就把目标设成内网里能 ping 通的地址。
set -uo pipefail

APP_CMD="/usr/local/bin/univpn-client"
# pkill 匹配用真实二进制路径: 包装脚本是 exec 启动的, 进程名会变成真实二进制
APP_MATCH="/usr/local/UniVPN/UniVPN"
TARGET="${RECONNECT_PING_TARGET:-8.8.8.8}"
ENABLED="${AUTO_RECONNECT:-false}"
GRACE="${RECONNECT_GRACE_PERIOD:-60}"
CHECK_INTERVAL=10
RESTART_DELAY=5

log() { echo "[keeper] $(date '+%F %T') $*"; }

# 等进程彻底退出, 免得新旧两个客户端抢同一个配置
stop_app() {
    local pid="$1"
    [ -n "${pid}" ] || return 0
    kill -0 "${pid}" 2>/dev/null || return 0

    log "结束客户端进程 ${pid}"
    kill "${pid}" 2>/dev/null || true
    local waited=0
    while kill -0 "${pid}" 2>/dev/null; do
        if [ "${waited}" -ge 20 ]; then
            log "进程没反应, 强制结束(SIGKILL)"
            kill -9 "${pid}" 2>/dev/null || true
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done
}

# 容器重启后可能有上次留下的残骸
pkill -f "${APP_MATCH}" 2>/dev/null || true
sleep 1

while true; do
    log "启动 UniVPN (记录在 ${HOME}/UniVPN 和 /usr/local/UniVPN/log)"
    "${APP_CMD}" &
    APP_PID=$!
    log "客户端 PID: ${APP_PID}"

    if [ "${ENABLED}" = "true" ]; then
        log "已开启自动重连: 宽限 ${GRACE}s, 之后每 ${CHECK_INTERVAL}s ping ${TARGET}"
        sleep "${GRACE}"

        while kill -0 "${APP_PID}" 2>/dev/null; do
            if ! ping -c 1 -W 2 "${TARGET}" >/dev/null 2>&1; then
                log "ping ${TARGET} 失败, 2 秒后复测"
                sleep 2
                if ! ping -c 1 -W 2 "${TARGET}" >/dev/null 2>&1; then
                    log "确认断线, 重启客户端触发重连"
                    break
                fi
            fi
            sleep "${CHECK_INTERVAL}"
        done
    else
        # 自动重连关着时, 等它自己退出
        wait "${APP_PID}"
    fi

    stop_app "${APP_PID}"
    log "${RESTART_DELAY} 秒后重新拉起"
    sleep "${RESTART_DELAY}"
done
