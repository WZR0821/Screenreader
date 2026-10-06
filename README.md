# 读屏 · Screenreader

面向 iPhone 的截图与文字翻译应用。通过操作按钮完成 **截屏 → 识字 / 识图 → 翻译 → 可滚动全文窗口**，也可在 App 内输入文字、导入照片或图片文件。

**版本 1.0.0 · 构建 17 · iOS 18+ · 开发者 WANG ZIRUI**

界面为中文，默认目标语言为英语，默认 API 为 DeepSeek / `deepseek-flash`。支持中文、英语、日语及混合语言截图；已保存的语言、服务商、模型和密钥会继续保留。

本仓库以一次完整开发交付的方式收录当前最终版本，不包含旧安装包、旧版本提交历史或过程日志。详细能力见 [开发总结](Docs/Release-1.0.0/开发总结.md)。

## 三种翻译模式

| 模式 | 用途 | 实现 |
|---|---|---|
| 快速 | 完整、精炼地翻译，优先响应速度 | 本机 OCR + 单次 API；App 内另可选 Apple 系统翻译 |
| 专业 | 标题像标题、列表仍是列表、价格跟着商品、正文保持段落 | 本机确定内容关系，API 翻译块内容，本机校验并恢复结构 |
| 识图 | 讲解可辨认文字的大意与图片整体内容 | 支持图片的模型；全图及最多两张局部图放在一次请求中 |

可预先选默认模式，也可让操作按钮每次询问。三个模式各有独立默认提示词和自定义要求。系统翻译只支持 App 内快速模式，不使用 API 提示词；操作按钮仍走 API。模型能否处理图片取决于实际服务能力，不能把任意文字模型当作识图模型。

## 已实现的重点

- **全文阅读**：正式快捷指令返回完整 HTML，由系统“快速查看”展示；可滚到末尾、展开“查看原文”，字号、行距和配色可设置。
- **识字与排版**：结合位置和邻近文字过滤状态栏、导航图标及装饰；保留有意义的数量、价格、日期、评分、表情和数学符号。模糊区域有限次局部放大复识别，仍不确定时可明确选择识图重试。
- **专业完整性**：保留标题、正文、列表、字段和表格列关系；校验段落 ID、数字及列归属。漏段、数字丢失或接口截断不会被记成完整成功。
- **日语语义**：强化含税 / 未税、以上 / 以下、起止期限、套餐 / 单品、退款条件、否定、必选和脚注。默认指令随目标语言切换。
- **可配置 API**：DeepSeek、OpenAI、Gemini、Claude、通义千问及自定义 HTTPS 地址；支持 Chat Completions、Responses、Claude Messages，服务商配置与 Keychain 密钥分别保存。
- **效率与数据**：匹配输入的文字翻译可复用 20 分钟内存缓存；不缓存图片、不自动重试收费请求。可保留 10 / 30 / 100 条本机文字记录，支持搜索、删除和清空。
- **中文极简界面**：中英日语言选择、轻量交换动效、深浅主题及自定义颜色；设置首页七个模块，常规竖屏一屏展示，大字体和短屏保留可访问的滚动。

<table><tr>
<td><img src="Docs/Release-1.0.0/assets/home.png" width="240" alt="中文翻译首页，默认英语目标"></td>
<td><img src="Docs/Release-1.0.0/assets/reader.png" width="240" alt="英文译文的标题、段落、列表和价格排版"></td>
</tr></table>

## 安装与操作按钮

从仓库的 **Releases → v1.0.0** 获取 `Screenreader-iOS-v1.0.0-build17-unsigned.ipa`。这是 iPhoneOS arm64 未签名 Release，需要自行签名后安装。

1. 在读屏 **设置 → API 设置** 中选服务和模型，填写自己的 API Key 并保存。
2. 在 **设置 → 操作按钮 → 安装“读屏全文”** 中添加已连接好的快捷指令。
3. 打开 iPhone **设置 → 操作按钮 → 快捷指令**，选择 **读屏全文**。解锁后打开目标页面，长按按钮，按提示授权并上下滚动阅读全文。

没有操作按钮的 iPhone 也可从快捷指令运行，或使用 App 内翻译。已有“屏译全文”可继续使用；若重签名改变了应用标识，需在指令中重新添加当前安装版本的“翻译截图全文”。详见 [使用指南](Docs/Release-1.0.0/使用指南.md)。

## 构建

使用支持 iOS 18 SDK 的 Xcode，打开 `ScreenTranslate.xcodeproj`，选择 `ScreenTranslate` scheme。开发验证环境为 Xcode 16.2 / iOS 18.2 模拟器。内部工程名与 Bundle ID `com.raydon.ScreenTranslate` 保持稳定，应用显示名为读屏 / Screenreader。应用没有第三方包依赖。

```sh
# 增删源码后可重新生成工程
python3 Scripts/generate_project.py

# 构建未签名真机 Release
xcodebuild build -project ScreenTranslate.xcodeproj -scheme ScreenTranslate \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath work/DeviceBuild CODE_SIGNING_ALLOWED=NO

# 包装并校验 IPA
python3 Scripts/package_unsigned_ipa.py \
  work/DeviceBuild/Build/Products/Release-iphoneos/ScreenTranslate.app \
  work/Screenreader-iOS-v1.0.0-build17-unsigned.ipa
```

测试：`swift test` 运行 macOS 核心测试；Xcode Product → Test 运行 iOS 单元、集成与 UI 测试。系统快捷指令 UI 测试需要有“快捷指令”App 的中文模拟器环境，自动化请求使用本地固定响应，不产生 API 费用。八张合成日英图片仅加入测试 target，不进入 Release。

## 验证与限制

当前交付记录：**127 项核心测试、184 项不同 iOS 单元 / 集成用例、28 项不同 UI 用例最终通过**。iOS 数字按基线和定向复测中每个用例的最后结果去重。覆盖真实 Vision 识字、窄屏大字号 WebKit 排版、全文末段、原文展开、关闭后再次运行，以及设置、缓存和持久化。见 [验证结果](Docs/Release-1.0.0/验证结果.md)。

**构建 17 尚未进行新版真机 API 复测。** 固定接口响应测试不代表实际模型准确率或真机速度；Apple 系统翻译的语言包下载和实际翻译仍需真机验证。

Quick Look 的关闭工具栏、WPS 等推荐应用、窗口高度由 iOS 控制。本版不提供其他 App 上方的自定义半屏覆盖层。OCR 无法保证辨认模糊、微小竖排或艺术字；识图也必须明确看不清之处。翻译范围是提供的截图，不会自动滚动原 App 获取屏幕之外的内容。

## 文档

- [开发总结：完整功能、优化与兼容](Docs/Release-1.0.0/开发总结.md)
- [使用指南：API、三种模式、操作按钮与排错](Docs/Release-1.0.0/使用指南.md)
- [架构与 API：协议、扩展入口、数据校验](Docs/Release-1.0.0/架构与API.md)
- [隐私与数据处理](Docs/Release-1.0.0/隐私与数据.md)
- [验证结果与安装包校验](Docs/Release-1.0.0/验证结果.md)
- [未来开发方向与优先级](Docs/Release-1.0.0/开发路线.md)

公开源码不等于授予开源许可证；本仓库当前没有指定开源许可。Logo 与八张合成测试图由内置生图工具生成，具体模型版本未披露。测试素材为开发用途，不是实际商品、活动或预约信息。
