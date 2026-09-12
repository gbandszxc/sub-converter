# AGENTS.md — 开发与维护规约

面向在本仓库工作的 agent（和人类协作者）。**本文只做索引与约定**：项目是什么、命令在哪、
文档在哪、什么时候必须同步维护。

## 1. 项目一句话

纯 Flutter 桌面的本地字幕格式转换器（SRT / VTT / LRC / ASS / SSA / SBV 互转），核心是
纯 Dart，无网络、无外部进程、无后端。

## 2. 环境与常用命令

`flutter` 需在 `PATH` 上。约定版本：Flutter 3.47.4 stable / Dart 3.13.3（`pubspec.yaml`
要求 `sdk: ^3.13.3`）。

```bash
flutter pub get
flutter analyze                  # 必须 "No issues found!"（0 issue）
flutter test                     # 必须全绿；当前 369 个测试
flutter build windows --release  # 产物 build\windows\x64\runner\Release\
flutter build macos   --release
flutter build linux   --release
flutter run -d windows           # 开发调试
```

打 MSI（无需预装 WiX，首次自动下载便携版到 git 忽略目录）：

```powershell
powershell -ExecutionPolicy Bypass -File packaging\msi\build-msi.ps1
# 可选：-SkipBuild  -Version 0.2.0  -Configuration release  -FlutterExe <路径>
# 产物：build\msi\sub-converter-<version>.msi
```

三平台 CI（测试 + release 构建 + 启动产物）定义在 `.github/workflows/ci.yml`，push 到 `main`
即触发。

## 3. 硬性约定（改动前确认不会破坏）

