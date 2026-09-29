# 华为 UniVPN 客户端 + noVNC Docker 镜像
#
# 主要特性:
#   - ubuntu:22.04 从零构建, 不依赖第三方镜像
#   - noVNC 用上游最新版, 打开网页即进桌面, VNC 密码自动填
#   - 客户端崩溃自动拉起, 可选断线自动重连
#   - 自带 SOCKS5(Dante) 与 HTTP(Tinyproxy) 代理, 宿主机程序可借道容器 VPN
#
# 底座固定为 ubuntu:22.04: 客户端自带 Qt 5.15.3 且无 RPATH, 22.04 的系统 Qt 恰好
# 同为 5.15.3, 可混用; 换成更新的发行版(Qt 5.15.8+)会让两个版本的 Qt 进同一进程,
# 客户端一启动就 core dump。详见 univpn-client 包装脚本。
#
# 客户端只有 amd64, Apple Silicon 上走 Rosetta 转译, 故固定 linux/amd64。
#
# 构建: docker compose build  (版本等参数在 .env 里改)

FROM --platform=linux/amd64 ubuntu:22.04

# ---- 构建参数 ----------------------------------------------------------
# APT_MIRROR: 国内构建慢就换镜像站, 例如 mirrors.tuna.tsinghua.edu.cn
ARG APT_MIRROR=
# 客户端版本。安装包从 assets/ 或 CLIENT_ZIP_URL 取, 或按此版本号拼 URL 下载
# (见 install-univpn.sh)。
ARG CLIENT_VERSION=10781.21.0.0831
# 安装包直链, 留空则用 CLIENT_ZIP_BASE + 版本号拼出来
ARG CLIENT_ZIP_URL=
ARG CLIENT_ZIP_BASE=https://raw.githubusercontent.com/zx900930/docker-univpn/main/bin
# noVNC 用上游 tar 包, 不用发行版源里的老版本
ARG NOVNC_URL=https://github.com/novnc/noVNC/archive/refs/tags/v1.6.0.tar.gz

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    LANG=zh_CN.UTF-8 \
    LANGUAGE=zh_CN:zh \
    LC_ALL=zh_CN.UTF-8 \
    USER=vpnuser \
    HOME=/home/vpnuser \
    DISPLAY=:1 \
    VNC_RESOLUTION=1024x768 \
    VNC_DEPTH=24 \
    VNC_PORT=5901 \
    NOVNC_PORT=6901 \
    AUTO_RECONNECT=false \
    RECONNECT_PING_TARGET=1.1.1.1 \
    RECONNECT_GRACE_PERIOD=60 \
    DANTE_INTERFACE=cnem_vnic \
    CLIENT_VERSION=${CLIENT_VERSION}

