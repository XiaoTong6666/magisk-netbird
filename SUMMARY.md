# Magisk NetBird 模块工作总结

本文档总结本次把 NetBird Linux ARM64 二进制封装成 Magisk 模块的研究、实现、调试和验证过程。

## 目标

目标是制作一个类似 Magisk-Tailscaled 的 Magisk 模块，让 NetBird CLI/daemon 能在 Android root 环境中常驻运行，并通过命令行执行 `up`、`status`、`log` 等操作。

用户已明确一个关键约束：Linux 二进制在 Android 上运行时 DNS 管理会失效或干扰系统，因此模块必须默认关闭 NetBird 的 DNS 管理。

## 参考资料和源码研究

参考了 Magisk 官方开发文档和本地 Magisk-Tailscaled 源码：

- Magisk 官方模块文档：`module.prop`、`customize.sh`、`service.sh`、`uninstall.sh`、`system/bin` 注入、late_start service 阶段。
- Magisk-Tailscaled 源码目录：`D:\my_first_web\Magisk-Tailscaled-v2.0.0.1-full`
- NetBird 官方 CLI 文档：确认 `netbird` 二进制同时承担 daemon 和 CLI 控制端，支持 `up`、`status`、`service run`、`--setup-key`、`--management-url`、`--daemon-addr`、`--disable-dns` 等参数。

对 Magisk-Tailscaled 的主要结论：

- 其模块把运行数据放在 `/data/adb/tailscale`，模块目录只负责脚本和 system/bin 注入。
- `service.sh` 等待 `sys.boot_completed=1` 后调用启动脚本。
- `tailscaled.service` 中通用的 daemon 启停框架可以借鉴。
- Tailscale 专用的 `status --json` 解析不能直接复用。
- Tailscaled 的 `settings.sh` 硬编码模块路径，不适合照搬；新模块使用 `/data/adb/netbird/module.path` 记录模块路径。

## 已创建的模块文件

当前模块源码目录：

```text
D:\my_first_web\Magisk-netbird
```

主要文件：

```text
module.prop
customize.sh
service.sh
uninstall.sh
README.md
SUMMARY.md
META-INF/com/google/android/update-binary
META-INF/com/google/android/updater-script
netbird/settings.sh
netbird/scripts/start.sh
netbird/scripts/netbird.service
netbird/bin/netbird
system/etc/resolv.conf
```

当前打包产物：

```text
D:\my_first_web\magisk-netbird-v0.1.0-arm64.zip
```

## 模块安装逻辑

安装入口：

```text
META-INF/com/google/android/update-binary
```

安装定制脚本：

```text
customize.sh
```

`customize.sh` 做的事情：

- 只支持从 Magisk/KernelSU/APatch 管理器安装，不支持 recovery 安装。
- 检测架构：
  - `arm64` 对应 NetBird release 的 `linux_arm64`
  - `arm` 对应 NetBird release 的 `linux_armv6`
- 创建运行目录：
  - `/data/adb/netbird`
  - `/data/adb/netbird/bin`
  - `/data/adb/netbird/scripts`
  - `/data/adb/netbird/run`
- 解压模块脚本到 `/data/adb/netbird/scripts`
- 解压设置脚本到 `/data/adb/netbird/settings.sh`
- 优先使用 zip 内置二进制：
  - `netbird/bin/netbird-arm64`
  - 或 `netbird/bin/netbird`
- 如果 zip 没有内置二进制，则尝试从 GitHub `netbirdio/netbird` 最新 release 下载。
- 注入命令链接：
  - `/system/bin/netbird`
  - `/system/bin/netbird.service`
- 安装后尝试后台启动 daemon。

本次用户已把 `netbird_0.74.2_linux_arm64.tar.gz` 解压出的 `netbird` 放进：

```text
netbird/bin/netbird
```

因此现在的 arm64 zip 已内置 NetBird 二进制，不依赖手机安装时访问 GitHub。

## NetBird 运行路径设计

为了避免 Android 只读目录和传统 Linux 路径不兼容，模块把 NetBird 的配置、socket、日志放到 `/data/adb/netbird`：

```text
配置文件: /data/adb/netbird/config.json
daemon socket: /data/adb/netbird/run/netbird.sock
daemon 日志: /data/adb/netbird/run/client.log
service 日志: /data/adb/netbird/run/service.log
```

daemon 启动命令：

```sh
netbird service run \
  --config /data/adb/netbird/config.json \
  --daemon-addr unix:///data/adb/netbird/run/netbird.sock \
  --log-file /data/adb/netbird/run/client.log
```

CLI 控制命令通过：

```sh
netbird --daemon-addr unix:///data/adb/netbird/run/netbird.sock ...
```

## DNS 处理

