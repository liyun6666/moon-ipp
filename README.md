# moon-ipp

[![CI](https://github.com/liyun6666/moon-ipp/actions/workflows/ci.yml/badge.svg)](https://github.com/liyun6666/moon-ipp/actions/workflows/ci.yml)

MoonBit 原生 IPP 网络打印协议库和客户端。业务系统可以查询打印机能力、预检参数、提交已有文档、查看或取消任务。核心独立于 CUPS，后者仅作为独立互操作测试端。

模块 `liyun6666/moon-ipp` · 仓库 `moon-ipp` · 作者马昀昀 · Apache-2.0。

## 安装

需要 MoonBit stable 2026-10-23 或更新的兼容版本。网络客户端依赖 `moonbitlang/async@0.22.5`；native 构建需要 C 编译器，Windows 异步库要求 MSVC。Windows/Linux CI 验证 native，JS 客户端通过 Node.js 测试。

```sh
moon add liyun6666/moon-ipp@0.1.4
```

在 `moon.pkg` 中导入所需包：

```moonbit
import {
  "liyun6666/moon-ipp" @ipp,
  "liyun6666/moon-ipp/client",
}
```

协议核心和参数解析支持 wasm-gc、JS、native；异步客户端支持 JS、native；文件操作 CLI 支持 native。浏览器使用受目标服务 CORS 策略约束。CLI 可从源码运行：

```sh
git clone https://github.com/liyun6666/moon-ipp.git
cd moon-ipp
moon update
moon run cmd/main --target native -- help
```

Windows 可安装 Visual Studio C++ Build Tools 及 Windows SDK，然后由 MoonBit 脚本自动发现并初始化 MSVC；已有 MinGW/GCC 时也不需要修改系统 PATH：

```sh
moon run scripts/verify.mbtx
moon run scripts/verify.mbtx --run help
moon run scripts/verify.mbtx --run capabilities --uri ipp://localhost:8631/ipp/print
```

`--native-only` 只检查、测试和构建 native；默认验证 wasm-gc、JS、native 与格式。`--run` 将后续参数交给 native CLI。也可以在已经配置好 MSVC 的开发者终端直接使用 CLI。

Windows 验证入口提供针对 async 0.22.5 的 C 编译兼容处理：在临时副本中先清除冲突的 EINVAL 宏，再保留上游的 Windows 错误码映射；原始依赖文件保持不变。C4005 在此入口中按编译错误处理，并检查无关宏冲突仍会失败。其他项目直接构建未修复的上游包仍可能收到原告警；这是本项目的构建兼容层，不是上游已发布新版本。

## 库 API

离线创建、编码和解码一份请求：

```moonbit
let context = @ipp.RequestContext::new("ipp://localhost:8631/ipp/print", user="demo")
let request = context.printer_attributes(1, requested=["printer-name", "document-format-supported"])
let wire = @ipp.encode(request)
let parsed = @ipp.decode(wire)
assert_eq(parsed, request)
```

异步提交已有 PDF，默认先读取能力并调用 Validate-Job：

```moonbit
let transport = @client.HttpTransport::new()
let client = @client.Client::new("ipp://localhost:8631/ipp/print", transport)
let options = @ipp.JobOptions::{
  ..@ipp.JobOptions::new("Monthly report", "application/pdf"),
  sides: Some(@ipp.TwoSidedLongEdge),
}
let job = client.print_job(options, pdf_bytes)
let observations = client.wait_job(job.id)
```

代码需要可抛错的函数环境；网络示例需要 async 函数和已有 `pdf_bytes`。完整离线示例：

```sh
moon run examples/packet --target wasm-gc
```

## 三个可运行场景

先准备独立虚拟设备（Ubuntu/Debian）：

```sh
sudo apt-get install cups-ipp-utils avahi-daemon
sudo systemctl start avahi-daemon
mkdir -p /tmp/moon-ipp-spool
ippeveprinter -n localhost -p 8631 -2 -s 60 \
  -f application/pdf,text/plain -d /tmp/moon-ipp-spool -k "Moon IPP Demo"
```

**1. 业务报表打印。** 查询能力，提交仓库内的有效单页 PDF，取得任务 ID 后等待结束。设备须声明支持 PDF 及所选参数。

```sh
moon run cmd/main --target native -- capabilities --uri ipp://localhost:8631/ipp/print
moon run cmd/main --target native -- print --uri ipp://localhost:8631/ipp/print \
  --input examples/report.pdf --name "Monthly report" --sides two-sided-long-edge
# 用上一步输出的 id 替换 1。
moon run cmd/main --target native -- wait --uri ipp://localhost:8631/ipp/print --job-id 1
```

**2. 办公室队列管理。** 查询设备状态与队列，创建等待文档的任务，再取消它。

```sh
moon run cmd/main --target native -- health --uri ipp://localhost:8631/ipp/print
moon run cmd/main --target native -- jobs --uri ipp://localhost:8631/ipp/print --which all
moon run cmd/main --target native -- create --uri ipp://localhost:8631/ipp/print --format text/plain --name "Cancel me"
# 用 create 输出的 id 替换 2。
moon run cmd/main --target native -- cancel --uri ipp://localhost:8631/ipp/print --job-id 2
moon run cmd/main --target native -- job --uri ipp://localhost:8631/ipp/print --job-id 2
```

**3. 应用团队的打印集成验收。** 自动启动独立 CUPS，完成 PDF 打印、拒绝不支持的格式、取消任务、Create-Job/Send-Document、队列查询及离线 JSON 往返；对比 CUPS 保留的文档字节，并用其 ipptool 交叉验证类型。先停止占用 8631 端口的手动演示设备。

```sh
python3 scripts/interop_cups.py
```

证据存于 `interop-output/`，包括服务端日志、每条命令的输入输出和 `result.json`，CI 上传证据 artifact。虚拟设备验证协议交互与文档接收；纸面输出需按实体设备另行验证。

## 功能与边界

- IPP 1.1/2.x 消息、属性组、多值、嵌套集合、常用标准值类型、未知值与二进制文档；默认上限为头部 1 MiB、文档 16 MiB、属性 4096 个、值 16384 个、集合深度 16。属性组最多为属性预算加一，防止空组膨胀；尚未支持的扩展值标签明确拒绝。
- 八个操作：Get-Printer-Attributes、Validate-Job、Print-Job、Create-Job、Send-Document、Get-Jobs、Get-Job-Attributes、Cancel-Job。
- 联合语法属性可含不同类型的值，例如标准纸张 keyword 与自定义纸张 name；out-of-band 仍必须是单值。Send-Document 允许空文档作为最后一次结束请求，非最后一次仍要求文档数据。
- 份数、纸张、单双面、颜色、分辨率、质量、方向、number-up、页范围和文档格式预检；MIME 类型支持大小写及参数，比较时保留普通参数值的大小写含义；缺失能力通常警告，明确不支持则报错。
- media-col 尺寸、四边页边距、纸盒及纸张类型；设备健康、队列摘要、能力差异和打印计划预览。
- 有界 HTTP/HTTPS 传输、请求 ID 关联、超时和取消；同一 Client 只允许一个并发请求。Transport 可注入业务已有网络层。
- native 和 JS 都拒绝自动重定向；JS 不携带浏览器隐式凭据。响应正文执行字节上限；HTTP 头部解析由所用网络后端负责，该正文上限不是整个 HTTP 头部的内存配额。
- 带类型标签的 JSON 保留集合、未知值和字节；CLI `encode`、`decode`、`compare` 可离线排查。

文档由上游生成，须是设备支持的格式。首版不提供文档转换、渲染器、USB 驱动、DNS-SD 自动发现、通知订阅或完整 IPP Everywhere 认证，不声称覆盖全部厂商扩展。HTTP 401/403 等明确报错；认证使用调用方设置的 `MOON_IPP_AUTHORIZATION` 环境变量并要求 `ipps://`，TLS 使用系统信任根。不要把秘密写进 URI 或日志。

提交中丢失响应、成功响应缺少可用任务编号，或 Send-Document 返回了其他任务的编号，会抛出 `SubmissionUncertain`：设备可能已接收文档，应查询队列并核对，客户端不会自动重发。任务查询还会核对返回的 job-id，防止把其他任务的完成状态当作本次结果。终态为 completed、canceled、aborted；超出轮询次数报错。`PrintPlan` 是参数与状态预览，不保证传输成功。

## 验证与维护

```sh
moon check --target wasm-gc --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon check --deny-warn
moon test --deny-warn
moon build --deny-warn
moon info
moon fmt --check
python3 scripts/count_source.py --minimum 4001
```

计数只含手写 `.mbt` 非空非注释实现行，排除测试、生成接口、依赖、构建文件及 Python 测试脚本。测试覆盖合法及异常报文、长度极值、集合预算、日期、URI、参数、任务状态和真实 HTTP 失败路径。详见 [验收记录](docs/verification.md)、[AI 辅助申报草稿](docs/项目申报书.md) 和 [查重记录](docs/查重记录.md)。比赛的人工撰写要求适用于初审申报；如果已通过初审，无须仅因版本更新另交一份申报书。

原创实现依据 [RFC 8010](https://www.rfc-editor.org/rfc/rfc8010) 和 [RFC 8011](https://www.rfc-editor.org/rfc/rfc8011)。[OpenPrinting CUPS](https://github.com/OpenPrinting/cups) 源码未被复制。依赖与许可证见 [第三方说明](THIRD_PARTY.md)。

本轮边界修复与验证范围见 [0.1.4 边界复核](docs/边界复核-0.1.4.md)；Windows 构建入口的 C4005 修复见 [0.1.3 验证记录](docs/0.1.3-验证记录.md)。这些是工程验证记录，不代表赛事官方验收结论。
