import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ntp/ntp.dart';

/// Why a stamp carries no coordinates. Drives both the line burned onto
/// the photo and which recovery action is worth offering the user.
enum GeoStampFailure {
  servicesOff,
  permissionDenied,
  permissionDeniedForever,
  noFix;

  String get label => switch (this) {
        servicesOff => 'Location is off',
        permissionDenied => 'Location permission denied',
        permissionDeniedForever => 'Location permission denied',
        noFix => 'Location unavailable',
      };

  /// Whether the user can fix this from system settings. A missed fix is
  /// just bad luck — retrying is the only useful move.
  bool get openSettingsHelps => this != noFix;
}

/// What gets burned onto a photo.
///
/// Both times are computed at capture, never cached: a stamp has to say
/// when the photo was taken, not when the location happened to be read.
/// [networkTime] comes from an NTP offset applied to the device clock, so
/// it stays right even if the clock has been changed — a lone local time
/// would be trivially forgeable.
@immutable
class GeoStamp {
  const GeoStamp({
    required this.localTime,
    required this.networkTime,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.locality,
    this.region,
    this.failure,
  });

  final DateTime localTime;

  /// Device clock corrected by the NTP offset, or null if NTP never
  /// answered — in which case the stamp shows the local time alone.
  final DateTime? networkTime;

  final double? latitude;
  final double? longitude;
  final double? accuracy;

  /// Town or city. Falls back to the district when the geocoder has no
  /// locality, which is common outside dense urban areas.
  final String? locality;

  /// State or province, e.g. "Manipur".
  final String? region;

  final GeoStampFailure? failure;

  bool get hasLocation => latitude != null && longitude != null;

  /// "24°45'38.078\"N 93°54'13.971\"E", or null without a fix.
  String? get coordinateLabel {
    if (!hasLocation) return null;
    return '${_dms(latitude!, 'N', 'S')} ${_dms(longitude!, 'E', 'W')}';
  }

  /// "Imphal, Manipur" — whichever parts came back.
  String? get placeLabel {
    final parts = [locality, region].where((p) => p != null && p.isNotEmpty);
    return parts.isEmpty ? null : parts.join(', ');
  }
}

/// Town name for a geocoded place: its locality where there is one, else
/// the district.
///
/// Outside dense urban areas the geocoder routinely returns an empty
/// locality; falling through to `subAdministrativeArea` still tells an
/// approver roughly where a photo came from instead of showing nothing.
String? localityOf(Placemark? place) {
  if (place == null) return null;
  final locality = place.locality;
  if (locality != null && locality.isNotEmpty) return locality;
  final district = place.subAdministrativeArea;
  return (district != null && district.isNotEmpty) ? district : null;
}

/// Degrees/minutes/seconds, the convention geotagged site photos use.
String _dms(double value, String positive, String negative) {
  final hemisphere = value >= 0 ? positive : negative;
  final absolute = value.abs();
  final degrees = absolute.floor();
  final minutesFull = (absolute - degrees) * 60;
  final minutes = minutesFull.floor();
  final seconds = (minutesFull - minutes) * 60;
  return "$degrees°$minutes'${seconds.toStringAsFixed(3)}\"$hemisphere";
}

/// Where the device was, and how far off its clock is. Held between a
/// [PhotoStampService.prewarm] and the capture that follows.
@immutable
class _Reading {
  const _Reading({required this.readAt, this.position, this.place, this.failure});

  final DateTime readAt;
  final Position? position;
  final Placemark? place;
  final GeoStampFailure? failure;
}

/// Supplies the location half of a photo stamp, warmed up ahead of time.
///
/// A cold GPS fix plus reverse geocoding can take several seconds, which
/// is a long time to stare at a camera button. [prewarm] starts that work
/// when a screen that can take photos opens, so [capture] usually has an
/// answer waiting.
class PhotoStampService {
  PhotoStampService._();

  static final PhotoStampService instance = PhotoStampService._();

  /// Short enough that the stamp can't show somewhere the user has since
  /// walked away from.
  static const _freshFor = Duration(seconds: 60);

  static const _fixTimeout = Duration(seconds: 5);
  static const _geocodeTimeout = Duration(seconds: 4);
  static const _ntpTimeout = Duration(seconds: 3);

  _Reading? _reading;
  Future<_Reading>? _inFlight;

  /// Offset between network time and this device's clock. Stored as an
  /// offset rather than a timestamp so it stays valid as time passes.
  Duration? _ntpOffset;
  Future<void>? _ntpInFlight;

