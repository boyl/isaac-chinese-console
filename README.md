# 以撒中文控制台 desktop-v1.4.3

面向 Windows / Steam 版《The Binding of Isaac: Rebirth》的离线中文图形控制台。无需安装 Mod，不联网、不读取存档；工具会切换到游戏窗口并通过原生调试控制台提交命令。

## 下载

- 推荐下载：[isaac-chinese-console-desktop-v1.4.3.zip](https://github.com/boyl/isaac-chinese-console/releases/download/desktop-v1.4.3/isaac-chinese-console-desktop-v1.4.3.zip)
- 版本说明：[desktop-v1.4.3 Release](https://github.com/boyl/isaac-chinese-console/releases/tag/desktop-v1.4.3)
- 下载后必须完整解压，再从解压目录运行 `START.cmd`；不要在 ZIP 预览窗口内启动。

## 本版重点

- v1.4.3 修复拆分后的外部脚本无法访问 HTA COM 对象、导致命令发送被误判为不可用的问题。
- 继续使用纯英文 `START.cmd` 和 PowerShell 自检启动器；只有检测到真实可见窗口才报告成功。
- Windows 脚本组件或 LocalAppData 被策略拦截时，界面进入可浏览的临时模式并显示明确诊断。

- 保留 v1.3.0 原有 11 个分类、74 个精选道具及排列顺序。
- 支持从用户本机的 External Item Descriptions（EID）离线导入 732 个道具的中英文名、可用说明、全拼和首字母；缓存仅保存在 `%LOCALAPPDATA%\IsaacChineseConsole`。
- 全局搜索支持中文、英文、拼音、首字母、ID 和原生命令；没有 EID 时仍可完整使用精选目录。
- 控制台操作扩展为 68 项：8 个调试、8 个补给、45 个普通模式楼层和 7 个贪婪模式楼层。
- 通用命令队列支持任意单行命令、排序、保存方案、取消和仅恢复未提交部分。
- 只有 `giveitem`、`spawn` 可以重复 2–99 次；其他命令始终按 1 次提交。
- 历史记录区分“请求次数”和“已提交次数”，不会把按键提交误报成游戏效果已验证。

## 快速开始

1. 完整解压发布 ZIP。
2. 双击 `一键环境检测.cmd`。
3. 关闭游戏后运行 `开启游戏控制台.cmd`，确保 `EnableDebugConsole=1`。
4. 启动游戏并进入一局，再在文件资源管理器中双击 `START.cmd`。聊天中的文件链接可能只会选中文件，不会执行脚本。
5. 可直接使用 74 个精选道具；点击“导入 EID”可启用完整中文目录。

完整说明见 [README-使用教程.md](./README-使用教程.md)。

## 更新日志

### desktop-v1.4.3（2026-08-08）

- 修复模块化外部脚本中 `ActiveXObject` 不可见，导致界面误报“Windows 脚本组件被拦截”、无法发送命令的问题。
- 新增 HTA 内联宿主桥，状态持久化、游戏检测、命令队列和 EID 导入统一复用经过验证的 COM 对象。
- 增加宿主桥回归测试，覆盖外部模块没有全局 `ActiveXObject` 的真实 Trident/HTA 场景。
- 已完成 Windows 实机启动与命令发送验收；分类、74 个精选道具、68 个控制台操作和命令语义保持不变。
- 补充正式 Release 下载入口、安装说明和分发包校验信息。

### desktop-v1.4.2（2026-08-08）

- 增加纯英文 `START.cmd` 和可见窗口自检，启动失败时保留明确日志与非零错误码。
- ActiveX 或 LocalAppData 被策略拦截时进入临时浏览模式，避免界面空白。

### desktop-v1.4.0（2026-08-07）

- 完成目录搜索、详情抽屉、响应式分页、EID 离线导入和状态持久化。
- 增加通用 JSON 命令队列、取消、部分完成恢复、方案与完整历史。
- 冻结原有 11 个分类及 74 个精选映射，并将内置控制台操作扩展至 68 项。

## 安全语义

- `remove c<ID>` 只移除道具，不会回滚拾取时产生的资源、实体、房间或生命变化。
- `stage` 仅提供已核对的普通/贪婪白名单，不生成未知后缀组合。
- 任意合法单行命令都可以加入队列；风险标签只提示，不阻止。建议在一次性测试存档中使用流程或 Lua 命令。
- 本工具只确认输入是否成功提交到游戏窗口；实际道具、资源、楼层和实体效果应在游戏内确认。

## 开发与验证

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -File .\tests\validate-desktop.ps1
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -File .\tools\build-desktop-package.ps1
```

运行时仍只要求 Windows PowerShell 5.1 和 `mshta.exe`；PowerShell 7 仅用于仓库开发与自动测试。

本项目与 Nicalis、Edmund McMillen、Valve、Steam 或 EID 项目无关联。《The Binding of Isaac》及相关名称归其权利人所有。本项目不会再分发 EID 原始文件或语言表。
