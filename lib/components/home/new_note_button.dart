import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:saber/components/navbar/bottom_navbar.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/images_to_pdf.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

class NewNoteButton extends StatefulWidget {
  const new({super.key, required this.cupertino, this.path});

  final bool cupertino;
  final String? path;

  @override
  State<NewNoteButton> createState() => _NewNoteButtonState();
}

class _NewNoteButtonState extends State<NewNoteButton> {
  final ValueNotifier<bool> isDialOpen = ValueNotifier(false);

  /// Whether a file import (which may take a while for images) is in progress.
  var _isImporting = false;

  /// Image file extensions that can be converted into a PDF.
  /// Taken from https://github.com/brendan-duncan/image/blob/main/doc/formats.md
  /// (note: .svg is not included because the `image` package can't decode it)
  static const _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.tiff',
    '.tif',
    '.webp',
    '.tga',
    '.ico',
    '.psd',
    '.exr',
    '.pvr',
  };

  @override
  Widget build(BuildContext context) {
    const materialBorderRadius = BorderRadius.all(.circular(16));
    return SpeedDial(
      spacing: 3,
      mini: true,
      openCloseDial: isDialOpen,
      childPadding: const .all(5),
      spaceBetweenChildren: 4,
      switchLabelPosition: Directionality.of(context) == .rtl,
      shape: widget.cupertino
          ? const CircleBorder()
          : const RoundedRectangleBorder(borderRadius: materialBorderRadius),
      dialRoot: (context, open, toggleChildren) {
        final platform = Theme.of(context).platform;
        return GlassyContainer(
          height: 56,
          borderRadius: platform.isCupertino ? null : materialBorderRadius,
          child: AspectRatio(
            aspectRatio: 1,
            child: IconButton(
              onPressed: toggleChildren,
              tooltip: t.home.tooltips.newNote,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                padding: .zero,
                shape: platform.isCupertino
                    ? const CircleBorder()
                    : const RoundedRectangleBorder(
                        borderRadius: materialBorderRadius,
                      ),
              ),
              icon: const Center(child: Icon(Icons.add)),
            ),
          ),
        );
      },
      children: [
        SpeedDialChild(
          child: const Icon(Icons.create),
          label: t.home.create.newNote,
          onTap: () async {
            if (widget.path == null) {
              context.push(RoutePaths.edit);
            } else {
              final newFilePath = await FileManager.newFilePath(
                '${widget.path}/',
              );
              if (!context.mounted) return;
              context.push(RoutePaths.editFilePath(newFilePath));
            }
          },
        ),
        SpeedDialChild(
          child: const Icon(Icons.note_add),
          label: t.home.create.importNote,
          onTap: () async {
            if (_isImporting) return;

            final files = await FilePicker.pickFiles(type: FileType.any);
            if (files.isEmpty) return;

            if (!mounted) return;
            _isImporting = true;
            try {
              await _importNote(files);
            } finally {
              _isImporting = false;
            }
          },
        ),
      ],
    );
  }

  Future<void> _importNote(List<PlatformFile> files) async {
    final extensions = [
      for (final file in files) p.extension(file.path ?? file.name).toLowerCase(),
    ];

    final allImages =
        extensions.isNotEmpty &&
        extensions.every(_imageExtensions.contains);

    if (allImages) {
      await _importImages(files);
      return;
    }

    // Anything other than images must be a single note/archive/pdf file.
    final filePath = files.first.path;
    if (files.length != 1 || filePath == null) {
      _showInvalidFormat();
      return;
    }

    final extension = extensions.first;
    if (extension == '.sbn' || extension == '.sbn2' || extension == '.sba') {
      final path = await FileManager.importFile(
        filePath,
        '${widget.path ?? ''}/',
      );
      if (path == null) return;
      if (!mounted) return;

      context.push(RoutePaths.editFilePath(path));
    } else if (extension == '.pdf') {
      if (!Editor.canRasterPdf) return;
      if (!mounted) return;

      final fileNameWithoutExtension = p.basenameWithoutExtension(filePath);
      final sbnFilePath = await FileManager.suffixFilePathToMakeItUnique(
        '${widget.path ?? ''}/$fileNameWithoutExtension',
      );
      if (!mounted) return;

      context.push(RoutePaths.editImportPdf(sbnFilePath, filePath));
    } else {
      _showInvalidFormat();
    }
  }

  /// Converts the selected [images] (in selection order) into a single PDF
  /// and creates a new note from it.
  Future<void> _importImages(List<PlatformFile> images) async {
    if (!Editor.canRasterPdf) return;

    // Read all images first, preserving the selection order.
    final imageBytes = <Uint8List>[];
    for (final file in images) {
      imageBytes.add(await file.readAsBytes());
    }
    if (!mounted) return;

    if (!stows.maxImageSize.loaded) {
      await stows.maxImageSize.waitUntilRead();
    }

    final Uint8List pdfBytes;
    try {
      pdfBytes = await ImagesToPdf.convert(
        imageBytes,
        maxImageSize: stows.maxImageSize.value,
      );
    } catch (e, st) {
      debugPrint('Failed to convert images to PDF: $e\n$st');
      _showInvalidFormat();
      return;
    }
    if (pdfBytes.isEmpty) {
      _showInvalidFormat();
      return;
    }
    if (!mounted) return;

    final fileNameWithoutExtension = p.basenameWithoutExtension(
      images.first.path ?? images.first.name,
    );
    final sbnFilePath = await FileManager.suffixFilePathToMakeItUnique(
      '${widget.path ?? ''}/$fileNameWithoutExtension',
    );
    if (!mounted) return;

    // The PDF is passed as bytes so we don't have to write a temp file.
    context.push(RoutePaths.editFilePath(sbnFilePath), extra: pdfBytes);
  }

  void _showInvalidFormat() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(t.home.invalidFormat)));
  }
}
