# desktop-v1.5.1 发布说明

desktop-v1.5.1 是 desktop-v1.5.0 的启动故障热修复，不改变命令语义、目录数据、状态格式或既有标签。

## 根因与修复

- 首次初始化异常会触发 `window.onerror` 并替换整个 `document.body`。
- 已经发出的异步游戏状态探测随后返回，旧代码直接访问已被删除的 `statusDot` 和 `statusText`，产生第 288 行二次异常。
- 二次异常再次运行错误处理，覆盖 `startup-error.log` 和错误页面，导致真实首次异常丢失。
- 状态探测回调现在先缓存两个节点；任一不存在时立即返回。
- 启动错误处理在任何日志或 DOM 操作前锁定首次异常，后续异常只返回，不覆盖首次证据。

## 回归验证

- 异步探测发出后状态节点消失，回调不抛异常。
- 连续触发两次 `window.onerror`，日志和错误页只包含首次异常。
- 搜索/目录、状态迁移、DOM、HTA 宿主桥、发送协议、EID 导入、可达性和孤立文件测试全部通过。
- 修复版 HTA 实机启动后获得可见窗口，未生成新的 `startup-error.log`。

## 构建结果

- 文件数：20（限制 20）。
- 解压体积：230919 字节（限制 327680 字节）。
- ZIP 体积：85260 字节（限制 131072 字节）。
- ZIP SHA-256：`9BD887442422FF047EDF0EC02BA184EACF9A32B3C8EA6C89B4BBF42989AB23E1`。

## 发布资产

- `isaac-chinese-console-desktop-v1.5.1.zip`
- `SHA256SUMS.txt`

保留 `desktop-v1.5.0` 标签和既有 Release，不移动、不覆盖。只允许普通方式推送 `main` 和新标签 `desktop-v1.5.1`，并在发布后用远端 SHA 与 Release API 双重核验。
