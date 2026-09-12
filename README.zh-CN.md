# Subtitle Converter（字幕格式转换器）

[English](README.md) | **简体中文**

一个轻量、完全离线的桌面字幕格式转换工具，支持六种文本字幕格式互转：SRT、WebVTT、LRC、
ASS、SSA、YouTube SBV。界面提供简体中文与英文：默认跟随系统语言，也可在应用内随时切换。
纯 Flutter 桌面应用：不上传任何文件，不依赖 FFmpeg / Python / Node，
运行期无需联网，无需额外安装运行时。把字幕拖进窗口、选目标格式，转换结果以 UTF-8 写在源文件
所在目录（或你指定的目录）。

## 支持的格式

| 格式 | 扩展名 | 保留的内容 | 有意丢弃的内容 |
| --- | --- | --- | --- |
| SubRip | `.srt` | 起止时间（毫秒精度）；多行纯文本；`<b>/<i>/<u>/<s>` 形式的行内**加粗**/*斜体*/下划线/删除线。 | 字幕序号（输出按 1..n 重新编号）；时间戳后的 SRT 定位数据（`X1:0 X2:100 ...`）读取时忽略、写出时不生成。 |
| WebVTT | `.vtt` | `WEBVTT` 头及其 `key: value` 元数据行；cue 标识符；时间戳后的 cue 设置（按不透明文本保存，VTT writer 会原样写回）；行内强调；HTML 实体会被解码。 | `STYLE`、`REGION` 块（跳过，不保留）；cue 设置不做解释也不建模，因此除 VTT 外的目标格式都会丢弃。 |
| LRC | `.lrc` | 元数据标签（`[ti:]`、`[ar:]`、`[al:]`、`[by:]`、`[offset:]`、`[length:]` 及未知 `[key:value]`），保留原始大小写；起始时间（厘秒精度）；文本。`[offset:]` 原样保留。 | 结束时间（该格式没有，解析时推断、写出时丢弃）；行内强调；多行 cue 的换行（用空格拼接）；增强型 LRC 的逐词时间戳 `<mm:ss.xx>`（剥离）。`[offset:]` 的值**不会**被应用。 |
| ASS | `.ass` | `[Script Info]` 字段；样式以原始字段映射保存；`Dialogue:` 事件；时间（厘秒精度）；样式引用；`Layer`/`Name`/`MarginL`/`MarginR`/`MarginV`/`Effect`；行内 `\b \i \u \s`；`\an`/`\pos` 对齐与位置；文本转义与换行。 | 卡拉 OK（`\k`、`\K`、`\kf`、`\ko`）；动画/变换（`\t`、`\move`、`\fad`、`\fade`、`\org`、`\clip`、rotation、blur、borders）；矢量绘图（`\p1`）；行内颜色/字体覆盖（`\c`、`\1c`..`\4c`、`\alpha`、`\fs`、`\fn`）；内嵌字体 `[Fonts]` 与图形 `[Graphics]`；所有非 `Dialogue` 事件（`Comment`、`Picture`、`Sound`、`Movie`、`Command`）。按规范要求 `Text` 必须是最后一个字段：若某文件把其他字段放在 `Text` 之后、且对白文本中含逗号，会报语法错误而不是猜测。 |
| SSA | `.ssa` | 与 ASS 相同：两者共用一套按 dialect 参数化的 parser/writer，行为不会分叉。输出 `[V4 Styles]`、`ScriptType: v4.00`、`Marked` 事件字段与 SSA 样式默认值。 | 同 ASS。 |
| SBV | `.sbv` | 起止时间（毫秒精度）；多行纯文本。 | 行内强调与位置：SBV 没有标记语法，只写纯文本。 |

输出始终为 UTF-8（LF 换行），可按文件选择是否写入 UTF-8 BOM。

## 使用

### 从源码运行

```bash
flutter pub get
flutter run -d windows     # 或 -d macos / -d linux
```

拖拽文件到窗口（拖入文件夹会加入其中一级的所有字幕文件）、按 `Ctrl+O`、或点「Add files」按钮添加字幕；
`Ctrl+Enter` 开始批量转换。启动时会恢复上次使用的选项。

### 构建发布版

```bash
flutter build windows --release
flutter build macos   --release
flutter build linux   --release
```

产物位置：

