#!/bin/bash
# 等 VPN 网卡出现之后再启动 Dante。
#
# 为什么要等: UniVPN 拨号成功后才会创建 cnem_vnic 这类网卡, 网卡不存在时 danted
# 会因为绑不上出口直接退出。这里先轮询等它出现, 出现了再把 external 改成这张网卡。
#
# 网卡名可以在 .env 里用 DANTE_INTERFACE 指定; 不确定的话先随便跑起来, 连上 VPN 后看:
#   docker compose exec univpn ip -br link
set -euo pipefail

INTERFACE="${DANTE_INTERFACE:-cnem_vnic}"
CHECK_INTERVAL="${DANTE_CHECK_INTERVAL:-5}"
WARN_AFTER="${DANTE_WARN_AFTER:-12}"   # 大约 1 分钟后开始提醒可能配错了

log() { echo "[danted-start] $(date '+%F %T') $*"; }

if ! echo "${INTERFACE}" | grep -Eq '^[A-Za-z0-9_.:-]+$'; then
    echo "[danted-start] DANTE_INTERFACE 名字不合法: ${INTERFACE}" >&2
    exit 1
fi

sed -i "s|^external:.*|external: ${INTERFACE}|" /etc/danted.conf
log "出口网卡设为 ${INTERFACE}, 等它出现..."

count=0
# 一直等: 没连上 VPN 时 Dante 起来也没用, 反复重启只会刷日志
while ! ip link show "${INTERFACE}" >/dev/null 2>&1; do
    count=$((count + 1))
    if [ "${count}" -eq "${WARN_AFTER}" ]; then
        log "已经等了 $((count * CHECK_INTERVAL)) 秒还没看到 ${INTERFACE}。"
        log "如果 VPN 已经连上了, 说明网卡名不对, 改 .env 里的 DANTE_INTERFACE;"
        log "还在等(进 VNC 里把 VPN 连上就能继续)。"
    fi
    sleep "${CHECK_INTERVAL}"
done

log "网卡 ${INTERFACE} 已就绪, 启动 Dante (SOCKS5 :1080)"
exec /usr/sbin/danted -f /etc/danted.conf
