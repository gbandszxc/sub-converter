import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/subtitle_format.dart';
import '../widgets/app_header.dart';
import '../widgets/file_list_view.dart';
import '../widgets/options_panel.dart';
import '../widgets/status_bar.dart';
import '../widgets/ui_constants.dart';
import 'app_controller.dart';

/// The single application window.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _dragging = false;

  AppController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyO, control: true):
            _pickFiles,
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _convert,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: DropTarget(
            onDragEntered: (_) => _setDragging(true),
            onDragExited: (_) => _setDragging(false),
            onDragDone: _onDropDone,
            child: ListenableBuilder(
              listenable: _controller,
              builder: (BuildContext context, Widget? child) =>
                  _window(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _window(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      foregroundDecoration: _dragging
          ? BoxDecoration(border: Border.all(color: scheme.primary, width: 2))
          : null,
      child: Column(
        children: <Widget>[
          AppHeader(controller: _controller, onAddFiles: _pickFiles),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: <Widget>[
                Expanded(child: FileListView(controller: _controller)),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: AppSpacing.optionsPanelWidth,
                  child: OptionsPanel(
                    controller: _controller,
                    onChooseDirectory: _chooseDirectory,
                    onConvert: _convert,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          StatusBar(controller: _controller),
        ],
      ),
    );
  }

  void _setDragging(bool value) {
    if (_dragging != value) {
      setState(() => _dragging = value);
    }
  }

  void _onDropDone(DropDoneDetails details) {
    _setDragging(false);
    final Iterable<String> paths = details.files
        .where((DropItem item) => item is! DropItemDirectory)
        .map((DropItem item) => item.path)
        .where((String path) => path.isNotEmpty);
    _controller.addPaths(paths);
  }

  Future<void> _pickFiles() async {
    try {
      final List<XFile> files = await openFiles(
        acceptedTypeGroups: _typeGroups,
      );
      if (files.isEmpty) {
        return;
      }
      await _controller.addPaths(files.map((XFile file) => file.path));
    } catch (_) {
      // The platform dialog is unavailable; nothing to do.
    }
  }

  Future<void> _chooseDirectory() async {
    try {
      final String? directory = await getDirectoryPath();
      if (directory != null && directory.isNotEmpty) {
        _controller.setOutputDirectory(directory);
      }
    } catch (_) {
      // The platform dialog is unavailable; nothing to do.
    }
  }

  void _convert() {
    _controller.convertAll();
  }

  List<XTypeGroup> get _typeGroups => <XTypeGroup>[
    XTypeGroup(
      label: 'Subtitle files',
      extensions: SubtitleFormat.values
          .map((SubtitleFormat format) => format.extension)
          .toList(),
    ),
    const XTypeGroup(label: 'All files'),
  ];
}
