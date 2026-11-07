import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:q_pro/core/services/geo_stamp_service.dart';
import 'package:q_pro/core/services/photo_stamper.dart';

final _noon = DateTime(2026, 11, 5, 13, 30);

GeoStamp _at(double lat, double lng, {String? locality, String? region}) =>
    GeoStamp(
      localTime: _noon,
      networkTime: _noon,
      latitude: lat,
      longitude: lng,
      locality: locality,
      region: region,
    );

Placemark _place({String? locality, String? district, String? area}) =>
    Placemark(
      locality: locality,
      subAdministrativeArea: district,
      administrativeArea: area,
    );

void main() {
  group('coordinateLabel', () {
    test('renders degrees/minutes/seconds the way site photos are tagged', () {
      // 24.76057722 N, 93.90388083 E -> the Imphal reading on the sample
      // photo this stamp is modelled on.
      expect(
        _at(24.76057722, 93.90388083).coordinateLabel,
        '''24°45'38.078"N 93°54'13.971"E''',
      );
    });

    test('picks the hemisphere from the sign', () {
      final south = _at(-33.8688, -151.2093).coordinateLabel!;
      expect(south, contains('"S'));
      expect(south, contains('"W'));
      expect(south, isNot(contains('-')));
    });

    test('handles the equator and prime meridian as positive', () {
      expect(_at(0, 0).coordinateLabel, '''0°0'0.000"N 0°0'0.000"E''');
    });

    test('is null without a fix', () {
      final stamp = GeoStamp(
        localTime: _noon,
        networkTime: _noon,
        failure: GeoStampFailure.servicesOff,
      );
      expect(stamp.coordinateLabel, isNull);
      expect(stamp.hasLocation, isFalse);
    });
  });

  group('placeLabel', () {
    test('joins town and region', () {
      expect(
        _at(24.76, 93.90, locality: 'Imphal', region: 'Manipur').placeLabel,
        'Imphal, Manipur',
      );
    });

    test('falls back to whichever part came back', () {
      expect(_at(24.76, 93.90, region: 'Manipur').placeLabel, 'Manipur');
      expect(_at(24.76, 93.90, locality: 'Imphal').placeLabel, 'Imphal');
    });

    test('is null when reverse geocoding found nothing', () {
      expect(_at(24.76, 93.90).placeLabel, isNull);
      expect(_at(24.76, 93.90, locality: '', region: '').placeLabel, isNull);
    });
  });

  group('localityOf', () {
    test('prefers the locality when the geocoder has one', () {
      expect(localityOf(_place(locality: 'Imphal', district: 'Imphal West')),
          'Imphal');
    });

    test('falls back to the district, which is common outside cities', () {
      expect(localityOf(_place(district: 'Imphal West')), 'Imphal West');
      expect(localityOf(_place(locality: '', district: 'Imphal West')),
          'Imphal West');
    });

    test('is null rather than empty when neither is usable', () {
      expect(localityOf(null), isNull);
      expect(localityOf(_place()), isNull);
      expect(localityOf(_place(locality: '', district: '')), isNull);
    });
  });

  group('GeoStampFailure', () {
    test('offers settings only where settings can actually fix it', () {
      expect(GeoStampFailure.servicesOff.openSettingsHelps, isTrue);
      expect(GeoStampFailure.permissionDenied.openSettingsHelps, isTrue);
      expect(GeoStampFailure.permissionDeniedForever.openSettingsHelps, isTrue);
      // A fix that simply didn't arrive is worth retrying, not a settings trip.
      expect(GeoStampFailure.noFix.openSettingsHelps, isFalse);
    });

    test('every failure has a label to burn onto the photo', () {
      for (final failure in GeoStampFailure.values) {
        expect(failure.label, isNotEmpty);
      }
    });
  });

  group('networkTime', () {
    test('is independent of local time, so a skewed clock is visible', () {
      final stamp = GeoStamp(
        localTime: _noon,
        networkTime: _noon.add(const Duration(minutes: 7)),
        latitude: 24.76,
        longitude: 93.90,
      );
      expect(stamp.networkTime, isNot(stamp.localTime));
    });

    test('is null when NTP never answered', () {
      final stamp = GeoStamp(localTime: _noon, networkTime: null);
      expect(stamp.networkTime, isNull);
    });
  });

  group('gmtOffsetLabel', () {
    // `intl` has no ICU `O` pattern — it passes the letter through, so the
    // stamp used to read a literal "(O)" instead of the zone.
    test('renders a half-hour zone like India', () {
      final tz = DateTime.now().timeZoneOffset;
      final label = gmtOffsetLabel(DateTime.now());
      expect(label, startsWith('GMT'));
      expect(label, matches(RegExp(r'^GMT[+-]\d{2}:\d{2}$')));
      expect(label, isNot(contains('O')));
      // Agrees with the device's actual offset.
      final sign = tz.isNegative ? '-' : '+';
      final hours = tz.abs().inHours.toString().padLeft(2, '0');
      final minutes = (tz.abs().inMinutes % 60).toString().padLeft(2, '0');
      expect(label, 'GMT$sign$hours:$minutes');
    });
  });
}
