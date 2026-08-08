# desktop-v1.4.3 发布说明

这是可直接分发的 HTA 宿主桥修复版。现有 11 个分类、74 个精选道具、68 个内置操作及命令语义均未改变。

## 下载文件

- 主程序：`isaac-chinese-console-desktop-v1.4.3.zip`
- 校验文件：`SHA256SUMS-desktop-v1.4.3.txt`
- 项目不会打包或再分发 EID 原始文件；完整道具目录由用户在本机离线导入。

下载完成后可使用 Windows 自带命令校验文件：

```powershell
certutil -hashfile isaac-chinese-console-desktop-v1.4.3.zip SHA256
```

输出值应与 Release 附件中的 `SHA256SUMS-desktop-v1.4.3.txt` 一致。

## 命令发送修复

- 修复 `desktop/*.js` 外部脚本中 `ActiveXObject` 未定义，导致界面错误提示“Windows 脚本组件被拦截”的问题。
- COM 对象改由可信的 HTA 内联引导创建，并通过 `window.IsaacHost` 提供给状态、队列和 EID 模块。
- 状态持久化、游戏检测、命令发送和 EID 导入统一复用同一宿主桥。
- 保留宿主桥确实不可用时的浏览降级模式，并显示实际错误原因。
- 增加宿主桥回归测试，覆盖外部模块没有全局 `ActiveXObject` 的运行环境。

## 启动方法

1. 完整解压 ZIP，不要覆盖运行中的旧版本目录。
2. 双击 `一键环境检测.cmd` 检查系统组件和数据目录。
3. 首次使用时关闭游戏，运行 `开启游戏控制台.cmd`。
4. 启动游戏并进入一局，再从解压目录双击 `START.cmd`。

不要直接点击聊天中的 `.cmd` 链接，也不要从 ZIP 预览窗口执行。

## 兼容性与限制

- 目标环境为正常安装、未被组织策略禁用 `mshta.exe`、Windows Script Host 或 Windows PowerShell 5.1 的 Windows 10/11。
- 无需管理员权限、联网服务或 Mod 安装；用户状态写入 `%LOCALAPPDATA%\IsaacChineseConsole`。
- 安全软件或组织策略拦截 HTA/脚本组件时，程序会进入浏览降级模式，无法代替系统策略发送命令。
- `remove` 只表示移除道具；只有 `giveitem` 和 `spawn` 支持重复执行，其他命令统一执行一次。
- 历史中的“已提交”只表示按键已发送到游戏窗口，不表示游戏内效果已经验证。

Repentance 与 Repentance+ 的真实命令效果仍需在一次性测试局中确认；“输入已提交”不代表游戏效果已验证。
