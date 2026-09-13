# 桌面应用系统字体与字体选择：经验总结

> 来源：sub-converter v0.1 实现「默认使用系统字体 + 用户自选字体」功能时实际踩过的坑。
> 目标读者：开发其它 Flutter 桌面工具（或原理类似的桌面应用）的自己人。
> 每一节都按「症状 → 根因 → 解法」组织，第 8 节是开工/验收清单。
> 本仓库的对应实现在 `lib/platform/` 与三个 runner，可作活例子。

## 1. 不要依赖引擎的默认字体回退

**症状**：界面中文渲染"看起来不对劲"——同一屏文字粗细不一、字形风格混杂。

**根因**：Flutter 桌面端默认只内置拉丁字体，CJK 走运行时回退。引擎的回退是按字符
逐个匹配的，不同字符可能落到不同家族/不同字重（Windows 上常混入宋体类衬线字形），
视觉上就是"粗细不均匀"。

**解法**：主动指定真实 UI 字体族 + 一条有序的 CJK 回退链，而不是把字体决策留给引擎：

- 主题里对所有文本样式应用 `fontFamily` + `fontFamilyFallback`
  （`TextTheme.apply(...)`，一次覆盖全部样式）；
- 回退链放在**任何情况下都生效**的位置——用户自选的字体可能缺 CJK 字形，
  回退链保证中文依然由雅黑/苹方等接管（见第 5 节）；
- 各平台默认值与回退链收在**一个纯 Dart 数据文件**里（本仓库：
  `lib/platform/app_typography.dart`），可单测、可文档化。

各平台精选默认（截至本文写作）：

| 平台 | 默认 | 备注 |
| --- | --- | --- |
| Windows | Microsoft YaHei UI | 中文系统的 shell 消息字体就是它；见第 2 节的动态取法 |
| macOS | PingFang SC | 苹方；不要用 `.AppleSystemUIFont`（私有名，解析不可靠） |
| Linux | Noto Sans CJK SC | 兜底值，正常情况下应取桌面环境当前字体，见第 2 节 |

## 2. "系统默认字体"在各平台的正确来源

**症状**：想跟随系统，但不同桌面环境/语言下拿到的字体不对。

**根因与解法**：每个平台的"系统 UI 字体"存在不同的地方，且有的平台需要兜底链：

- **Windows**：`SystemParametersInfoW(SPI_GETNONCLIENTMETRICS)` 取 `lfMessageFont`。
  这是 shell 自己用的字体，天然跟随系统区域设置：中文系统 = Microsoft YaHei UI，
  英文 = Segoe UI，日文 = Meiryo UI。比硬编码"微软雅黑"更正确；查询失败再兜底
  固定值。
- **macOS**：直接固定 `PingFang SC`。`NSFont.systemFont.fontName` 返回
  `.AppleSystemUIFont` 这类私有名，DirectWrite/CoreText 能否解析不稳定，别用。
- **Linux（GNOME）**：`GtkSettings` 的 `gtk-font-name`（形如 "Cantarell 11"），
  用 `pango_font_description_from_string()` 解析出字族名——不要手写解析器。
- **Linux（KDE Plasma）**：**KDE 不一定给 GTK 填设置**（Wayland 会话尤其如此）。
  当 `gtk-font-name` 缺失/为空时，读 `~/.config/kdeglobals` 的 `General/font=`：
  这是 QFont 的 toString 格式（`Family[,style][,size],...`），**第一个逗号前的字段
  才是字族名**。C 侧用 GKeyFile 解析即可。

## 3. 枚举已安装字体：列表必须与渲染引擎的匹配规则一致

**症状**：字体选择器里选了某个字体，界面只有粗细变化、或完全没变化。

**根因**：这是本功能最大的坑。**Windows 上 GDI 与 DirectWrite 的"字族"模型不同**：

- GDI（`EnumFontFamiliesExW`）把字重变体列为独立字族：
  "Microsoft YaHei UI Light"、"MiSans Demibold"、"等线 Light"、"汉仪中黑 197"……
- 而 Flutter（Skia/Impeller）按 **DirectWrite** 匹配，这些只是同一基础字族的
  不同字面（face），按名字查找**找不到**；
- 找不到就走回退链 → 落回雅黑 → 用户看到"切换无效/只有粗细变"。

**解法**：Windows 上用 **DirectWrite 系统字体集合**枚举（`DWriteCreateFactory` →
`GetSystemFontCollection` → 逐 `IDWriteFontFamily::GetFamilyNames`），列表与引擎
同源，每个条目都能被引擎解析。注意两点：

- API 名是 **`GetFamilyNames`**（没有 `GetFaceNames`，编译期会教你做人）；
- 本地化名用 `FindLocaleName(用户区域)`，失败退 `en-us`，再退第 0 项。

macOS 用 `NSFontManager.availableFontFamilies`、Linux 用 Pango/fontmap（fontconfig），
它们的字族模型天然与渲染引擎一致，无需特殊处理。

其它要点：

- 本地化名 vs 英文名：跟随用户区域给出（中文系统显示"微软雅黑"），选择器体验更好；
- **字重变体不要进列表**——应用不支持选字重，列出来只会制造"选了没反应"的假象；
- 排序用大小写不敏感比较，去重同理（不同来源可能给出仅大小写不同的名字）。

## 4. 字重坑：CJK 字体普遍没有 500（Medium）字重