NetBird DNS 管理已默认关闭：

- `netbird.service up` 会自动追加：

```sh
--disable-dns
```

- `settings.sh` 里也设置：

```sh
export NB_DISABLE_DNS=true
```

另外，为了解决 Linux 二进制在 Android 上可能缺少 `/etc/resolv.conf` 的问题，模块注入：

```text
system/etc/resolv.conf
```

内容：

```text
nameserver 1.1.1.1
nameserver 8.8.8.8
options timeout:2 attempts:2
```

这个文件只是给 Linux 二进制运行时提供传统 resolver 文件，不代表启用 NetBird DNS 管理。

## 手机实机调试过程

手机已通过 adb 连接，实际执行过 NetBird 入网命令，setup key 仅用于调试命令，未写入模块源码或本文档。

调试命令模板：

```sh
adb shell su -c 'sh /data/adb/netbird/scripts/netbird.service up --setup-key <KEY> --management-url https://82.156.12.252:4430'
```

### 第一阶段：daemon 能启动

执行：

```sh
netbird.service status
```

最初状态：

```text
daemon: running
OS: linux/arm64
Daemon version: development
CLI version: development
Management: Disconnected
Signal: Disconnected
NetBird IP: N/A
```

这说明：

- NetBird Linux ARM64 二进制能在 Android 上启动。
- daemon socket 能工作。
- CLI 能连接 daemon。

### 第二阶段：排除服务端不可达

测试手机到自建服务 IP 的连通性：

```sh
ping -c 3 82.156.12.252
toybox nc -w 3 82.156.12.252 4430 < /dev/null
```

结果：

- ping 正常。
- TCP 4430 正常，`nc_exit:0`。

因此自建服务 IP 和端口从手机网络上可达。

### 第三阶段：修复 USER 环境问题

daemon 日志最初出现：

```text
failed to get current user: user: Current requires cgo or $USER set in environment
```

原因：

- NetBird release 二进制在 Android 环境中调用 Go 的当前用户查询逻辑失败。
- 非 cgo 静态/交叉编译二进制在 Android root shell 中可能没有完整 Linux 用户数据库环境。

修复：

在 `netbird/settings.sh` 中加入：

```sh
export USER="${USER:-root}"
export LOGNAME="${LOGNAME:-root}"
export SHELL="${SHELL:-/system/bin/sh}"
```

修复后，日志中的 `failed to get current user` 消失。

### 第四阶段：修复 Android root/native 路由问题

修复 USER 后，daemon 日志变成：

```text
dial tcp 82.156.12.252:4430: connect: network is unreachable
```

但同一手机 shell 执行 `ping` 和 `nc` 都能访问该 IP 和端口。

进一步检查：

```sh
ip route show
ip rule show
ip route show table 1032
ip route get 82.156.12.252 uid 0
```

发现：

- Android 默认路由不在 main 表。
- 当前 Wi-Fi 默认路由在 Android 网络表 `1032` / `wlan0`。
- root/native daemon 没有 Android netd fwmark 时，走不到这个表，最后命中 unreachable 规则。

临时验证命令：

```sh
ip rule add pref 100 from all uidrange 0-0 lookup 1032
```

加完后再执行 NetBird up，连接成功。

已固化进 `netbird/scripts/netbird.service`：

- 启动 daemon 前自动查找 Android 当前默认路由表。
- 给 root uid 添加路由规则：

```sh
ip rule add pref 100 from all uidrange 0-0 lookup <route_table>
```

脚本会跳过 dummy0 默认路由，并尽量把 `table wlan0` 这类表名解析成数字表 ID。

### 第五阶段：修复 config warning

NetBird CLI 反复提示：

```text
Warning: Config flag is deprecated on up command, it should be set as a service argument with $NB_CONFIG environment or with "-config" flag
```

原因：

- daemon 启动需要 `--config`。
- 但 CLI 控制端执行 `up` 时不应该再传 config。
- 即使脚本不显式传 `--config`，环境变量 `NB_CONFIG` 仍可能被 CLI 识别并触发 warning。

修复：

`client_cmd()` 中临时清除 `NB_CONFIG`，只保留 daemon socket：

```sh
client_cmd() {
  ensure_android_route
  (
    unset NB_CONFIG
    netbird --daemon-addr "$NB_DAEMON_ADDR" "$@"
  )
}
```

daemon 本身仍然通过 `service run --config ...` 使用 `/data/adb/netbird/config.json`。

## 当前手机验证结果

最终执行：

```sh
sh /data/adb/netbird/scripts/netbird.service status
```

状态：

