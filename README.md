# v2rayn-proxy-guard

[中文](#中文说明) | [English](#english)

---

<a id="中文说明"></a>
## 中文说明

**v2rayn-proxy-guard** 是一个 Windows 系统代理守护脚本。

v2rayN 7.x 移除了旧版的"系统代理守护"功能：系统代理只在启动核心或切换节点时设置一次，之后如果有别的代理软件（例如其他机场客户端、Clash 系工具）把系统代理改写或关闭，v2rayN 不会自动夺回来，结果就是全系统静默断网。

本项目补上这块拼图：**自动检测你本机 v2rayN 的本地端口，并在系统代理被抢占时自动恢复。**

### 特性

- 🔍 **端口自动检测**，零配置：
  1. 优先读取 v2rayN 的 `guiConfigs/guiNConfig.json`（`Inbound[].LocalPort`，含第二入站端口）；
  2. 若该文件缺失，回退解析核心生成的 `binConfigs/config.json`（同时兼容 sing-box 的 `listen_port` 和 Xray 的 `port` 格式）；
  3. 端口以本机 v2rayN 实际配置为准，换端口、换机器都不用改脚本。
- 🛡️ **自动夺回**：发现系统代理被关闭或指向其他端口时，立即恢复为 `127.0.0.1:<v2rayN端口>`，并写入日志。
- 🧠 **尊重用户意图**，两种情况不动作：
  - v2rayN 没在运行（说明你想直连）；
  - v2rayN 内的系统代理模式不是"自动配置系统代理"（`SysProxyType ≠ ForcedChange`）。
- 📝 修复留痕：每次纠偏记录时间、修复前的值，方便回溯"是谁动了代理"。
- 🪶 无常驻内存：以 Windows 计划任务驱动，卸载只需删任务。

### 安装

```powershell
git clone https://github.com/<you>/v2rayn-proxy-guard.git
cd v2rayn-proxy-guard
.\install.ps1                 # 默认每 5 分钟检查一次
# 或
.\install.ps1 -IntervalMinutes 1 -Port 10809   # 自定义间隔 / 固定端口
```

无需管理员权限（只写 `HKCU` 注册表）。安装完立即执行一次检查。

### 工作原理

```
计划任务(每N分钟) ──► proxy-guard.ps1 -Once
                        │
                        ├─ v2rayN.exe 在运行吗？        ── 否 ──► 什么都不做
                        ├─ 定位 v2rayN 安装目录         （进程路径 / 自启任务 / 常见路径）
                        ├─ 读取端口                      （guiNConfig.json ──► binConfigs/config.json）
                        ├─ v2rayN 系统代理模式=自动配置？ ── 否 ──► 什么都不做
                        └─ 系统代理 = 127.0.0.1:端口？
                                   ├─ 是 ──► 什么都不做
                                   └─ 否 ──► 恢复 + 写日志
```

日志：`%USERPROFILE%\v2rayn-proxy-guard.log`（超过 512 KB 自动清空重记）。

### 卸载

```powershell
.\uninstall.ps1
```

### 已知局限

- 最长存在一个检查周期（默认 5 分钟）的"空窗期"；
- 只守护系统代理（注册表层），不处理 TUN/虚拟网卡层面的冲突；
- 如果 PAC 模式（`SysProxyType = Pac`），本项目不接管，避免误伤。

---

<a id="english"></a>
## English

**v2rayn-proxy-guard** reclaims the Windows system proxy for v2rayN.

Since v7.x, v2rayN applies the system proxy only once (on core start / server switch). If another proxy client overwrites or disables it afterwards, v2rayN never fixes it back and the whole system silently loses connectivity. This project adds the missing watchdog:

- **Auto-detects** the local inbound port of your v2rayN installation — from `guiConfigs/guiNConfig.json` (`Inbound[].LocalPort`), falling back to the generated core config `binConfigs/config.json` (supports both sing-box `listen_port` and Xray `port` formats). No hardcoded ports.
- **Restores** the system proxy to `127.0.0.1:<detected-port>` whenever it was disabled or pointed elsewhere — and logs every fix.
- **Respects intent**: does nothing when v2rayN is not running, or when v2rayN's own system-proxy mode is "clear"/"unchanged"/PAC.
- Runs as a plain Windows **scheduled task** (no resident process, no admin rights needed).

### Quick start

```powershell
.\install.ps1                 # check every 5 minutes, auto-detect port
.\install.ps1 -IntervalMinutes 1 -Port 10809   # custom interval / fixed port
.\uninstall.ps1               # remove
```

Requirements: Windows 10/11, PowerShell 5.1 or 7+, v2rayN installed locally.

### License

[MIT](LICENSE)
