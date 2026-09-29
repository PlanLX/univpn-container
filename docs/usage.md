# 使用说明

## 目录结构

```
Dockerfile              从 ubuntu:22.04 开始装
install-univpn.sh       安装客户端(assets/ 里的包优先, 否则按版本号下载)
docker-compose.yml      端口/权限/卷
.env.example            配置模板(复制成 .env 使用)
vnc_startup.sh          起 Xtigervnc(虚拟桌面)
Xtigervnc-session       桌面会话: fluxbox + 客户端
univpn-keeper.sh        看护客户端(崩溃重启 / 断线重连)
novnc_launch.sh         noVNC 网页入口
novnc-serve.py          websockify 包装(给静态文件加 no-cache)
supervisord.conf        进程管理
danted.conf             SOCKS5 代理配置
danted-start.sh         等 VPN 网卡出现再起 Dante
tinyproxy.conf          HTTP 代理配置
univpn-client           Qt 环境的客户端包装(解释 Qt 版本冲突)
uvpaste / uvrestore     从宿主机推文字 / 把窗口拉回来
assets/                 放自己的客户端安装包(优先级最高)
```

## 端口说明

容器里:

| 端口 | 服务 |
|---|---|
| `6901` | noVNC 网页入口 |
| `5901` | 原生 VNC(TigerVNC) |
| `1080` | SOCKS5(Dante) |
| `8888` | HTTP(Tinyproxy) |

端口映射只写了容器端口的(比如 `- "6901"`)宿主端口会随机分配,用 `docker compose port`
查。想固定就直接写 `- "6901:6901"`。

## 安装包来源

`install-univpn.sh` 按这个顺序找客户端安装包:

1. **`assets/` 里的 `univpn-linux-*.zip` 或 `.run`** —— 想锁定版本就用这个,
   详见 [`assets/README.md`](../assets/README.md)
2. `.env` 里的 `CLIENT_ZIP_URL`
3. `CLIENT_ZIP_BASE`(默认指向开源项目
   [zx900930/docker-univpn](https://github.com/zx900930/docker-univpn) 的 `bin/`)
   + `CLIENT_VERSION`

> 公网上只发布过 `10781.19.0.1214` 和 `10781.21.0.0831` 两个官方 Linux 包。
> 想要别的版本: 把对应官方包放进 `assets/`, 再把 `.env` 里的 `CLIENT_VERSION` 改成
> 那个版本号(只影响镜像名和日志显示), 然后 `docker compose build --no-cache`。

客户端只有 amd64, Apple Silicon 上走 Rosetta 转译(compose 里已固定
`platform: linux/amd64`)。

## 常见问题

**网页打开是黑的**

客户端窗口可能被最小化/缩起来了。拉回来:

```bash
docker compose exec univpn uvrestore
```

**分辨率不合适**

默认 `1024x768`。VPN 客户端界面就一个登录框 + 服务器地址, 分辨率大了并不会多显示
什么, 反而 noVNC 要传更多像素。改 `.env` 里的 `VNC_RESOLUTION`, 然后重建容器
(不用重新构建镜像):

```bash
docker compose up -d
```

noVNC 默认开了 `resize=scale`, 桌面会自动缩放到浏览器窗口, 两边不用一样大。

**怎么把密码/验证码粘进去**

方式一, 用 noVNC 侧边栏的剪贴板面板: 粘完后**在别处点一下让它失焦**(noVNC 绑的是
`change` 事件, 不失焦内容不会发到远端), 再回客户端 Ctrl+V。

方式二(推荐, 最稳), 从宿主机直接推进去 —— 先在客户端里点一下要输入的框:

```bash
printf '%s' '你的密码' | docker compose exec -T univpn uvpaste
```

**客户端死了或者卡住**

```bash
docker compose exec univpn reconnect      # 杀掉客户端, keeper 会自动拉起
docker compose exec univpn supervisorctl status
docker compose logs -f
```

**要看 VPN 客户端的日志**

```bash
docker compose exec univpn ls -lt /usr/local/UniVPN/log | head
docker compose exec univpn tail -n 50 ~/UniVPN/UniVPN_UniVPNUI_0.log
```

**noVNC 页面打不开 / 提示连接被拒绝**

先确认端口: noVNC 的宿主端口是**随机**的, 用 `docker compose port univpn 6901` 查。

最常见的原因是 `docker-compose.yml` 的 `ports` 写错。容器里 noVNC 监听的是 **6901**,
所以那一行必须是 `- "6901"`(随机宿主端口)或 `- "6901:6901"`(固定 6901);
写成 `- ":6080"` 把宿主端口映到容器 6080 的形式是打不开的(容器里没有东西监听 6080)。
改完 `docker compose up -d` 重建容器。

**页面报 `does not provide an export named ...`**

浏览器缓存了旧版 noVNC 的 JS。本镜像的静态文件放在带版本+哈希的目录里, 理论上不会
出现; 真遇到了强刷一次(Ctrl+Shift+R)。

**要不要开自动重连**

`AUTO_RECONNECT=true` 后, keeper 每 10 秒 ping 一次 `RECONNECT_PING_TARGET`, 连续不通
就重启客户端。**如果这个目标在 VPN 里本来就不通(比如只放内网), 客户端会被反复重启**,
所以默认关着。要开就把目标设成能 ping 通的内网地址, 并给够
`RECONNECT_GRACE_PERIOD`(输验证码的时间)。