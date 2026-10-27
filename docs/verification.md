# 验收记录

本页记录可复现验证方法；GitHub Actions 保存每次运行的实际结果。

## 0.2.0 实测结果

2026-10-27，[CI 40427150535](https://github.com/liyun6666/moon-ipp/actions/runs/40427150535) 的 Windows/Linux 均通过：wasm-gc 78/78、JS 107/107、native 114/114。三套独立 CUPS 场景验证既有功能、空结束和实用工作流，包括凭据复用不重复提交、取消非零退出和文档字节一致。

实际发布 HTTP 200，注册表确认 0.2.0 未撤回；独立消费测试 2/2 通过，49 个代码与构建支持文件和发布源码一致。有效实现 5,151 行。细节及已知边界见 [工作流复核](实用工作流-0.2.0.md)。

## 0.1.5 实测结果

2026-10-26，[CI 40333080812](https://github.com/liyun6666/moon-ipp/actions/runs/40333080812) 的 Windows/Linux 任务均成功：wasm-gc 77/77、JS 102/102、native 103/103，检查、构建、格式、MSVC 探针和两套独立 CUPS 场景通过。

0.1.5 实际发布 HTTP 200，注册表确认未撤回；独立下载安装与消费测试通过，46 个代码与构建支持文件和发布源码一致。有效实现 4,889 行；复现的问题和修复见 [2026-10-26 复核](复核-2026-10-26.md)。

## 0.1.4 实测结果

2026-10-25，[CI 40179677640](https://github.com/liyun6666/moon-ipp/actions/runs/40179677640) 的 Windows/Linux 任务均成功：wasm-gc 69/69、JS 93/93、native 95/95，检查、构建、格式和 MSVC 探针通过。独立 CUPS 的既有流程及新增空结束请求全部通过；后者只收到一个字节未变的文档，任务正常完成。

发布返回 HTTP 200，Mooncakes 确认 0.1.4 未撤回。独立工程下载并通过消费测试，全部 45 个代码与构建支持文件与发布源码一致。有效实现 4,806 行；问题、修复、协议依据和测试边界见 [0.1.4 复核](边界复核-0.1.4.md)。

## 0.1.3 实测结果

2026-10-25，[CI 40170010056](https://github.com/liyun6666/moon-ipp/actions/runs/40170010056) 的 Windows/Linux 任务全部成功：wasm-gc 55/55、JS 69/69、native 74/74；Windows C4005 按错误检查，编译兼容探针、构建、脚本格式及 Linux CUPS 全流程均通过。

实际发布返回 HTTP 200；注册表确认 0.1.3、未撤回。独立消费测试 1/1 通过，下载包 37 个 MoonBit 文件及 3 个构建支持文件与发布代码一致。详见 [新版验证记录](0.1.3-验证记录.md)，并保留以下历史证据。

## 0.1.2 实测结果

2026-10-25，发布代码 `bfdb7c0fc13a39120fc18d0280840fc9d160abce` 的 [CI 40167374982](https://github.com/liyun6666/moon-ipp/actions/runs/40167374982) 两个任务全部成功：Windows/Linux 均为 wasm-gc 55/55、JS 69/69、native 74/74；严格检查、构建、格式通过，Linux 独立 CUPS 及大文档验收通过。本机也已安装 MSVC 并完成 native 验证。

实现行数 4,594；新增 5,000 组固定种子畸形报文及真实 HTTP 断流测试。工具链对齐 2026-10-23 stable，async 升级为 0.22.5。`moon info` 的接口变更仅为 Int32 名称规范化；归一化后根库、client、cli 接口一致。

发布返回 HTTP 200；注册表确认 0.1.2、未撤回，独立消费测试 1/1 通过，下载包全部 37 个 MoonBit 源文件与发布代码一致。摘要见 [CUPS 结果](evidence/cups-result-0.1.2.json)、[发布核验](evidence/release-verification-0.1.2.json)，完整结论与已知上游告警见 [新版复核报告](终审复核-2026-10-25.md)。

## 0.1.0 实测结果

测试日期：2026-10-05。发布源码提交：`6c55fad1050271314e8d8b83709c137a18a9ef2f`。

[完整成功 CI](https://github.com/liyun6666/moon-ipp/actions/runs/37303212132)：wasm-gc 35/35、JS 43/43、Linux native 43/43 测试通过；三个后端检查、native 构建、格式检查和独立 CUPS 全流程均通过。有效 MoonBit 实现 4,144 行，不含测试、注释、空行、示例、生成接口、依赖和构建文件。

CUPS 收到的 PDF 与文本均与输入逐字节一致，两个任务完成、一个任务取消；不支持的格式没有产生新任务。`ipptool` 交叉校验与 JSON 字节往返通过。完整日志和 spool 在该运行的 artifact 中，结果摘要见 [cups-result.json](evidence/cups-result.json)。

`moon publish` 返回 HTTP 200；[Mooncakes](https://mooncakes.io/docs/liyun6666/moon-ipp) 索引确认 `liyun6666/moon-ipp@0.1.0`，没有撤回。独立消费工程通过 `moon update` 从注册表下载 0.1.0，JS 消费测试 1/1 通过，验证编解码和 Client 公共接口，无本地路径依赖。

验证工具链：moon 0.1.20260920、moonc v0.10.14+7d59c7ec9（2026-09-18）、async 0.22.4。后续文档提交不会改写已发布的 0.1.0 源码。

## 0.1.1 实测结果

测试日期：2026-10-05。发布代码提交：`ba0228b3420cd61545aca773976f3c3ada02baef`。

[完整成功 CI](https://github.com/liyun6666/moon-ipp/actions/runs/37307580858)：wasm-gc 39/39、JS 50/50、Linux 默认 native 50/50；标准 `moon check --deny-warn`、`moon test --deny-warn`、`moon build --deny-warn`、格式检查及独立 CUPS 流程均通过。有效实现为 4,172 行，计数边界保持不变；`moon info` 后公共接口没有改变。

CUPS 验证继续覆盖两个任务完成、一个取消、格式拒绝不入队、文档字节相同与 ipptool 类型交叉校验。新增独立构造 1,048,832 字节二进制文档的 IPP → JSON → IPP 测试，JSON 超过 1 MiB，恢复结果逐字节一致。摘要见 [cups-result-0.1.1.json](evidence/cups-result-0.1.1.json)。

`moon publish` 返回 HTTP 200；注册表确认 0.1.1、未撤回，发布时间为 2026-10-05 12:11:19 UTC。独立消费工程日志显示 `Downloading liyun6666/moon-ipp@0.1.1`，从注册表下载后 JS 严格检查及消费测试 1/1 通过，没有本地路径依赖。对下载包的全部 34 个 `.mbt` 文件与上述 Git 提交逐一比较，仅规范换行后无差异。

赛事材料、工程与环境条件的完整自查见 [终审自查报告](终审自查报告.md)。

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
