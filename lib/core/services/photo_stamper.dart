import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import 'geo_stamp_service.dart';

/// JPEG quality for the re-encoded photo. `image_picker` already shot at
/// quality 70, so going higher here only grows the file without
/// recovering detail it never had.
const _jpegQuality = 85;

/// Font size is a fraction of image *height* rather than width, so the
/// band reads the same in portrait and landscape, and is clamped so it
/// stays legible on a small photo without turning into a billboard on a
/// large one.
const _fontScale = 0.018;
const _minFontSize = 18.0;
const _maxFontSize = 42.0;

/// Both as multiples of the font size, so the band stays in proportion to
/// its text once the clamp kicks in.
const _padScale = 0.7;
const _lineSpacing = 1.35;

final _timeFormat = DateFormat('d MMM yyyy h:mm:ss a');

/// "GMT+05:30". Built by hand because `intl` does not implement the ICU
/// `O` pattern — it passes the letter straight through, so a format string
/// using it stamps a literal "(O)" onto the photo.
String gmtOffsetLabel(DateTime time) {
  final offset = time.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final hours = offset.abs().inHours.toString().padLeft(2, '0');
  final minutes = (offset.abs().inMinutes % 60).toString().padLeft(2, '0');
  return 'GMT$sign$hours:$minutes';
}

String _stampTime(DateTime time) =>
    '${_timeFormat.format(time)} (${gmtOffsetLabel(time)})';

/// Burns [stamp] onto [source] as a band across the bottom and returns a
/// new file; the original is left alone.
///
/// Rendering goes through a `dart:ui` Canvas rather than the `image`
/// package so the text uses a real font with proper shaping — `image`
/// only draws bitmap fonts, which looks crude at photo resolution. The
/// result comes back out as raw RGBA and is re-encoded to JPEG, because
/// `dart:ui` can only write PNG and a lossless photo would be many times
/// the size.
Future<File> stampPhoto(File source, GeoStamp stamp) async {
  final bytes = await source.readAsBytes();
  final frame = await (await ui.instantiateImageCodec(bytes)).getNextFrame();
  final photo = frame.image;

  final pixelWidth = photo.width;
  final pixelHeight = photo.height;
  final width = pixelWidth.toDouble();
  final height = pixelHeight.toDouble();

  final fontSize = (height * _fontScale).clamp(_minFontSize, _maxFontSize);
  final padding = fontSize * _padScale;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImage(photo, ui.Offset.zero, ui.Paint());

  final painters = _linePainters(stamp, width, fontSize, padding);
  final textHeight = painters.fold<double>(
    0,
    (total, p) => total + p.height * _lineSpacing,
  );
  final bandHeight = textHeight + padding * 2;

  // A translucent band rather than a solid one: it keeps the text legible
  // without hiding whatever the photo shows at the bottom of the frame.
  canvas.drawRect(
    ui.Rect.fromLTWH(0, height - bandHeight, width, bandHeight),
    ui.Paint()..color = const Color(0xCC000000),
  );

  var dy = height - bandHeight + padding;
  for (final painter in painters) {
    painter.paint(canvas, ui.Offset(padding, dy));
    dy += painter.height * _lineSpacing;
  }

  final stamped = await recorder.endRecording().toImage(
        pixelWidth,
        pixelHeight,
      );
  final rgba = await stamped.toByteData(format: ui.ImageByteFormat.rawRgba);
  photo.dispose();
  stamped.dispose();

  if (rgba == null) return source;

  final encoded = img.encodeJpg(
    img.Image.fromBytes(
      width: pixelWidth,
      height: pixelHeight,
      bytes: rgba.buffer,
      numChannels: 4,
    ),
    quality: _jpegQuality,
  );

  final target = File(
    '${source.parent.path}/stamped_${source.uri.pathSegments.last}',
  );
  await target.writeAsBytes(encoded, flush: true);
  return target;
}

/// The stamp's lines, in reading order, already laid out.
///
/// Network time is shown above local time whenever it could be checked:
/// a device clock can be set to anything, so the pair is what makes the
/// timestamp worth trusting. With no network, only the local line appears
/// rather than a network time the app couldn't verify.
List<TextPainter> _linePainters(
  GeoStamp stamp,
  double width,
  double fontSize,
  double padding,
) {
  final lines = <(String, bool)>[
    if (stamp.coordinateLabel != null) (stamp.coordinateLabel!, true),
    if (stamp.placeLabel != null) (stamp.placeLabel!, false),
    if (stamp.failure != null) (stamp.failure!.label, false),
    if (stamp.networkTime != null)
      ('Network: ${_stampTime(stamp.networkTime!)}', false),
    ('Local: ${_stampTime(stamp.localTime)}', false),
  ];

  return [
    for (final (text, emphasised) in lines)
      TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: const Color(0xFFFFFFFF),
            fontSize: emphasised ? fontSize * 1.1 : fontSize,
            fontWeight: emphasised ? FontWeight.w600 : FontWeight.w400,
            // Deliberately the platform default rather than the app's
            // Sora: this runs at capture time, and GoogleFonts may need a
            // network fetch the device doesn't have.
            height: 1.2,
            shadows: const [
              Shadow(blurRadius: 3, color: Color(0xFF000000)),
            ],
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: width - padding * 2),
  ];
}