**症状**：某些控件的文字比周围明显粗（比如下拉框的选中值），换个字体也不一致。

**根因**：Material 主题里 `DropdownButton` 闭合态的值文本用 `textTheme.titleMedium`，
**默认 w500**。雅黑/苹方/MiSans 等中文字体通常只有 400/700（MiSans 例外地有全套），
w500 会被 DirectWrite 就近跳到 Bold。于是：同一段 UI 里，w400 的正文是常规体，
w500 的控件值是粗体；若同时存在逐字回退（第 5 节），不同字符还会落到不同字体
的不同字面上，粗细彻底开花。

**解法**：

- 在主题里**显式钉死** `titleMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w400)`
  （或给下拉传显式 style），消灭隐式 w500；
- 排查思路：凡是"比周围粗"的控件，先查它用的是哪个 theme 样式、该样式字重是多少；
- 标题类的 w600 是**整段统一**的，DirectWrite 会整段映射到 700，视觉上是一致的黑体
  加粗，这类可以保留——问题只出在**同屏混用 400/500** 的场景；
- 通用结论：**界面正文字重只用 w400，强调用 w600+，永远不要用 w500**，除非目标
  字体确认有 Medium 字面。

## 5. 逐字回退是字体回退的固有行为，不是 bug

**症状**：用户选了一个日文字体（如 BIZ UDPGothic），中文里「动」「统」这类简体
专用字和其它字粗细/风格不同。

**根因**：日文字体不含简体专用码位，这些字符必然逐字回退到回退链里的中文字体。
浏览器、编辑器都是同样行为。

**解法**：无解，只能管理预期：

- 回退链保证回退字体本身是好的（统一走雅黑/苹方），不要让缺字字符落到引擎随机
  回退上；
- 字体选择器**每一项用自身字体预览**，用户选之前就能看到真实效果；
- 若工具的目标用户会拿日文字体渲染中文，可以在文档里写明"建议选择含简体覆盖的
  字体"。

## 6. 字体选择器的持久化：别验证、别丢

**症状**：换机器/卸载字体后，启动时之前选的字体让下拉框崩溃或被悄悄重置。

**解法**：

- 持久化键存字族名字符串，读回时**不校验**是否还在系统里；
- 下拉框的"value 必须是 items 之一"约束自己处理：持久化值不在枚举结果里时，
  **把它作为额外条目插回列表**，既不崩溃也不丢用户选择；
- 渲染交给回退链（第 5 节），字体不存在时自动落到链上，无需特殊 UI。

## 7. UI 提示文案：悬停 tooltip 的图标要"看得见"

**症状**：把说明文字改成标签旁图标 + hover tooltip 后，用户反馈"悬停在文字后面
的空白区域弹出说明，很怪"。

**根因**：14px 灰色细线图标在 125% DPI 下只有十几个物理像素、线条极细，肉眼不可见；
但图标的悬停热区还在——等于一个**隐形触发区**。

**解法**：

- 说明类图标 18px、用主题主色（primary），一眼可见；
- 错误提示与值显示**保持内联**，永远不要塞进 tooltip（错误必须始终可见）；
- 验证手段：**DPI 感知的原生截图**放大看真实像素（`SetProcessDPIAware()` +
  `CopyFromScreen`，PowerShell 的 System.Drawing 默认 DPI 虚拟化会骗你）。

## 8. 开工 / 验收清单

实现同类功能时按顺序过一遍：

- [ ] 主题：`fontFamily` + `fontFamilyFallback` 应用到全部文本样式；
      无隐式 w500；标题用 w600+
- [ ] 默认字体来源：Win = 消息字体（NONCLIENTMETRICS），mac = 苹方，
      Linux = gtk-font-name + kdeglobals 兜底；查询失败有精选兜底值
- [ ] 字体枚举：Windows 走 DirectWrite 集合（不是 GDI）；
      字重变体不进列表；本地化名 + 排序去重
- [ ] 选择器：每项以自身字体预览；持久化值不在列表里也能显示与选择
- [ ] 回退链始终生效（用户选了缺字字体也不崩、不乱）
- [ ] 平台通道：查询失败静默降级为空/默认值，widget 测试（无原生实现）照常跑
- [ ] 图标/提示：说明走 tooltip、图标看得见；错误保持内联
- [ ] 打包（若含安装器）：**同版本重装必须能覆盖旧文件**
      （MSI：`MajorUpgrade AllowSameVersionUpgrades="yes"`，见下节）
- [ ] 三平台实机过一遍"默认渲染 + 切换字体 + 恢复默认"

## 9. 附：两个与字体无关但一起踩掉的坑

**MSI 同版本重装不覆盖文件**：MSI 对"版本号相同的已版本化文件"默认不覆盖，
且同版本产品不会被 MajorUpgrade 识别（默认不允许同版本升级）。结果：新包"安装
成功"但跑的还是旧 exe，控制面板还积累重复产品——极度浪费时间。解法：
`<MajorUpgrade AllowSameVersionUpgrades="yes" />`（会触发 ICE61 告警，属预期，
在构建脚本里写明理由后抑制）。

**图形 API 的名字陷阱**：DirectWrite 的字族名枚举方法是 `IDWriteFontFamily::
GetFamilyNames`，不是 `GetFaceNames`；Qt 字体串的第一段才是字族名；C 里解析
INI 用 GKeyFile，别手写。这类小错在原生侧一次编译失败就是一轮完整构建，
能省则省。