# ---- 系统依赖 ----------------------------------------------------------
# tigervnc + fluxbox: 虚拟桌面; supervisor: 进程管理; dante/tinyproxy: 两个代理
#
# Qt5 是刻意装的: 系统 5.15.3 与客户端自带版本一致, 混用不冲突(详见 univpn-client 注释)。
#
# libxcb-* / libxkbcommon-x11-0 是客户端 xcb 平台插件 libqxcb.so 的依赖, 显式列出,
# 避免瘦身时被清掉后报 "Could not load the Qt platform plugin xcb"。
#
# x11-utils: 提供 xwininfo(排查窗口问题); x11-xserver-utils: 提供 xsetroot(给桌面铺底色)
RUN set -eux; \
    if [ -n "${APT_MIRROR}" ]; then \
        for f in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources \
                 /etc/apt/sources.list.d/debian.sources; do \
            [ -f "${f}" ] && sed -i \
                "s|archive.ubuntu.com|${APT_MIRROR}|g; \
                 s|security.ubuntu.com|${APT_MIRROR}|g; \
                 s|deb.debian.org|${APT_MIRROR}|g; \
                 s|security.debian.org|${APT_MIRROR}|g" "${f}"; \
        done; \
    fi; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl wget unzip locales tzdata tini sudo \
        net-tools iproute2 iputils-ping procps \
        dbus dbus-x11 \
        libx11-6 libxext6 libxrender1 libxtst6 libxi6 libxfixes3 libxdamage1 \
        libxcomposite1 libxrandr2 libxkbcommon0 libxcb1 libxau6 libxdmcp6 \
        libsm6 libice6 libglib2.0-0 libgl1 \
        libqt5core5a libqt5gui5 libqt5widgets5 libqt5dbus5 libqt5network5 \
        libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 \
        libxcb-render-util0 libxcb-shape0 libxcb-shm0 libxcb-sync1 \
        libxcb-xfixes0 libxcb-xinerama0 libxcb-xkb1 libxkbcommon-x11-0 \
        fonts-liberation fonts-noto-core fonts-wqy-zenhei \
        tigervnc-standalone-server tigervnc-tools fluxbox supervisor xterm \
        python3 python3-websockify \
        xclip xdotool x11-utils x11-xserver-utils \
        dante-server tinyproxy; \
    echo "${TZ}" > /etc/timezone; \
    ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime; \
    sed -i 's/^# *\(zh_CN.UTF-8\)/\1/; s/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen; \
    locale-gen; \
    rm -rf /var/lib/apt/lists/*

# ---- 用户 --------------------------------------------------------------
RUN set -eux; \
    groupadd --gid 1000 vpnuser; \
    useradd --uid 1000 --gid 1000 --shell /bin/bash --create-home vpnuser; \
    echo 'vpnuser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/vpnuser; \
    chmod 440 /etc/sudoers.d/vpnuser; \
    mkdir -p /home/vpnuser/.vnc /home/vpnuser/.fluxbox /home/vpnuser/UniVPN \
             /var/log/supervisor /var/run/dbus; \
    chown -R vpnuser:vpnuser /home/vpnuser /var/log/supervisor; \
    chmod 700 /home/vpnuser/.vnc; \
    chown messagebus:messagebus /var/run/dbus

# ---- 客户端本体 --------------------------------------------------------
# 安装包从 assets/ 取, 或按 CLIENT_ZIP_URL / CLIENT_ZIP_BASE 下载, 逻辑都在脚本里
COPY assets/ /tmp/assets/
COPY install-univpn.sh /usr/local/bin/install-univpn
RUN chmod +x /usr/local/bin/install-univpn && \
    CLIENT_VERSION="${CLIENT_VERSION}" \
    CLIENT_ZIP_URL="${CLIENT_ZIP_URL}" \
    CLIENT_ZIP_BASE="${CLIENT_ZIP_BASE}" \
    /usr/local/bin/install-univpn && \
    rm -rf /tmp/assets && \
    test -x /usr/local/UniVPN/UniVPN

# ---- noVNC 前端 --------------------------------------------------------
# 关键: 文件放带版本+哈希的子目录(例如 /opt/novnc-web/n/1.6.0-50661039/)。
# 浏览器会把同一个 URL 的 JS 缓存很久, 换命名空间后升级镜像就不会出现
# "新的 app/ui.js 配旧的 core/*.js" 这种版本错配。
RUN set -eux; \
    wget --tries=3 --timeout=30 -q -O /tmp/novnc.tar.gz "${NOVNC_URL}"; \
    ver="$(basename "${NOVNC_URL}" | sed -E 's/^v?([0-9][0-9.]*)\.tar\.gz$/\1/')"; \
    hash="$(sha256sum /tmp/novnc.tar.gz | cut -c1-8)"; \
    dir="/opt/novnc-web/n/${ver}-${hash}"; \
    mkdir -p "${dir}"; \
    tar -xzf /tmp/novnc.tar.gz -C /tmp; \
    cp -a /tmp/noVNC-*/. "${dir}/"; \
    rm -rf /tmp/novnc.tar.gz /tmp/noVNC-* "${dir}/index.html"; \
    printf '/n/%s-%s' "${ver}" "${hash}" > /opt/novnc-web/.novnc-path; \
    chown -R vpnuser:vpnuser /opt/novnc-web