| 约定 | 说明 | 由什么守住 |
|---|---|---|
| Parser / Writer 必须是纯 Dart | 不得 import Flutter、不得做 IO、不得 `print`；只做字符串进出 | `lib/models/subtitle_codec.dart` 的接口 + 审查 |
| UI 不含字幕知识 | `lib/screens`、`lib/widgets` 不得 import `formats/**`；转换只经 `FileService` | 审查（`grep -rn "formats/" lib/screens lib/widgets` 应为空） |
| 只有一个 IO 边界 | 文件读写与目录展开只在 `lib/services/file_service.dart`；其余地方不得读写磁盘（`lib/screens/app_controller.dart` 也 import 了 `dart:io`，但仅用于 `Platform.isWindows` 判断路径大小写） | 审查（`grep -rn "dart:io" lib/` 应只命中这两处） |
| 拖入的目录只展开一级 | 目录→字幕文件的展开只在 `FileService.expandPaths`：只取该目录的直接子文件，按注册表中的扩展名（含 alias）过滤，按文件名排序，不递归、不读文件内容；判定目录靠文件系统而不是拖放项的 `DropItem` 类型（Windows 上插件把目录当普通路径上报）；列目录失败必须静默返回已列出的部分 | `test/services/file_service_test.dart`、`test/widget/drag_drop_test.dart` |
| 平台通道只在 `lib/platform/` | 向 OS 查询系统字体（枚举 + 默认字体）走唯一的 `sub_converter/fonts` 通道：Dart 侧包装在 `lib/platform/system_fonts.dart`，策略（各平台默认字体与回退链）在纯 Dart 的 `lib/platform/app_typography.dart`，原生实现在三个 runner 内。查询失败必须静默降级到策略默认值，不得抛出 | `test/platform/app_typography_test.dart`、`test/widget/font_settings_test.dart` |
| 绝不修改源文件 | `OutputPathResolver` 在任何策略下都拒绝把源文件当输出路径（含 overwrite） | `test/services/output_path_resolver_test.dart` |
| 输出恒为 UTF-8（可选 BOM） | 不提供其他输出编码 | `test/services/file_service_test.dart` |
| 时间只用 `Duration` | 不得把格式化时间戳当内部表示 | `lib/models/subtitle_cue.dart` |
| 时间戳解析/格式化只有一份 | 所有格式必须用 `lib/utils/timestamp.dart` | 10 个 parser/writer 均 import 它 |
| LRC 时序默认值只有一个来源 | 5 秒兜底只在 `lib/utils/subtitle_defaults.dart` | 审查 |
| 不新增成对转换器 | 必须 `源 -> Parser -> SubtitleDocument -> Writer -> 目标` | 审查（格式目录之间不得互相 import） |
| ASS/SSA 共用一份实现 | 只有 `lib/formats/ass/` 有逻辑，`ssa/` 是 dialect 包装 | 审查 |
| 控制标签不得留在可见文本里 | `{\an8}{\bord2}Hello` 必须变成 `Hello` | `test/core/markup_regression_test.dart`、`test/formats/ass_test.dart` |
| 检测不能只看扩展名 | 内容优先，扩展名只是加分项 | `test/services/conversion_matrix_test.dart` |
| 无网络、无外部进程 | 不得引入 ffmpeg / Python / Node / HTTP 调用 | 审查 + 依赖白名单 |
| 只做 v0.1 范围 | 不加入播放、预览、OCR、翻译、下载、账号、云同步等 | README「范围」段 |
| 注释用英文 | 代码与脚本注释用英文；面向用户的文档中英各一份；提交信息描述可用中文或英文（本仓库历史两者都有） | 审查 |
| 界面文案必须双语齐备 | 新增/修改任何用户可见文案，必须同时改 `lib/i18n/strings_en.dart` 与 `strings_zh.dart`；基类是抽象类，漏翻即编译错误 | `test/i18n/strings_test.dart`（另查空串、查中文误留英文） |
| 纯层不得依赖 i18n | `lib/models`、`lib/formats`、`lib/services` 不得 import `lib/i18n` 或 `package:flutter`；模型/服务只产出枚举等结构（如 `LossKind`、`ConversionFailure`），句子由 UI 组装 | 审查（`grep -rn "i18n/\|package:flutter" lib/models lib/formats lib/services` 应为空） |
| 语言设置默认跟随系统 | 新增用户可见设置项时，默认值应最少惊讶；语言默认 `AppLanguage.system`，持久化键 `language` | `test/i18n/localization_widget_test.dart` |
| 不提交构建产物 | `build/`、`packaging/msi/.tools/`、`packaging/msi/.build/` 已 gitignore | `.gitignore` |
| MSI 开始菜单必须用 `ProgramMenuFolder` | 它是 MSI 的系统文件夹属性（per-machine 时解析到 all-users 开始菜单）；`CommonProgramsFolder` **不是** MSI 属性，会被静默回退到 `TARGETDIR` | `packaging/msi/Product.wxs` 注释 + 安装日志（`/l*v`） |
| 同版本重装必须能覆盖旧文件 | `MajorUpgrade` 必须带 `AllowSameVersionUpgrades="yes"`：exe/dll 的文件版本跟 pubspec 版本走，不带它时重装同版本 MSI 会保留旧版本文件（尤其 `sub_converter.exe`），并在控制面板重复注册产品 | `packaging/msi/Product.wxs` 注释 + `packaging/msi/README.md` 安装行为 |
| WiX 告警要么修要么写清理由 | `-sreg` 关掉 DLL self-reg 探测；ICE60 因 `MaterialIcons-Regular.otf` 是 Flutter 资源、**不该**注册为系统字体而有意抑制 | `packaging/msi/build-msi.ps1` 注释 |

**提交信息**：conventional commits（`feat(formats):` / `fix(services):` / `test(ui):` /
`docs:` / `build(msi):` / `chore:`），一个任务一个提交；长流程分批提交，不要最后攒一块。

## 4. 文档地图与同步义务

### 4.1 必须与代码同步维护（漂移会误导用户或后续 agent）

