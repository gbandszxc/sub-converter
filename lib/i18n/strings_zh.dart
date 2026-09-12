import 'app_strings.dart';

/// Simplified Chinese strings.
class AppStringsZh extends AppStrings {
  const AppStringsZh();

  @override
  String get appTitle => '字幕格式转换器';

  @override
  String get addFiles => '添加文件';

  @override
  String get clear => '清空列表';

  @override
  String get remove => '移除';

  @override
  String get targetFormat => '目标格式';

  @override
  String get output => '输出位置';

  @override
  String get outputSourceFolder => '源文件所在目录';

  @override
  String get outputCustomFolder => '指定目录';

  @override
  String get choose => '选择…';

  @override
  String get noFolderChosen => '未选择目录';

  @override
  String get chooseFolderError => '请选择输出目录。';

  @override
  String get conflict => '冲突处理';

  @override
  String get conflictAutoRename => '自动改名';

  @override
  String get conflictOverwrite => '覆盖';

  @override
  String get conflictSkip => '跳过';

  @override
  String get conflictAutoRenameHelp => '若同名文件已存在，写出带序号的新文件，不覆盖原文件。';

  @override
  String get conflictOverwriteHelp => '覆盖已存在的输出文件。';

  @override
  String get conflictSkipHelp => '保留已存在的输出文件，并跳过该条目。';

  @override
  String get timeOffset => '时间偏移';

  @override
  String get timeOffsetHint => '负值使字幕提前；时间戳在 0 处截断。';

  @override
  String get resetOffset => '重置偏移';

  @override
  String get writeBom => '写入 UTF-8 BOM';

  @override
  String get language => '界面语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '简体中文';

  @override
  String get font => '字体';

  @override
  String get fontSystemDefault => '跟随系统';

  @override
  String get fontSystemDefaultHelp =>
      '使用系统默认界面字体：Windows 微软雅黑、macOS 苹方、Linux 桌面当前字体；'
      '也可选择任意已安装字体。';

  @override
  String get convert => '开始转换';

  @override
  String convertWithCount(int count) => '转换 $count 个文件';

  @override
  String get emptyTitle => '把字幕文件拖到这里';

  @override
  String get emptySubtitle => '或点击「添加文件」选择文件';

  @override
  String get noFiles => '未添加文件';

  @override
  String fileCount(int count) => '$count 个文件';

  @override
  String get inspecting => '识别中…';

  @override
  String get ready => '待转换';

  @override
  String get converting => '转换中…';

  @override
  String convertedTo(String format) => '已转换为 $format';

  @override
  String get conversionFailed => '转换失败';

  @override
  String get skippedExisting => '已跳过：输出文件已存在';

  @override
  String renamedNote(String name) => '$name（已改名，原名被占用）';

  @override
  String get unknown => '未知';

  @override
  String get lossyNotice => '转换成功，但部分样式无法由目标格式表达。';

  @override
  String batchSummary({
    required int succeeded,
    required int failed,
    required int skipped,
    required int lossy,
  }) {
    final List<String> parts = <String>[
      if (succeeded > 0) '$succeeded 个成功',
      if (failed > 0) '$failed 个失败',
      if (skipped > 0) '$skipped 个已跳过',
    ];
    if (parts.isEmpty) {
      return '';
    }
    final String message = '${parts.join('，')}。';
    if (lossy == 0) {
      return message;
    }
    return '$message$lossy 个有样式丢失。';
  }

  @override
  String lossInlineStyles(String target) => '行内强调（加粗/斜体/下划线）无法由 $target 表达。';

  @override
  String lossPositions(String target) => '屏幕位置无法由 $target 表达。';

  @override
  String lossNamedStyles(String target) => '命名样式无法由 $target 表达。';

  @override
  String get lossLrcLineBreaks => 'LRC 不支持换行，多行字幕已合并为一行。';

  @override
  String get lossLrcEndTimes => 'LRC 不支持结束时间，结束时间已丢弃。';

  @override
  String lossInvertedCues(int count) => '$count 条字幕的结束时间早于开始时间，已按原样写出。';

  @override
  String get unsupportedFormat => '不支持的格式';

  @override
  String get encodingDetectionFailed => '字符编码识别失败';

  @override
  String get invalidSubtitleSyntax => '字幕语法无效';

  @override
  String get emptyDocument => '没有字幕条目';

  @override
  String get cannotWriteOutput => '无法写入输出文件';

  @override
  String get permissionDenied => '没有写入权限';

  @override
  String get targetPathUnavailable => '目标路径不可用';

  @override
  String get readFailed => '无法读取输入文件';

  @override
  String get filterSubtitleFiles => '字幕文件';

  @override
  String get filterAllFiles => '所有文件';

  @override
  String get formatSubRip => 'SubRip 字幕';

  @override
  String get formatWebVtt => 'WebVTT 字幕';

  @override
  String get formatLrc => 'LRC 歌词';

  @override
  String get formatAss => 'Advanced SubStation Alpha 字幕';

  @override
  String get formatSsa => 'SubStation Alpha 字幕';

  @override
  String get formatSbv => 'YouTube SBV 字幕';
}
