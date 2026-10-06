# 架构与 API

应用无第三方包依赖，使用 SwiftUI、Vision、App Intents、Translation、ImageIO、WebKit 测试与系统 Keychain。提供可配置 API 客户端和可扩展源码接口层，没有公共翻译服务器。

## 目录与数据流

```text
ScreenTranslate/Core       设置模型、协议解析、语义排版、复识别策略、缓存
ScreenTranslate/Services   Vision / 图片处理、翻译管线、历史、HTML、钥匙串
ScreenTranslate/Views      SwiftUI 输入、结果、模式与设置
ScreenTranslate/Intents    文字、截图及截图全文动作
ScreenTranslate/Resources  已签名快捷指令、应用名称本地化
Tests                      macOS 核心 / iOS 集成 / UI / 图片素材
Scripts                    工程生成与未签名 IPA 包装校验
```

文字模式：图片 → 本机 OCR → 阅读块 → API 翻译 → 完整性校验 → 结果 / 历史 / HTML。专业输出类型以本机源块为准。识图：图片及局部图 + 可选 OCR 参考 → 一次视觉请求 → 文字大意 / 画面大意。

`TranslationPipeline.image(_:settings:key:)` 与 `text(_:settings:key:)` 是 App 和 Intent 的共享入口。`APIClient.translate` 处理单次网络调用；专业调用使用 `preserveBlocks` / 源阅读块，识图传入全图和 `imageDetails`。扩展协议适配器时仍应返回 `TranslationOutput`，保留上层完整性、取消和数据处理规则。

## 支持的协议

| 协议 | 路径 | 鉴权 | 响应处理 |
|---|---|---|---|
| Chat Completions | `/chat/completions` | Bearer | 合并文本内容，不把 reasoning_content 当译文 |
| Responses | `/responses` | Bearer | 遍历 output 中 message / output_text，忽略 reasoning，发送 store=false |
| Claude Messages | `/messages` | x-api-key、anthropic-version | 合并 text 内容，忽略 thinking |

地址仅允许 HTTPS，拒绝 URL 用户名、密码、查询参数与片段。支持基础地址、代理路径前缀和完整请求地址。模型列表通过 `/models` 获取；没有兼容列表接口时可手动填写。内置服务预设不保证账户一定拥有对应模型。

文字请求示例（密钥由调用者本地配置，不应写入仓库）：

```json
{
  "model": "your-model-id",
  "stream": false,
  "messages": [
    {"role": "system", "content": "所选模式、源/目标语言、术语与自定义要求"},
    {"role": "user", "content": "待翻译文字，作为数据处理"}
  ]
}
```

专业请求内容带 blocks 及 ID，返回同样 ID / text；字段和表格需保留源文的关系。检查 ID 缺失、重复、额外 ID、空段、数字遗漏 / 改写及串列。服务返回 `finish_reason=length`、`status=incomplete`、`stop_reason=max_tokens` 时抛出不完整错误，不写成功记录或缓存。

## 模式与提示词

`AppSettings.mode`：quick / professional / visual。`translationService`：api / system；system 限制为快速，操作按钮仍使用 API。兼容的旧设置字段在解码时迁移。

`modePrompts` 分模式保存要求，单模式最多 8,000 字符；`prompt(for:)`、`setPrompt(_:for:)` 操作指定模式，兼容属性 `customPrompt` 对应当前模式。模板变量单次替换，术语内容不再解释为模板。源文和图内指令属于数据，不作为执行命令。系统翻译忽略提示词和术语表。

`glossary` 上限 4,000 字符，其原文术语可提供 Vision customWords（最多 100 个）。原文上限 16,000 字符，超限明确报错而非偷偷截掉。

## 图片与局部复核

识字使用本机像素与 Vision 几何信息，复核预算按模式控制。识图先应用图像方向、重编码 JPEG，不复制原图 EXIF / GPS；全图长边最多 2048，最多两张局部图各最多 1800，总 JPEG 上限 8 MB。OCR 参考最多 4,000 字符，不作为已确定事实。

三种协议分别使用 image_url、input_image 或 Claude base64 image source。所有同图细节放在同一请求中，不增加自动重试；多图仍可能增加 token、费用与耗时。已知仅支持文字的模型在图片上传前拒绝，未知自定义模型的能力由服务决定。

## 超时、错误与取消

快速 / 专业 / 识图等待上限分别为 25 / 90 / 60 秒，会话资源时间上限 120 秒；这些是上限而非速度承诺。响应 JSON 上限 2 MB。401 / 402 / 403 / 404 / 429 / 5xx、超时和离线映射为中文提示，不显示任意服务原始错误正文。取消不覆盖新输入或显示旧结果，无自动重试。

URLSession 为 ephemeral，不使用 cookies 或 HTTP 缓存。应用级缓存为进程内、20 分钟、40 条 / 约 1 MB，按当前翻译输入和有效提示词等匹配，不存图片。

## 全文 Intent 与持久化

`TranslateScreenshotDocumentIntent` 接收 IntentFile 图片，返回 `Screenreader.html`（public.html），后接快速查看。`TranslationDocument.html` 恢复语义内容，不截断正文；原译文及警告都 HTML 转义，无 JavaScript / 远程资源。原文用原生 details 展开，可配置生成时字号、行距与主题。

`TranslateScreenshotIntent` 仅兼容旧预览，保持标识和字符串返回但不可发现；`TranslateTextIntent` 继续可用。三个动作 mode 支持 saved / ask / quick / professional / visual，文字动作不能选识图。saved 可依偏好询问本次模式；单次选择不修改默认。

升级保持 Bundle ID `com.raydon.ScreenTranslate`、偏好键 `screenTranslate.settings.v1`、Keychain service `com.screentranslate.app.api-keys` 和历史目录。历史从旧单结果迁移到 Application Support/ScreenTranslate/history.json，原子写入、文件保护、UUID 去重，损坏不静默覆盖。

## 开发注意事项

Release 排除调试测试路由、模拟操作入口、测试图片和凭据。`generate_project.py` 扫描源码生成稳定 ID 工程；`package_unsigned_ipa.py` 验证 iPhoneOS arm64、1.0.0（17）、全部 Mach-O 未签名、Intent 元数据和 ZIP CRC。更改源码后须重新构建并记录校验，不应沿用旧 IPA 的验证结论。