| 平台 | 产物 |
| --- | --- |
| Windows | `build\windows\x64\runner\Release\sub_converter.exe` |
| macOS | `build/macos/Build/Products/Release/Subtitle Converter.app` |
| Linux | `build/linux/x64/release/bundle/sub_converter` |

### 构建 Windows 安装包（MSI）

Windows 发布版可用 WiX Toolset v3 打成 per-machine x64 安装包（便携版 WiX，无需预装、构建
不需要管理员权限）：

```powershell
powershell -ExecutionPolicy Bypass -File packaging\msi\build-msi.ps1
```

该命令会执行 `flutter build windows --release`、抓取整个 Release 目录，并生成
`build\msi\sub-converter-<version>.msi`——单一自包含文件（CAB 已内嵌）。加 `-SkipBuild`
可复用已有 Release 产物；加 `-Version x.y.z` 可覆盖从 `pubspec.yaml` 读取的版本号。

安装包提供许可协议页、可自选安装目录（默认 `%ProgramFiles%\Subtitle Converter`）、可选的
开始菜单快捷方式（默认勾选）；会写入带应用图标的「添加/删除程序」条目，并用 `MajorUpgrade`
覆盖旧版本。详细说明、静默安装参数与打包内容见
[`packaging/msi/README.md`](packaging/msi/README.md)。

### 环境要求

`pubspec.yaml` 声明 `environment: sdk: ^3.13.3`，即需要 Dart 3.13.3（或更高的 3.x）SDK。
本项目在 Flutter 3.47.4 stable（Dart 3.13.3）上构建与测试，支持上表中的三个桌面目标平台。

## 转换流程

所有文件走同一条管线，不存任何「格式对格式」的专用转换：

```text
文件 -> 读字节 -> 解码字符集 -> 检测格式
     -> Parser -> SubtitleDocument -> Writer -> 编码 UTF-8 -> 写文件
```

先解决编码再检测格式，因为格式检测需要看解码后的文本；文件扩展名只作为辅助加分项。内容
明确是 SRT 的文件即使用 `.ass` 命名，也会按 SRT 处理。

默认输出到各源文件所在目录，扩展名取目标格式。若同名文件已存在则自动改名
（`E01.srt` -> `E01 (1).srt`）；源文件**永远**不是合法的输出路径：即使选择覆盖策略，当唯一
冲突就是源文件本身时也会退回改名。

## 选项

| 选项 | 取值 | 默认 |
| --- | --- | --- |
| 目标格式 | SRT、VTT、LRC、ASS、SSA、SBV | SRT |
| 输出位置 | 源文件所在目录，或指定目录 | 源文件所在目录 |
| 冲突策略 | 自动改名、覆盖、跳过 | 自动改名 |
| 时间偏移 | 带符号毫秒（可输入，或用 ±500 ms 步进，可重置） | 0 ms |
| 写入 UTF-8 BOM | 开 / 关 | 关 |
| 界面语言 | 跟随系统、English、简体中文 | 跟随系统 |
| 字体 | 跟随系统，或任意已安装字体 | 跟随系统 |

时间统一平移并在 0 处截断，因此负偏移不会产生负时间戳。覆盖策略会替换已存在的**输出**文件，
但仍拒绝替换源文件。设置项（目标格式、输出位置、指定目录、冲突策略、偏移、BOM、界面语言、
字体）通过 `shared_preferences` 持久化，下次启动恢复。

### 字体

应用默认使用各系统自己的界面字体——Windows 微软雅黑（YaHei UI）、macOS 苹方（PingFang）、
Linux 桌面环境当前选中的字体——而不是依赖引擎自带的字体回退，后者渲染中文时粗细不均。即便所
选字体缺字，CJK 回退链仍能兜底。选项面板中的「字体」下拉列出系统已安装字体（每项都以自身字
体预览）；选择会持久化。若所选字体之后被卸载（或在别的机器上不存在），界面回退到标准回退字体，
不会报错。

## 字符编码支持

输入：

| 编码 | 说明 |
| --- | --- |
| UTF-8 | 无 BOM；纯 ASCII 也走这里。 |
| UTF-8 with BOM | BOM 为权威依据，并从文本中剥离。 |
| UTF-16 LE / BE | 带或不带 BOM。无 BOM 时按 NUL 字节奇偶性猜测，并对无 NUL 字节的纯中文场景做额外判断。 |
| UTF-32 LE / BE | 带 BOM。 |
| GBK | |
| GB18030 | 含四字节序列，使用自带解码器。 |
| Shift-JIS | |
| EUC-JP | |
| Windows-1252 | 同时作为宽松的兜底读法。 |