```text
daemon: running
OS: linux/arm64
Daemon version: development
CLI version: development
Management: Connected
Signal: Connected
Relays: 0/2 Available
Nameservers: 0/0 Available
FQDN: linux.gh.local
NetBird IP: 100.81.84.179/16
NetBird IPv6: fd23:a431:aeb1:9617:7547:bc2c:7ded:29ef/64
Interface type: Userspace
Wireguard port: 51820
Quantum resistance: false
Lazy connection: false
SSH Server: Disabled
Networks: 100.81.0.0/16
Peers count: 2/6 Connected
```

结论：

- Magisk 模块方向可行。
- NetBird daemon 已在 Android 上成功运行。
- Management 和 Signal 均已连接。
- 已拿到 NetBird IP。
- DNS 管理保持关闭。
- 当前使用 Userspace interface。

## 仍存在的问题和风险

### Relay 证书问题

日志中仍有：

```text
tls: failed to verify certificate: x509: certificate signed by unknown authority
```

影响：

- Management 和 Signal 已连接，不影响基础入网。
- Relay 可能不可用，状态显示 `Relays: 0/2 Available`。
- 某些无法直连的 peer 可能连接失败。

可能原因：

- 自建 relay 使用了 Android/Linux 二进制不信任的自签证书或私有 CA。
- NetBird Linux 二进制使用的证书信任链无法覆盖该 CA。

后续方向：

- 服务端 relay 使用公网可信 CA 证书。
- 或研究 NetBird 是否支持指定 CA 文件。
- 或把自签 CA 注入到二进制可识别的证书路径。

### ip6tables NAT 表问题

日志中有：

```text
ip6tables v1.8.7 (legacy): can't initialize ip6tables table `nat': Table does not exist
```

影响：

- 当前 daemon 继续运行，并进入 userspace 模式。
- IPv6 NAT/防火墙清理可能不完整。

后续方向：

- 可考虑默认禁用 IPv6 或防火墙相关功能。
- 需要看 NetBird 是否有适合 Android 的 `NB_DISABLE_IPV6`、`--disable-ipv6`、`--disable-firewall` 等参数组合。

### SSH 配置目录只读

日志中有：

```text
failed to update SSH client config: create SSH config directory /etc/ssh/ssh_config.d: mkdir /etc/ssh: read-only file system
```

影响：

- 当前 SSH Server 是 Disabled，基础组网不受影响。
- 如果后续要支持 NetBird SSH，需要单独处理 SSH 配置路径。

### Android 网络切换

当前自动路由修复会在 daemon start/client command 前根据当前默认路由表添加 root uid 规则。

风险：

- Wi-Fi/移动网络切换后，默认 route table 可能变化。
- 需要重启 `netbird.service` 或再次执行命令触发 `ensure_android_route`。

后续方向：

- 用 `inotifyd` 或轮询检测网络变化。
- 或增强 `start.sh` 定期刷新 root uid route rule。

## 常用命令

安装模块：

```sh
adb push D:\my_first_web\magisk-netbird-v0.1.0-arm64.zip /sdcard/
adb shell su -c 'magisk --install-module /sdcard/magisk-netbird-v0.1.0-arm64.zip'
adb reboot
```

启动：

```sh
adb shell su -c 'sh /data/adb/netbird/scripts/netbird.service start'
```

入网：

```sh
adb shell su -c 'sh /data/adb/netbird/scripts/netbird.service up --setup-key <KEY> --management-url https://82.156.12.252:4430'
```

状态：

```sh
adb shell su -c 'sh /data/adb/netbird/scripts/netbird.service status'
```

日志：

```sh
adb shell su -c 'tail -n 120 /data/adb/netbird/run/client.log'
adb shell su -c 'tail -n 120 /data/adb/netbird/run/service.log'
```

停止：

```sh
adb shell su -c 'sh /data/adb/netbird/scripts/netbird.service stop'
```

重启：

```sh
adb shell su -c 'sh /data/adb/netbird/scripts/netbird.service restart'
```

## 当前结论

NetBird Linux ARM64 二进制可以通过 Magisk 模块在 Android root 环境中运行。

完成的关键适配包括：

- Magisk 安装脚本和模块结构。
- 内置 NetBird ARM64 二进制。
- `/data/adb/netbird` 数据目录。
- daemon 后台启动管理。
- CLI 通过 unix socket 控制 daemon。
- 默认关闭 NetBird DNS 管理。
- 补充 Linux resolver 文件。
- 修复 `$USER` 缺失导致的 Go 当前用户查询失败。
- 修复 Android root/native 进程缺少 netd fwmark 导致的 `network is unreachable`。

当前可用状态：

- Management Connected
- Signal Connected
- NetBird IP 已获取
- Userspace interface 可运行

剩余主要问题：

- Relay 证书信任问题。
- IPv6 ip6tables NAT 表缺失警告。
- 网络切换后的 route rule 刷新机制还可以继续增强。
