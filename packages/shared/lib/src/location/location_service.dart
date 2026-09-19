import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Why a location read failed, in terms that map to something the user
/// can actually do about it.
enum LocationFailureKind {
  serviceDisabled,
  permissionDenied,
  permissionPermanentlyDenied,
  timedOut,
  unknown,
}

class LocationFailure implements Exception {
  const LocationFailure(this.kind, {this.detail});

  final LocationFailureKind kind;

  /// The underlying error text. Shown to the user for [unknown] only --
  /// for the rest, the specific advice is more useful than the raw
  /// exception.
  final String? detail;

  String get message => switch (kind) {
        LocationFailureKind.serviceDisabled =>
          'Location is switched off on your phone. Turn it on, then try again.',
        LocationFailureKind.permissionDenied =>
          'Location permission was declined, so we cannot pin this spot.',
        LocationFailureKind.permissionPermanentlyDenied =>
          'Location permission is blocked for this app. Open Settings to allow it.',
        LocationFailureKind.timedOut =>
          'Could not get a location fix. Step outside or near a window and try again.',
        LocationFailureKind.unknown =>
          'Could not read your location.${detail == null ? '' : ' ($detail)'}',
      };

  /// Whether [LocationService.openRelevantSettings] can help here.
  bool get canOpenSettings =>
      kind == LocationFailureKind.serviceDisabled ||
      kind == LocationFailureKind.permissionPermanentlyDenied;

  @override
  String toString() => 'LocationFailure(${kind.name}): $message';
}

/// One place that knows how to get a position, used by checkout, the
/// address editor, and the staff store-location screen.
///
/// Written defensively because on a real phone this fails in several
/// distinct ways -- GPS off, permission refused, permission refused
/// permanently, or a fix that simply never arrives indoors -- and each
/// needs different advice. It previously lived inline in three screens
/// with one catch-all "check permissions" message, which is why a
/// device-only failure was impossible to diagnose.
class LocationService {
  const LocationService();

  /// Best available position, or throws [LocationFailure].
  ///
  /// [timeout] matters: `getCurrentPosition` will otherwise wait
  /// indefinitely for a fix that may never come indoors, leaving the UI
  /// spinning forever. On timeout or an unexpected plugin error we fall
  /// back to the last known position, which is usually good enough to
  /// place an order against.
  Future<Position> current({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(LocationFailureKind.serviceDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(LocationFailureKind.permissionPermanentlyDenied);
    }
    if (permission == LocationPermission.denied) {
      throw const LocationFailure(LocationFailureKind.permissionDenied);
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          // `best` can hang for a long time hunting satellites; `high`
          // is accurate to a few metres and settles much faster, which
          // matters more when someone is standing at a doorstep.
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
      throw const LocationFailure(LocationFailureKind.timedOut);
    } on LocationServiceDisabledException {
      throw const LocationFailure(LocationFailureKind.serviceDisabled);
    } on PermissionDeniedException {
      throw const LocationFailure(LocationFailureKind.permissionDenied);
    } catch (e) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
      throw LocationFailure(LocationFailureKind.unknown, detail: e.toString());
    }
  }

  /// Sends the user where they can fix [failure] themselves.
  Future<void> openRelevantSettings(LocationFailure failure) {
    return failure.kind == LocationFailureKind.serviceDisabled
        ? Geolocator.openLocationSettings()
        : Geolocator.openAppSettings();
  }
}