输出始终为 UTF-8，可选带 BOM。

**传统编码检测是启发式的，不是统计式的。** BOM 绝对可信；否则先尝试严格 UTF-8，再逐个解码候选
传统编码并按产出的字符脚本打分，同分时取靠前的候选。GBK/GB18030 与 Shift-JIS 共享大量双字节
空间，GBK 汉字与 Shift-JIS 汉字无法从字形上区分，因此打分会偏向含假名的结果，并对两种编码
共用的字节区间扣分。实际后果是：短小或有歧义的文件仍可能被误判，单字节西文除非恰好是合法
UTF-8，否则按 Windows-1252 读取。检测失败会按文件报错，而不是猜一个结果。

## 测试

```bash
flutter test
```

当前共 **369 个测试，全部通过**。覆盖范围：

- **核心**：时间戳解析/格式化规则、统一模型（`SubtitleDocument`/`SubtitleCue`）、共享的行内标记扫描器。
- **各格式**：SRT、VTT、LRC、ASS、SSA、SBV 各自独立的 parser/writer 测试，使用真实 fixture（含中日文与含标签的文件）。
- **转换矩阵**：自动生成的 6x6 测试，把每个 fixture 转成每种格式，再用目标格式自己的 parser 回读，校验 cue 数量与起始时间漂移。
- **编码**：BOM 处理、UTF-16/UTF-32 检测、ASCII/中日文/SJIS/GBK/GB18030 用例、Windows-1252 兜底与失败行为。
- **路径与文件安全**：冲突策略与「绝不覆盖源文件」规则；批量转换、进度与单文件失败。
- **UI/控制器**：`AppController` 状态与持久化、主界面 widget 测试、界面语言与字体下拉，以及直接驱动窗口真实 `DropTarget` 回调的拖放测试（多文件拖入、拖入的文件夹展开为其中一级的字幕文件、空路径忽略、重复项合并）。
- **应用字体**：各平台默认字体、桌面字体覆盖、回退链、持久化，以及字体未安装时选择器的行为。
- **端到端**：用真实 `FileService` 与 `AppController` 操作磁盘上的真实文件，含完整的全格式矩阵。

## 跨平台验证

三个目标操作系统都在真实机器上通过 [`.github/workflows/ci.yml`](.github/workflows/ci.yml)
验证。每个 job 都会运行 `flutter analyze`、完整测试、release 构建，然后**启动产物并确认进程
仍然存活**，因此不会把「能编译」误当成「能运行」。

| 平台 | Runner | 测试 | Release 构建 | 启动 |
| --- | --- | --- | --- | --- |
| Windows | `windows-latest` | 346 通过 | `sub_converter.exe` | 是，12 秒后仍存活 |
| macOS | `macos-latest` | 346 通过 | `Subtitle Converter.app`（45.4 MB） | 是，12 秒后仍存活 |
| Linux | `ubuntu-latest` | 346 通过 | `sub_converter` bundle | 是，15 秒后仍存活 |

最近一次完整 CI 验证：commit `480c053`，CI run 34697190030，三个 job 全绿（346 个测试）。
系统字体相关的提交另在真实 Windows 机器上验证过（release 构建、MSI 安装、实机 UI 操作）；
推送最新提交、CI 跑完后，上表数字会刷新为当时的测试数。Linux job 在 `Xvfb` 下以
`LIBGL_ALWAYS_SOFTWARE=1` 启动，因为无头 runner 既没有显示器也没有 GPU。

有一处行为是**有意按平台区分**的，而且正是 CI 把它暴露出来的：路径去重**只在 Windows** 上
大小写不敏感（因为其文件系统如此）。在 macOS 与 Linux 上 `A.srt` 与 `a.srt` 确实是两个不同
文件，因此两条都会保留，而不是悄悄消失一条。

## 范围

v0.1 不做：

- 不做视频/音频处理，不做播放、预览、时间轴编辑。
- 不做 OCR、语音识别、翻译、字幕下载。
- 不做账号、云同步，代码中完全没有网络访问。
- 不集成 FFmpeg：不做封装、提取、烧录。
- 暂不支持输入/输出：MicroDVD、MPL2、TTML、SAMI、SCC、VobSub。

