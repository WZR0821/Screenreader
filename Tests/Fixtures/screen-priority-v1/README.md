# 读屏语言优先级截图测试集

6 张 PNG 模拟截图，2026-11-22 为 1.4.0（构建 33）制作，尺寸 1206×2622，和 iPhone 16 Pro 截屏一样大。手机界面是中文，屏幕内容是日语、中文或英语，用来检查操作按钮、截图和识图在“自动识别”下怎样按语言优先级改译。内容都是虚构的，链接只用 example 域名。

| 图片 | 场景 | 默认优先级（中文 › 日语 › 英语）下的预期 |
|---|---|---|
| [日语时间线](ja-timeline-zh-ui.png) | 中文界面的社交软件，四条日语帖子，带账号、链接、话题标签和 iPhone 等英文词 | 目标日语 → 改译为中文 |
| [日语聊天](ja-chat-zh-ui.png) | 中文界面的聊天，五条日语消息，带“已读”“按住 说话” | 目标日语 → 改译为中文 |
| [日语短聊天](ja-chat-sparse-zh-ui.png) | 只有“明日よろしくね！”“了解です！”两条消息，中文标签和日语差不多多 | 目标日语 → 改译为中文 |
| [中文群聊夹日语](zh-chat-with-ja.png) | 中文群聊里有一条日语消息 | 目标中文 → 仍译为中文；目标日语 → 仍译为日语 |
| [中文文章](zh-article.png) | 中文文章，末尾有“阅读原文 city.example.cn/winter” | 目标中文 → 改译为日语 |
| [英文时间线](en-timeline-zh-ui.png) | 中文界面的社交软件，三条英文帖子，带“为你推荐”“翻译帖子” | 目标英语 → 改译为中文 |

1.3.4 在其中 5 张上没有改译，只有“中文群聊夹日语”本来就对。

## 重新生成

`source/` 里是每张图的网页和渲染程序。渲染程序在屏幕外打开网页，按 3 倍缩放截图，不会出现在程序坞，也不抢焦点：

```bash
cd Tests/Fixtures/screen-priority-v1/source
xcrun swiftc -O render.swift -o /tmp/render-phone
/tmp/render-phone . .. ja-timeline-zh-ui ja-chat-zh-ui ja-chat-sparse-zh-ui zh-chat-with-ja zh-article en-timeline-zh-ui
```

重新生成后字体渲染可能有细微差别。Mac 和模拟器的识字结果也不完全相同，比如“3小时”常被认成“3小町”，“翻译帖子”被认成“翻洋帖子”。所以测试只检查最后译成哪种语言，不逐字核对识字结果。