# ---- 运行脚本 / 配置 ---------------------------------------------------
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY danted.conf /etc/danted.conf
COPY tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
COPY Xtigervnc-session /etc/X11/Xtigervnc-session
COPY fluxbox-keys /home/vpnuser/.fluxbox/keys
COPY fluxbox-menu /home/vpnuser/.fluxbox/menu
# 自备一份 fluxbox init: 默认那份会调 fbsetbg 设壁纸, 容器里没有壁纸工具,
# 它就会弹一个 xmessage 窗口占满屏幕(还挺难看)。这里直接用 xsetroot 铺个底色。
COPY fluxbox-init /home/vpnuser/.fluxbox/init
COPY vnc_startup.sh /usr/local/bin/vnc_startup.sh
COPY novnc_launch.sh /usr/local/bin/novnc_launch.sh
COPY novnc-serve.py /usr/local/bin/novnc-serve
COPY danted-start.sh /usr/local/bin/danted-start.sh
COPY univpn-keeper.sh /usr/local/bin/univpn-keeper.sh
COPY univpn-client /usr/local/bin/univpn-client
COPY fbsetbg /usr/local/bin/fbsetbg
COPY uvpaste /usr/local/bin/uvpaste
COPY uvrestore /usr/local/bin/uvrestore
# Windows 上编辑过的文件很容易带上 CRLF。在 Linux 里 CR 会变成内容的一部分:
# shebang 变成 "python3\r" 直接 command not found(127), danted 会把 "\r" 当成网卡名,
# tinyproxy 会拒绝解析配置。构建时统一清掉, 免得踩这个坑。
RUN set -eux; \
    find /etc/supervisor/supervisord.conf /etc/danted.conf /etc/tinyproxy/tinyproxy.conf \
         /etc/X11/Xtigervnc-session /usr/local/bin /home/vpnuser/.fluxbox \
         -type f -exec sed -i 's/\r$//' {} +
# reconnect: 手动重启客户端(客户端卡死时不必重启整个容器)
RUN set -eux; \
    printf '%s\n' '#!/bin/sh' \
        'echo "重启 UniVPN 客户端..."' \
        'pkill -f "/usr/local/UniVPN/UniVPN"' \
        > /usr/local/bin/reconnect; \
    chmod +x /usr/local/bin/vnc_startup.sh /usr/local/bin/novnc_launch.sh \
             /usr/local/bin/novnc-serve /usr/local/bin/danted-start.sh \
             /usr/local/bin/univpn-keeper.sh /usr/local/bin/univpn-client \
             /usr/local/bin/fbsetbg \
             /usr/local/bin/uvpaste \
             /usr/local/bin/uvrestore /usr/local/bin/reconnect \
             /etc/X11/Xtigervnc-session; \
    mv /usr/bin/fbsetbg /usr/bin/fbsetbg.real; \
    cp /usr/local/bin/fbsetbg /usr/bin/fbsetbg; \
    chmod +x /usr/bin/fbsetbg; \
    chown -R vpnuser:vpnuser /home/vpnuser/.fluxbox; \
    cp /etc/X11/Xtigervnc-session /home/vpnuser/.vnc/xstartup; \
    chown vpnuser:vpnuser /home/vpnuser/.vnc/xstartup; \
    chmod +x /home/vpnuser/.vnc/xstartup; \
    : > /var/log/tinyproxy.log; \
    chown vpnuser:vpnuser /var/log/tinyproxy.log; \
    touch /var/log/sockd.log; \
    chown vpnuser:vpnuser /var/log/sockd.log

# 5901 = 原生 VNC 入口, 6901 = noVNC 网页入口
EXPOSE 5901 6901 1080 8888
VOLUME ["/home/vpnuser/UniVPN"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD wget -q -O /dev/null "http://127.0.0.1:${NOVNC_PORT}/" || exit 1

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