架构为后续格式留了扩展位：转换永远是
`源 -> Parser -> SubtitleDocument -> Writer -> 目标`，新增格式是「新增一个目录 + 一行注册」，
而不是为每个组合新增一个转换器。

## 新增一种格式

1. 在 `lib/models/subtitle_format.dart` 的 `SubtitleFormat` 枚举加一个值（label、扩展名、描述）。
2. 新建 `lib/formats/<name>/<name>_parser.dart`，实现 `SubtitleParser`。
3. 新建 `lib/formats/<name>/<name>_writer.dart`，实现 `SubtitleWriter`。
4. 新建 `lib/formats/<name>/<name>_format.dart`，导出一个 `FormatDescriptor`：parser/writer 工厂、
   内容指纹 `FormatSignature`、扩展名别名与能力开关（`supportsStyles`、`supportsInlineStyles`、
   `supportsPositions`、`requiresEndTime`）。
5. 把 descriptor 追加到 `lib/formats/built_in_formats.dart` 的 `builtInFormatDescriptors`。
6. 在 `test/fixtures/<name>/` 加 fixture，在 `test/formats/<name>_test.dart` 加测试；6x6 矩阵会自动带上新格式。

不需要改任何核心 switch，也不需要写两两组合的转换器。

## 目录结构

```text
lib/
  main.dart                     应用入口与根 widget。
  models/                       与格式无关的类型。
    subtitle_document.dart      SubtitleDocument、SubtitleMetadata。
    subtitle_cue.dart           SubtitleCue、InlineStyleRange、CuePosition。
    subtitle_style.dart         SubtitleStyle（原始字段映射）。
    subtitle_format.dart        SubtitleFormat 枚举。
    subtitle_codec.dart         SubtitleParser / SubtitleWriter 接口。
    format_descriptor.dart      FormatDescriptor（能力开关 + 工厂）。
    format_signature.dart       内容指纹与签名工厂。
    conversion_job.dart         选项、冲突/位置枚举、结果类型。
    subtitle_exception.dart     ConversionFailure 与异常类型。
  formats/
    built_in_formats.dart       六种格式唯一的注册列表。
    format_registry.dart        与格式无关的查找（按格式/扩展名）。
    srt/ vtt/ lrc/ ass/ ssa/ sbv/
                                每种格式一个 parser + writer + descriptor。
  services/
    file_service.dart           唯一的 IO 边界：读取、批处理、写出。
    encoding_service.dart       解码启发式与 UTF-8 编码。
    gb18030_codec.dart          自带 GB18030 解码器（含四字节）。
    format_detector.dart        内容 + 扩展名的加权检测。
    subtitle_converter.dart     Parse -> document -> write 核心。
    loss_analyzer.dart          报告不可避免的信息丢失。
    output_path_resolver.dart   输出命名与冲突规则。
    settings_store.dart         持久化接缝（shared_preferences）。
  screens/
    app_controller.dart         全部 UI 状态；委托给 FileService。
    home_screen.dart            单窗口、拖放目标与快捷键。
  widgets/                      头部、文件列表、选项面板、状态栏。
  i18n/                         文案表（en、zh）、AppLanguage，以及把文案交给
                                widget 的 StringsScope。
  platform/                     唯一的平台通道接缝：系统字体查询与各平台的
                                字体策略。
  utils/                        时间戳、行内标记、默认值。
test/
  core/ formats/ services/ platform/ widget/ integration/
                                单元、矩阵、路径、字体策略、UI 与端到端测试。
  fixtures/                     各格式的真实样例文件。
packaging/
  msi/                          Windows 安装包的 WiX v3 定义、构建脚本与资源；
                                详见其自带 README。
.github/workflows/ci.yml        Windows/macOS/Linux 三平台的测试、构建与启动检查。
docs/ARCHITECTURE.md            分层与数据流、模型、扩展点、有损策略与文件安全规则。
AGENTS.md                       开发规约，以及文档索引与各自的维护时机。
```

开发约定、以及每份文档「何时必须更新」，见 [`AGENTS.md`](AGENTS.md)。

## 隐私

所有处理都在本机应用内完成。代码中没有网络访问、没有遥测、没有上传路径：字幕内容从磁盘读入、
在内存中转换、再写回磁盘。任何数据都不会被发送到任何地方。
