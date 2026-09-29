#!/bin/bash
# 安装华为 UniVPN 客户端到 /usr/local/UniVPN。
#
# 安装包来源, 按优先级:
#   1. assets/ 目录里的 univpn-linux-*.zip 或 *.run —— 想锁定版本或离线构建就用它
#   2. 环境变量 CLIENT_ZIP_URL 指向的直链
#   3. CLIENT_ZIP_BASE + univpn-linux-64-<CLIENT_VERSION>.zip
#      默认 base 指向开源项目 zx900930/docker-univpn 里存的官方安装包
set -euo pipefail

ASSETS_DIR="${ASSETS_DIR:-/tmp/assets}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/UniVPN}"
LOG_FILE="${INSTALL_DIR}/log/install.log"
CLIENT_VERSION="${CLIENT_VERSION:-}"
CLIENT_ZIP_URL="${CLIENT_ZIP_URL:-}"
CLIENT_ZIP_BASE="${CLIENT_ZIP_BASE:-}"

log() { echo "[install-univpn] $*"; }

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

archive=""

# 1. 构建上下文里放的包优先, 方便固定版本
if [ -d "${ASSETS_DIR}" ]; then
    archive="$(find "${ASSETS_DIR}" -maxdepth 1 -type f \
        \( -name 'univpn-linux-*.zip' -o -name 'univpn-linux-*.run' \) | head -n 1 || true)"
fi

# 2. / 3. 从网络取
if [ -z "${archive}" ]; then
    if [ -z "${CLIENT_ZIP_URL}" ]; then
        if [ -z "${CLIENT_ZIP_BASE}" ] || [ -z "${CLIENT_VERSION}" ]; then
            echo "没有可用的安装包: assets/ 里是空的, CLIENT_ZIP_URL 也没给" >&2
            exit 1
        fi
        CLIENT_ZIP_URL="${CLIENT_ZIP_BASE}/univpn-linux-64-${CLIENT_VERSION}.zip"
    fi
    log "下载客户端安装包: ${CLIENT_ZIP_URL}"
    archive="${work_dir}/$(basename "${CLIENT_ZIP_URL}")"
    wget --tries=3 --timeout=60 -q -O "${archive}" "${CLIENT_ZIP_URL}"
fi

log "使用安装包: ${archive}"

# zip 里的 .run 才是真正的安装器
installer="${archive}"
case "${archive}" in
    *.zip)
        unzip -q -o "${archive}" -d "${work_dir}/unpacked"
        installer="$(find "${work_dir}/unpacked" -type f -name 'univpn-linux-*' ! -name '*.zip' \
            | head -n 1 || true)"
        if [ -z "${installer}" ]; then
            echo "压缩包里没找到 univpn-linux-* 安装器" >&2
            exit 1
        fi
        ;;
esac

chmod +x "${installer}"
mkdir -p "$(dirname "${LOG_FILE}")" /usr/share/fonts

# 安装器要求从它所在的目录执行
cd "$(dirname "${installer}")"
log "执行安装器 $(basename "${installer}") (日志: ${LOG_FILE})"
./"$(basename "${installer}")" > "${LOG_FILE}" 2>&1

if [ ! -x "${INSTALL_DIR}/UniVPN" ]; then
    echo "安装失败: ${INSTALL_DIR}/UniVPN 不存在, 详见 ${LOG_FILE}" >&2
    tail -n 30 "${LOG_FILE}" >&2 || true
    exit 1
fi

# 版本号记在 /etc/univpn.version, entrypoint/日志里会打印
if [ -n "${CLIENT_VERSION}" ]; then
    printf '%s\n' "${CLIENT_VERSION}" > /etc/univpn.version
else
    basename "${archive}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' > /etc/univpn.version || echo unknown > /etc/univpn.version
fi
log "安装完成: $(cat /etc/univpn.version)"
