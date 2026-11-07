import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:q_pro/core/services/geo_stamp_service.dart';
import 'package:q_pro/core/services/photo_stamper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stampPhoto writes a valid JPEG of the same size', () async {
    final dir = Directory.systemTemp.createTempSync('stamp');
    addTearDown(() => dir.deleteSync(recursive: true));

    final source = File('${dir.path}/photo.jpg');
    final original = img.Image(width: 400, height: 300);
    img.fill(original, color: img.ColorRgb8(20, 90, 160));
    await source.writeAsBytes(img.encodeJpg(original));

    final stamped = await stampPhoto(
      source,
      GeoStamp(
        localTime: DateTime(2026, 11, 5, 13, 30),
        networkTime: DateTime(2026, 11, 5, 13, 30, 2),
        latitude: 24.76057722,
        longitude: 93.90388083,
        locality: 'Imphal',
        region: 'Manipur',
      ),
    );

    expect(stamped.path, isNot(source.path), reason: 'original must survive');
    expect(source.existsSync(), isTrue);

    final out = img.decodeJpg(await stamped.readAsBytes());
    expect(out, isNotNull);
    expect(out!.width, 400);
    expect(out.height, 300);

    // The band is drawn across the bottom, so the bottom strip must differ from
    // the flat fill while the top is untouched.
    expect(out.getPixel(10, 10).b, greaterThan(100), reason: 'top unchanged');
    expect(out.getPixel(10, 290).b, lessThan(100), reason: 'band darkened');
  });
}
