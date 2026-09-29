# 华为 UniVPN 客户端 Docker 镜像

在浏览器里用华为 UniVPN 客户端: 不用在宿主机装客户端, 也不用装 VNC 客户端。
打开 noVNC 页面就直接进桌面并连上, 密码自动填。

## 快速开始

```bash
docker compose up -d --build
docker compose logs -f
```

noVNC 用的是**随机宿主端口**, 先查一下再打开:

```bash
docker compose port univpn 6901          # 例如 0.0.0.0:9863 → 打开 http://localhost:9863
```

嫌每次查麻烦, 把 `docker-compose.yml` 里的 `- "6901"` 改成 `- "6901:6901"` 就是固定 6901。

| 入口 | 地址 | 用途 |
|---|---|---|
| noVNC 网页 | 随机端口, 用 `docker compose port univpn 6901` 查 | 浏览器用, 推荐 |
| SOCKS5 | `localhost:1081` | 让别的程序借道容器的 VPN |
| HTTP | `localhost:8889` | 同上, 给只支持 HTTP 代理的程序 |

> 容器内 noVNC 固定监听 **6901**, 所以端口映射必须写到 6901 这个容器端口上;
> 写成 `":6080"` 这种把宿主端口映到 6080 的写法是打不开的(那个端口没人监听)。

### 在客户端里登录

1. 打开 noVNC 页面(端口用 `docker compose port univpn 6901` 查)
2. 在 UniVPN 界面里填服务器地址、账号、密码、短信验证码
3. 登录成功后 `docker compose logs -f` 里会看到 Dante 起来(说明 VPN 网卡出现了)

登录信息保存在客户端配置目录, 已挂载 `./data/univpn`, 重建容器不用重新填服务器地址。

## 代理怎么用

VPN 连上之后:

```bash
# SOCKS5
curl -x socks5h://127.0.0.1:1081 https://内网地址/

# HTTP
curl -x http://127.0.0.1:8889 https://内网地址/

# 让某个程序全走这条代理(Windows PowerShell)
$env:ALL_PROXY = 'socks5h://127.0.0.1:1081'
```

链路: 程序 → 容器 `8888`(Tinyproxy) → 容器 `1080`(Dante) → VPN 网卡 → 内网。
默认是**分流**: 只有 VPN 路由表里的网段走隧道, 普通上网流量仍走本机网络。

Dante 等的是 `DANTE_INTERFACE`(默认 `cnem_vnic`)这张网卡。不确定名字就:

```bash
docker compose exec univpn ip -br link     # VPN 连上之后执行
```

## 配置项 (.env)

| 变量 | 默认值 | 说明 |
|---|---|---|
| `VNC_PASSWORD` | `univpn` | VNC/noVNC 密码 |
| `CLIENT_VERSION` | `10781.21.0.0831` | 客户端版本, 也是镜像 tag |
| `CLIENT_ZIP_URL` | 空 | 安装包直链, 一般不用 |
| `VNC_RESOLUTION` | `1024x768` | 桌面分辨率 |
| `SPOOF_MAC` | `02:42:ac:11:00:01` | 服务端校验客户端 MAC 时填被绑定的那个 |
| `AUTO_RECONNECT` | `false` | 断线自动重连, 原理见 docs/usage.md |
| `RECONNECT_PING_TARGET` | `1.1.1.1` | 判断"还连着"的探测地址 |
| `RECONNECT_GRACE_PERIOD` | `60` | 启动后留给你登录的秒数 |
| `DANTE_INTERFACE` | `cnem_vnic` | SOCKS5 出口网卡名 |
| `APT_MIRROR` | 空 | 国内构建用的 apt 镜像站 |
| `TZ` | `Asia/Shanghai` | 时区 |

## 构建

```bash
docker compose build
```

国内慢的话在 `.env` 里设 `APT_MIRROR=mirrors.tuna.tsinghua.edu.cn`。

客户端安装包按 `assets/` → `CLIENT_ZIP_URL` → `CLIENT_ZIP_BASE + 版本号` 的顺序获取,
详见 [docs/usage.md](docs/usage.md)。

## 权限说明

VPN 客户端要改路由表、建 TUN 设备, 所以需要:

```yaml
cap_add: [NET_ADMIN]
devices: ["/dev/net/tun:/dev/net/tun"]
```

这是 VPN 容器的常规配置。**不要**为了图省事加 `privileged: true` 或 `network_mode: host`,
除非确实遇到权限不够且清楚后果(那等于把容器隔离废掉了)。

宿主机需要 `tun` 模块。Windows/macOS 上的 Docker Desktop 已自带; 如果报
`/dev/net/tun` 不存在, Linux 上执行 `sudo modprobe tun`。

## 常见问题

清理残留缓存、粘贴验证码、黑屏恢复、自动重连等见 [docs/usage.md](docs/usage.md)。

## 关于版权

UniVPN 客户端是华为/联软的专有软件, 不在本仓库里分发。构建时从你的门户或公网已有的
位置下载, 请按你的授权协议使用, 别把安装包传到公开仓库(`.gitignore` 已经挡住
`assets/*.zip`)。本目录下的 Dockerfile 和脚本是自写的胶水代码。

## 许可证

[MIT](LICENSE)