| 文档 | 内容 | 何时必须更新 |
|---|---|---|
| [`README.md`](README.md) / [`README.zh-CN.md`](README.zh-CN.md) | 面向用户：支持的格式与各格式「保留/丢弃」清单、使用与构建、MSI、选项、编码、测试数量、跨平台验证结果、范围 | 功能增删、选项或默认值变化、构建/打包方式变化、**测试数量变化**、某格式的保留/丢弃清单变化、SDK 或依赖要求变化、跨平台验证结果变化 |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | 分层与数据流、模型、扩展点、有损转换策略、文件安全规则、有意保留的 v0.1 简化项 | 模块边界或分层变化、新增服务或格式、模型字段变化、文件安全规则变化、简化项增减 |
| [`packaging/msi/README.md`](packaging/msi/README.md) | MSI 构建方式与参数、**打包内容**、安装行为、静默安装 | 打包内容变化（新增 DLL/目录/插件）、脚本参数变化、安装行为变化（安装范围、快捷方式默认值）、WiX 版本变化 |
| [`packaging/msi/license.rtf`](packaging/msi/license.rtf) | 安装包许可页文本（当前为占位） | **对外分发前必须替换为真实 EULA**；内置第三方组件变化时同步说明 |
| `AGENTS.md`（本文件） | 开发规约、命令、硬性约定、文档地图 | 命令变化、测试数量变化、新增或移动文档（索引要同步）、新增硬性约定 |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | 三平台测试/构建/启动检查 | 支持平台、Flutter 版本、构建或启动检查步骤变化 |

> 约定：文档里出现的数字与清单，宁可从代码/命令抄，也不要凭记忆写。

## 5. 容易漂移的具体事实（改代码时顺手核对）

这些是「同一事实被写在多处」的高风险项：

1. **测试数量** —— 出现在 `README.md`、`README.zh-CN.md`、`AGENTS.md` 第 2 节。
   校验：`flutter test` 结尾行的数字。
2. **每格式的保留/丢弃清单** —— 两份 README 的表 + 各 writer 的 doc comment。
   校验：读 `lib/formats/*/*_writer.dart` 顶部注释。
3. **Release 目录内容 / 打包内容** —— 两份 README、`packaging/msi/README.md`。
   校验：`flutter build windows --release` 后 `ls build/windows/x64/runner/Release`。
4. **版本号** —— `pubspec.yaml` 的 `version:`（MSI 版本由脚本从此解析，必须是 `x.y.z`）。
5. **平台相关行为**（Windows 大小写不敏感去重；macOS/Linux 视为两个文件）—— 两份 README、
   `docs/ARCHITECTURE.md`。校验：`test/widget/app_controller_test.dart`。
6. **编码候选清单** —— 两份 README 的编码表与 `EncodingService.legacyEncodingNames`。
7. **已注册格式** —— `SubtitleFormat` 枚举与 `lib/formats/built_in_formats.dart` 必须一致（6 种）。
8. **界面文案** —— 两份 README 只描述功能，具体文案以 `lib/i18n/strings_*.dart` 为准；新增语言时
   `AppLanguage`、`resolve()`、文案表与语言下拉三处都要改，并同步 `supportedLocales`。
9. **默认字体清单**（Windows 微软雅黑 / macOS 苹方 / Linux 桌面字体，及 CJK 回退链）—— 两份
   README 的「字体」段与 `lib/platform/app_typography.dart`；原生查询实现在三个 runner，见
   `docs/ARCHITECTURE.md` 的 System fonts 段。校验：`test/platform/app_typography_test.dart`。
10. **拖入目录的行为**（只展开一级、按已注册扩展名过滤、不递归）—— 两份 README 的使用段与测试
    覆盖段、`docs/ARCHITECTURE.md` 的 Input resolution 段、`lib/services/file_service.dart` 的
    `expandPaths` doc comment。校验：`test/services/file_service_test.dart`。

## 6. 提交前自检

```bash
flutter analyze   # 0 issue
flutter test      # 全绿（当前 369）
```

- [ ] 若改动用户可见行为 → 更新两份 README；涉及打包 → 更新 `packaging/msi/README.md`
- [ ] 若新增/删除测试 → 同步三处测试数量
- [ ] 若新增格式 → 枚举 + parser + writer + descriptor + 一行注册 + fixtures + 测试，并核对两份 README 的格式表
- [ ] 若改动打包布局 → 重跑 `build-msi.ps1`，并用 `msiexec /a` 或 `dark.exe` 核对 MSI 文件表
- [ ] 提交信息符合 conventional commits，且按任务分批提交