  /// Starts a fix, reverse geocode and NTP sync in the background. Safe
  /// to call repeatedly — a warm reading or an in-flight one is reused.
  void prewarm() {
    _syncNtp();
    if (_isFresh(_reading) || _inFlight != null) return;
    // Nothing awaits this; capture() picks the result up.
    unawaited(_startReading().catchError((_) => _failed(GeoStampFailure.noFix)));
  }

  /// Resets warmed state. Tests only.
  @visibleForTesting
  void resetForTesting() {
    _reading = null;
    _inFlight = null;
    _ntpOffset = null;
    _ntpInFlight = null;
  }

  /// A stamp for a photo being taken right now.
  ///
  /// Uses a warm reading when there is one, otherwise joins whatever
  /// [prewarm] already started, otherwise fetches from cold. Never throws.
  Future<GeoStamp> capture() async {
    _Reading reading;
    if (_isFresh(_reading)) {
      reading = _reading!;
    } else {
      try {
        reading = await (_inFlight ?? _startReading());
      } catch (_) {
        reading = _failed(GeoStampFailure.noFix);
      }
    }

    // Both times belong to this moment, not to when the reading was taken.
    final now = DateTime.now();
    final position = reading.position;

    return GeoStamp(
      localTime: now,
      networkTime: _ntpOffset == null ? null : now.add(_ntpOffset!),
      latitude: position?.latitude,
      longitude: position?.longitude,
      accuracy: position?.accuracy,
      locality: localityOf(reading.place),
      region: reading.place?.administrativeArea,
      failure: position == null ? (reading.failure ?? GeoStampFailure.noFix) : null,
    );
  }

  bool _isFresh(_Reading? reading) =>
      reading != null &&
      DateTime.now().difference(reading.readAt) < _freshFor &&
      reading.position != null;

  _Reading _failed(GeoStampFailure failure) =>
      _Reading(readAt: DateTime.now(), failure: failure);

  Future<_Reading> _startReading() {
    final future = _read();
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<_Reading> _read() async {
    final denial = await _permissionProblem();
    if (denial != null) {
      return _reading = _failed(denial);
    }

    // A last-known position is instant and usually close enough to
    // geocode against, so the fresh fix and the place name can be chased
    // at the same time instead of one after the other.
    final lastKnown = await _lastKnown();

    final fixFuture = _freshFix(lastKnown);
    final placeFuture = lastKnown == null
        ? Future<Placemark?>.value()
        : _placemark(lastKnown);

    final position = await fixFuture;
    var place = await placeFuture;

    // No last-known to geocode against, so geocode what we just got.
    if (place == null && position != null) {
      place = await _placemark(position);
    }

    return _reading = _Reading(
      readAt: DateTime.now(),
      position: position,
      place: place,
      failure: position == null ? GeoStampFailure.noFix : null,
    );
  }

  Future<GeoStampFailure?> _permissionProblem() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return GeoStampFailure.servicesOff;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return switch (permission) {
        LocationPermission.denied => GeoStampFailure.permissionDenied,
        LocationPermission.deniedForever =>
          GeoStampFailure.permissionDeniedForever,
        _ => null,
      };
    } catch (_) {
      return GeoStampFailure.noFix;
    }
  }

  Future<Position?> _lastKnown() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  /// Medium accuracy on a short leash: a few metres either way doesn't
  /// change what the stamp is for, and a high-accuracy fix can take far
  /// longer. Falls back to [lastKnown], which may itself be null.
  Future<Position?> _freshFix(Position? lastKnown) async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: _fixTimeout,
        ),
      );
    } catch (_) {
      return lastKnown;
    }
  }

  Future<Placemark?> _placemark(Position position) async {
    try {
      final places = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(_geocodeTimeout);
      return places.isEmpty ? null : places.first;
    } catch (_) {
      // Offline, throttled, or no match — the stamp omits the name.
      return null;
    }
  }

  /// Learns how far the device clock is from network time. Runs once per
  /// warm-up; a failure just leaves the stamp with its local time only.
  void _syncNtp() {
    if (_ntpOffset != null || _ntpInFlight != null) return;
    _ntpInFlight = _readNtpOffset().whenComplete(() => _ntpInFlight = null);
  }

  Future<void> _readNtpOffset() async {
    try {
      final milliseconds = await NTP.getNtpOffset(timeout: _ntpTimeout);
      _ntpOffset = Duration(milliseconds: milliseconds);
    } catch (_) {
      // No network, blocked UDP, or a slow server — the stamp falls back
      // to showing only the device's own clock.
    }
  }
}
