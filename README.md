# 以撒中文控制台 desktop-v1.5.0

面向 Windows / Steam 版《The Binding of Isaac: Rebirth》的离线中文图形控制台。无需安装 Mod，不联网、不读取存档；工具通过游戏原生调试控制台提交命令。

## 下载与启动

- 推荐下载：[isaac-chinese-console-desktop-v1.5.0.zip](https://github.com/boyl/isaac-chinese-console/releases/download/desktop-v1.5.0/isaac-chinese-console-desktop-v1.5.0.zip)
- 版本说明：[desktop-v1.5.0 Release](https://github.com/boyl/isaac-chinese-console/releases/tag/desktop-v1.5.0)
- ZIP SHA-256：`5A9C19CC99DF7FAF7F962687076C379F85537D53091CD95BB63223003E0F1E28`
- 必须完整解压 ZIP，再从文件资源管理器运行 `START.cmd`；不要在 ZIP 或聊天附件预览中启动。
- 首次使用先运行 `一键环境检测.cmd`，再关闭游戏并运行 `开启游戏控制台.cmd`。
- 启动游戏并进入一局，最后运行 `START.cmd`。

详细步骤见 [README-使用教程.md](./README-使用教程.md)。

## 本版重点

- 15 个分类，与中文控制台 Mod v2.5.3 的内容模型对齐。
- 内置 1056 个官方对象：721 个收藏品、188 个饰品、97 个卡牌/符文、50 个胶囊效果。
- 不安装 EID 和中文控制台 Mod 也能按中文、英文、全拼、首字母、类型 ID 和完整命令搜索、收藏、入队和执行。
- 使用 `c:182`、`t:1`、`k:1`、`p:0` 等类型化键，避免共享数字 ID 时串收藏或串详情。
- 74 个精选收藏品保留原分类、排序和原创详细说明；同一对象在完整目录与精选分类共用状态。
- EID 只提供可选详细效果说明，不再充当名称、拼音或完整目录来源。
- 保留命令队列、方案、取消、部分恢复和最近 100 条提交历史。
- 状态升级为 `%LOCALAPPDATA%\IsaacChineseConsole\state-v3.json`；旧数字收藏迁移为 `c:<id>`，旧文件保留用于回滚。
- 删除运行时拼音探测、旧 EID 全目录合并、无类型数字 ID 推断及孤立文件。

## 命令语义

- 收藏品：`giveitem c<ID>`，可重复 1–99 次；可用 `remove c<ID>` 移除本体。
- 饰品：`giveitem t<ID>`，固定 1 次；可用 `remove t<ID>` 移除本体。
- 卡牌/符文：`giveitem k<ID>`，固定 1 次，不提供移除。
- 胶囊效果：`giveitem p<ID>`，固定 1 次，不提供移除。
- `spawn` 可重复 1–99 次。其他内置、未知或流程命令固定 1 次；风险标签只提示，不阻止合法单行命令入队。
- `remove` 仅表示移除本体，不表示撤销，也不会回滚已产生的资源、实体、房间或生命变化。
- “已提交”只表示工具完成输入与回车，实际效果仍需在游戏中确认。

## 兼容性

运行时使用 Windows 自带的 `mshta.exe`、Windows PowerShell 5.1、FileSystemObject 和 WScript.Shell，目标为 Windows 10/11。企业策略、精简系统或安全软件若禁用 HTA、ActiveX/Windows Script Host 或模拟按键，发送功能可能不可用；环境检测会给出明确结果。游戏与工具权限级别必须一致。

## 开发与验证

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -File .\tests\validate-desktop.ps1
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -File .\tools\build-desktop-package.ps1
```

发布构建采用显式白名单，并阻断：ZIP 超过 131072 字节、解压后超过 327680 字节、包含校验文件后超过 20 个文件、运行模块孤立、PowerShell AST 解析失败或内部函数不可达。

## 更新日志

### desktop-v1.5.0（2026-08-09）

- 内置 1056 项官方对象和构建期拼音索引，新增全部收藏品、饰品、卡牌/符文、胶囊效果分类。
- EID 缓存升级为 `catalog-v2.json`，只保存类型化详细说明与来源元数据。
- 用户状态升级为 `state-v3.json`，完成类型化收藏迁移和缓存损坏回退。
- UI、队列与发送器统一四种对象命令的重复和移除规则。
- 增加目录、搜索、迁移、EID 降级、队列 DryRun、可达性、孤立文件和发布体积测试。

### desktop-v1.4.3（2026-08-08）

- 修复模块化 HTA 外部脚本无法访问宿主 COM 对象的问题，并增加自检启动器、完整队列、部分恢复和 68 项控制台操作。

## 第三方数据说明

内置对象名称与搜索别名在构建阶段从用户本机已安装的游戏辅助数据整理为紧凑目录；发布包不包含 EID 原始 Lua 文件、Mod 源码或运行缓存。EID 只作为用户主动选择的本机说明增强来源。项目采用保守再分发策略；参见 [External Item Descriptions](https://github.com/wofsauge/External-Item-Descriptions) 与 [GitHub 关于无许可证仓库的说明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)。

本项目与 Nicalis、Edmund McMillen、Valve、Steam 或 EID 项目无关联。《The Binding of Isaac》及相关名称归其权利人所有。
