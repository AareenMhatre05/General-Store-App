import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../repositories/route_repository.dart';
import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_theme.dart';

/// The drop, and whoever is carrying it, on one map -- joined by the
/// actual road route between them.
///
/// OpenStreetMap tiles through flutter_map, matching the address picker:
/// no API key, no billing account, and one fewer service to keep alive.
/// The route line comes from the `route` Edge Function, so the routing
/// key stays on the server.
///
/// Used from both ends: the customer watching their order approach, and
/// the delivery partner finding the door.
class DeliveryMap extends StatefulWidget {
  const DeliveryMap({
    super.key,
    required this.destination,
    this.partner,
    this.destinationLabel = 'Delivery address',
    this.partnerLabel = 'Delivery partner',
    this.height = 260,
  });

  /// Where the order is going.
  final LatLng destination;

  /// Where the partner is right now, if their position is known.
  final LatLng? partner;

  final String destinationLabel;
  final String partnerLabel;
  final double height;

  @override
  State<DeliveryMap> createState() => _DeliveryMapState();
}

class _DeliveryMapState extends State<DeliveryMap> {
  final _controller = MapController();
  bool _ready = false;

  List<LatLng>? _route;
  String? _routeSummary;
  bool _routeFailed = false;
  LatLng? _routedFrom;
  bool _fetching = false;

  static const _distance = Distance();

  /// The partner's position refreshes every 20 seconds. Re-routing on
  /// each of those would burn the routing quota to redraw a line that
  /// has barely changed, so a new route is only worth fetching once they
  /// have actually moved.
  static const _refetchAfterMeters = 200.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFetchRoute());
  }

  @override
  void didUpdateWidget(DeliveryMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.partner != widget.partner ||
        oldWidget.destination != widget.destination) {
      _maybeFetchRoute();
      _fit();
    }
  }

  Future<void> _maybeFetchRoute() async {
    final partner = widget.partner;
    if (partner == null || _fetching) return;

    final routedFrom = _routedFrom;
    if (routedFrom != null &&
        _distance(routedFrom, partner) < _refetchAfterMeters &&
        _route != null) {
      return;
    }

    _fetching = true;
    try {
      final route = await context.read<RouteRepository>().getRoute(
            fromLatitude: partner.latitude,
            fromLongitude: partner.longitude,
            toLatitude: widget.destination.latitude,
            toLongitude: widget.destination.longitude,
          );
      if (!mounted) return;
      setState(() {
        _route = [
          for (final point in route.points)
            LatLng(point.latitude, point.longitude),
        ];
        _routeSummary = '${route.distanceLabel} · ${route.etaLabel} away';
        _routeFailed = false;
        _routedFrom = partner;
      });
      _fit();
    } catch (_) {
      // Routing can fail for ordinary reasons -- no signal, a pin that is
      // not near a road, the daily quota. A straight line is still worth
      // drawing, as long as it is labelled as the estimate it is.
      if (mounted) setState(() => _routeFailed = true);
    } finally {
      _fetching = false;
    }
  }

  /// Frames the whole route where there is one, and both points
  /// otherwise. With only one known point there is nothing to fit.
  void _fit() {
    if (!_ready) return;
    final partner = widget.partner;
    final route = _route;

    if (route != null && route.length > 1) {
      _controller.fitCamera(
        CameraFit.coordinates(
          coordinates: route,
          padding: const EdgeInsets.all(40),
        ),
      );
      return;
    }
    if (partner == null) {
      _controller.move(widget.destination, 16);
      return;
    }
    _controller.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(widget.destination, partner),
        padding: const EdgeInsets.all(48),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final partner = widget.partner;
    final route = _route;
    final hasRoad = route != null && route.length > 1;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: partner ?? widget.destination,
                initialZoom: 15,
                onMapReady: () {
                  _ready = true;
                  _fit();
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.kavitageneralstores',
                ),
                if (hasRoad)
                  PolylineLayer(
                    polylines: [
                      // Drawn twice: a wider dark stroke underneath gives
                      // the line an outline, so it stays readable over
                      // both pale roads and dark parkland.
                      Polyline(
                        points: route,
                        strokeWidth: 7,
                        color: context.colors.onPrimaryContainer
                            .withValues(alpha: 0.35),
                      ),
                      Polyline(
                        points: route,
                        strokeWidth: 4,
                        color: context.colors.primary,
                      ),
                    ],
                  )
                else if (partner != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [partner, widget.destination],
                        strokeWidth: 3,
                        color: context.colors.outline.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: widget.destination,
                      width: 44,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: Icon(Icons.location_on,
                          size: 40, color: context.colors.error),
                    ),
                    if (partner != null)
                      Marker(
                        point: partner,
                        width: 44,
                        height: 44,
                        child: Container(
                          decoration: BoxDecoration(
                            color: context.colors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: context.colors.onPrimary, width: 2),
                          ),
                          child: Icon(Icons.delivery_dining,
                              size: 22, color: context.colors.onPrimary),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: AppSpacing.base,
              bottom: AppSpacing.base,
              right: AppSpacing.base,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.dp),
                ),
                child: Text(
                  _caption(partner != null, hasRoad),
                  style: AppTextStyles.labelMd
                      .copyWith(color: context.colors.onSurface),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _caption(bool hasPartner, bool hasRoad) {
    if (!hasPartner) return 'Waiting for the partner\'s location';
    if (hasRoad) return '${widget.partnerLabel} · $_routeSummary';
    if (_routeFailed) {
      return '${widget.partnerLabel} · direct line, road route unavailable';
    }
    return '${widget.partnerLabel} · working out the route...';
  }
}
