# 验收记录

本页记录可复现验证方法；GitHub Actions 保存每次运行的实际结果。

## 验证范围

- wasm-gc：协议核心、纸张规格、参数、诊断和 CLI 参数解析。
- JS：上述测试以及异步客户端的预检、超时、关联校验、提交不确定和任务等待。
- Linux native：检查、测试、构建 CLI；与独立 CUPS ippeveprinter / ipptool 交互。
- 本机 Windows：wasm-gc、JS、native 类型检查。完整异步 native C 构建要求 MSVC，本机缺少可用 MSVC，未宣称在 Windows 实体设备上验收。

## 有实际意义的互操作验收

`scripts/interop_cups.py` 启动系统安装的 CUPS 实现，测试客户端不能通过自己的编码器充当服务端来“自证”：

1. 能力查询、健康查询；提交有效 PDF，等待 completed，并与 CUPS 保留文档逐字节比较。
2. 已明确不支持的文档类型在预检阶段失败，队列任务数量不增加。
3. Create-Job 后取消等待文档的任务，再读取 canceled 状态。
4. Create-Job / Send-Document 提交文本，等待 completed，验证接收字节；队列包含两个完成任务和一个取消任务。
5. CUPS ipptool 独立检查任务 ID 和状态的属性类型。
6. 能力响应 JSON → IPP → JSON 完全一致；能力比较没有虚假变化。

完整证据在每次 CI 的 `cups-interoperability-evidence` artifact 中：`server.log`、`commands.json`、`ipptool.log`、`result.json` 和 spool 文件。测试针对虚拟设备，不将协议验收等同于实体打印机纸面质量或 IPP Everywhere 认证。

## 代码量和提交

```sh
python3 scripts/count_source.py --minimum 4001
git rev-list --count main
git log --oneline --reverse
```

代码量排除注释、空行、测试、依赖和构建产物，只统计 MoonBit 实现；源码、API、测试和文档按功能阶段提交，没有用空提交增加次数。

## 失败记录

早期 CI 使用不存在的 setup action，已改为官方工具链安装入口。独立测试发现 Ubuntu CUPS 不支持新版 `-roff` 参数，已使用 Avahi 初始化；随后发现错误信息只显示构造器名称，已保留可读原因。ipptool 默认只请求任务 ID/URI，交叉校验已显式请求 job-state。失败记录保留在公开 Actions 历史，最终验收以修复后的成功运行及其证据为准。
