# desktop-v1.4.2 发布说明

这是启动链自检修复版，分类、74 个精选、68 个内置操作和命令语义均未改变。

## 启动修复

- 新增纯英文 `START.cmd`，避免中文 CMD 文件名、代码页和聊天链接执行限制。
- 新增 `start-console.ps1`，使用固定 Windows PowerShell 5.1 路径启动 HTA。
- 启动前验证全部必需模块，缺少任何文件都会显示准确文件名。
- 启动后枚举真实的 `HTML Application Host Window Class`；只有找到 desktop-v1.4.2 可见窗口才报告成功。
- 成功后主动恢复并前置窗口；失败保留非零返回码并暂停窗口。
- 诊断写入 `%LOCALAPPDATA%\IsaacChineseConsole\launcher.log` 和 `launcher-status.json`。
- 原中文启动器保留，但仅作为 `START.cmd` 的兼容转发入口。

## 界面降级

- ActiveX、Windows 脚本组件或 LocalAppData 被拦截时，界面不再空白，会进入临时浏览模式。
- 此时仍可查看和搜索 74 个精选与 68 个内置操作，但持久化、EID 导入和命令发送不可用。

## 启动方法

完整解压 ZIP，在文件资源管理器中进入解压目录并双击 `START.cmd`。不要直接点击聊天中的 `.cmd` 链接，也不要从 ZIP 预览窗口执行。

Repentance 与 Repentance+ 的真实命令效果仍需在一次性测试局中确认；“输入已提交”不代表游戏效果已验证。
