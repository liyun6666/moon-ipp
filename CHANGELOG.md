# Changelog

## 0.1.1

- 核对任务查询返回的 job-id，防止等待过程中误认其他任务。
- 将提交成功但缺少可用任务编号的响应标记为 SubmissionUncertain，避免调用方误重试。
- 按 RFC 8011 修正 printer-uri / job-id 顺序，严格检查目标、任务和文档属性的类型及单值约束。
- 修复离线 JSON 输入上限过小导致较大文档无法往返的问题，增加独立构造的二进制文档验收。
- CI 直接执行默认 native 的 moon check、moon test、moon build，并保留跨后端及独立 CUPS 验证。

## 0.1.0

- 原创 IPP 编解码与八个标准操作，包含集合和带语言值。
- 参数预检、纸张规格、设备健康、队列汇总和能力差异。
- 异步传输和 native CLI；提交结果不确定时阻止自动重发。
- 标记 JSON、离线包工具、三个应用场景及独立 CUPS CI 验收。
