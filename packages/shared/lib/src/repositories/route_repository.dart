import '../supabase/supabase_bootstrap.dart';

/// A point on a route, in the order humans write coordinates.
class RoutePoint {
  const RoutePoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

/// One turn in the directions.
class RouteStep {
  const RouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final String instruction;
  final double distanceMeters;
  final double durationSeconds;
}

/// A road route: the line to draw, plus how far and how long.
class DeliveryRoute {
  const DeliveryRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.steps,
  });

  final List<RoutePoint> points;
  final double distanceMeters;
  final double durationSeconds;
  final List<RouteStep> steps;

  String get distanceLabel => distanceMeters >= 1000
      ? '${(distanceMeters / 1000).toStringAsFixed(1)} km'
      : '${distanceMeters.round()} m';

  String get etaLabel {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 1) return 'under a minute';
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    return '${hours}h ${minutes % 60}m';
  }
}

class RouteException implements Exception {
  const RouteException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Road routing for the delivery map.
///
/// Calls the `route` Edge Function rather than OpenRouteService
/// directly: the API key lives on the server, because anything shipped
/// in an APK can be extracted and would let a stranger spend the shop's
/// daily quota. Swapping routing provider is therefore a server change,
/// with no app release.
class RouteRepository {
  Future<DeliveryRoute> getRoute({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
  }) async {
    final response = await supabase.functions.invoke('route', body: {
      'from': {'lat': fromLatitude, 'lng': fromLongitude},
      'to': {'lat': toLatitude, 'lng': toLongitude},
    });

    final data = response.data;
    if (data is! Map || data['points'] == null) {
      throw RouteException(
        (data is Map ? data['error'] as String? : null) ??
            'Could not work out a route.',
      );
    }

    return DeliveryRoute(
      points: [
        for (final p in (data['points'] as List))
          RoutePoint(
            latitude: (p['lat'] as num).toDouble(),
            longitude: (p['lng'] as num).toDouble(),
          ),
      ],
      distanceMeters: (data['distance_meters'] as num?)?.toDouble() ?? 0,
      durationSeconds: (data['duration_seconds'] as num?)?.toDouble() ?? 0,
      steps: [
        for (final s in (data['steps'] as List? ?? const []))
          RouteStep(
            instruction: s['instruction'] as String? ?? '',
            distanceMeters: (s['distance_meters'] as num?)?.toDouble() ?? 0,
            durationSeconds: (s['duration_seconds'] as num?)?.toDouble() ?? 0,
          ),
      ],
    );
  }
}
