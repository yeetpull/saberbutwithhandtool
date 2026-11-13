import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as im;
import 'package:logging/logging.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Converts a list of images into a single PDF, with one image per page.
///
/// This is used to import photos as a new note: the images are embedded into
/// the note as a PDF so that the existing (lazy, PDF-based) image pipeline can
/// be used, instead of embedding every image at full resolution.
abstract class ImagesToPdf {
  static final log = Logger('ImagesToPdf');

  /// Converts [images] (in the given order) into a single PDF.
  ///
  /// Each image is downscaled so that its longest side is at most
  /// [maxImageSize] pixels (a value of 0 or less disables downscaling), then
  /// encoded as PNG if it has transparency, or JPEG otherwise.
  ///
  /// The work runs in a separate isolate so the UI stays responsive.
  static Future<Uint8List> convert(
    List<Uint8List> images, {
    required double maxImageSize,
  }) {
    return Isolate.run(() => _convert(images, maxImageSize));
  }
}

Future<Uint8List> _convert(
  List<Uint8List> images,
  double maxImageSize,
) async {
  final pdf = pw.Document(compress: true);

  for (final bytes in images) {
    final decoded = im.decodeImage(bytes);
    if (decoded == null) {
      ImagesToPdf.log.warning(
        'Skipping image: could not decode ${bytes.length} bytes',
      );
      continue;
    }

    final image = _downscale(decoded, maxImageSize);
    final encoded = image.hasAlpha
        ? im.encodePng(image)
        : im.encodeJpg(image, quality: 85);

    // Use the image's pixel dimensions as the page size in points, so the
    // page has the same aspect ratio as the image.
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          image.width.toDouble(),
          image.height.toDouble(),
        ),
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Center(
          child: pw.Image(pw.MemoryImage(encoded), fit: pw.BoxFit.contain),
        ),
      ),
    );
  }

  return pdf.save();
}

/// Returns [image] downscaled so its longest side is at most [maxSize] pixels.
im.Image _downscale(im.Image image, double maxSize) {
  final longestSide = image.width > image.height
      ? image.width
      : image.height;
  if (maxSize <= 0 || longestSide <= maxSize) return image;

  final scale = maxSize / longestSide;
  return im.copyResize(
    image,
    width: (image.width * scale).round(),
    height: (image.height * scale).round(),
    interpolation: im.Interpolation.cubic,
  );
}
