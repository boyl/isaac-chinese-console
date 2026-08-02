# 以撒中文控制台

面向 Windows / Steam 版《The Binding of Isaac: Rebirth》的中文图形控制台。当前版本为 **v1.3.0 批量执行版**。

[下载最新正式版](https://github.com/boyl/isaac-chinese-console/releases/latest) · [完整使用教程](./README-使用教程.md) · [版本记录](./版本信息.txt)

![批量执行演示](https://github.com/boyl/isaac-chinese-console/releases/download/v1.3.0/Isaac-Chinese-Console-v1.3.0-Demo.gif)

## 主要功能

- 中文分类整理常用、高强度道具与控制台命令。
- 点击卡片时与底部原生命令输入框联动。
- `giveitem`、`spawn` 支持一次执行 `1–99` 次，并实时显示进度。
- `debug`、`stage`、`kill`、`remove` 等危险命令始终只执行一次。
- 一次打开原生控制台，连续执行后只使用一次 `Esc` 关闭。
- 支持部分完成、关闭失败、失去焦点与按键注入失败的独立提示。
- 不安装 Mod、不联网、不读取存档。

## 快速开始

1. 从 [Releases](https://github.com/boyl/isaac-chinese-console/releases/latest) 下载 ZIP 并完整解压。
2. 双击 `一键环境检测.cmd`。
3. 关闭游戏后运行 `开启游戏控制台.cmd`，或手动将 `EnableDebugConsole` 改为 `1`。
4. 启动游戏并进入一局，再运行 `启动以撒中文控制台.cmd`。

详细前置要求、兼容模式和排障方式请阅读 [README-使用教程.md](./README-使用教程.md)。

## 安全说明

本项目通过 PowerShell 切换 Isaac 窗口并模拟键盘输入，因此部分安全软件可能提示脚本风险。所有脚本均为可读文本；正式分发包附带 `SHA256SUMS.txt`。使用调试控制台可能影响成就或解锁条件，建议用于娱乐、测试或已有备份的存档。

本项目与 Nicalis、Edmund McMillen、Valve 或 Steam 无关联。《The Binding of Isaac》及相关名称归其权利人所有。
