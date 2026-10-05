# 第三方与来源

本项目为依据公开协议标准的原创实现，不是 CUPS 的源码移植。

| 项目 | 用途 | 来源 | 许可证 |
| --- | --- | --- | --- |
| MoonBit core | 字节、UTF-8、JSON、容器 | https://github.com/moonbitlang/core | Apache-2.0 |
| moonbitlang/async 0.22.4 | HTTP、TLS、异步、文件访问 | https://github.com/moonbitlang/async | Apache-2.0 |
| OpenPrinting CUPS | 独立互操作服务和 ipptool，仅 CI 系统依赖 | https://github.com/OpenPrinting/cups | Apache-2.0，含上游注明的例外 |
| RFC 8010 / RFC 8011 | 协议与语义规范，仅参考 | https://www.rfc-editor.org/rfc/rfc8010 / https://www.rfc-editor.org/rfc/rfc8011 | RFC 页面版权声明 |

项目没有复制 RFC 的规范正文或 CUPS 源码。测试字节向量和示例 PDF 为项目自行构造；PDF 使用标准内置 Helvetica 字体引用，没有嵌入第三方字体文件。第三方源码由工具链或包管理器取得，不作为本仓库实现行数。

AI 辅助使用 Codex 参与实现、测试和文档草拟；实际编译、测试结果和 GitHub CI 记录用于核验交付。参赛者需理解代码和申报内容，并按比赛的人工申报要求修改最终申报书。
