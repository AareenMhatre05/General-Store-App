// Turn-by-turn road route between two points, via OpenRouteService.
//
// This exists as an Edge Function rather than a direct call from the app
// for one reason: the ORS key must not ship inside an APK. Anything in
// the binary can be extracted, and a leaked key means someone else burns
// the shop's daily quota. The key stays here; the apps call this.
//
// It also means swapping provider later (ORS -> self-hosted OSRM, or
// Google Directions) is a server-side change with no app release.
//
// Secret required:
//   supabase secrets set ORS_API_KEY=...   (openrouteservice.org, free tier)

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function isFiniteCoord(lat: unknown, lng: unknown): boolean {
  return (
    typeof lat === 'number' && typeof lng === 'number' &&
    Number.isFinite(lat) && Number.isFinite(lng) &&
    lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
  );
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const key = Deno.env.get('ORS_API_KEY');
    if (!key) {
      return json({
        error: 'Routing is not configured yet. Set ORS_API_KEY (see RELEASE.md).',
      }, 503);
    }

    // Signed-in callers only. Routing costs quota, so it is not a public
    // endpoint even though it exposes nothing sensitive.
    if (!req.headers.get('Authorization')) {
      return json({ error: 'Not signed in.' }, 401);
    }

    const { from, to } = await req.json();
    if (!from || !to || !isFiniteCoord(from.lat, from.lng) || !isFiniteCoord(to.lat, to.lng)) {
      return json({ error: 'from and to must each be {lat, lng}.' }, 400);
    }

    // ORS takes [longitude, latitude] -- the reverse of how humans write
    // it, and a classic source of routes through the wrong hemisphere.
    const response = await fetch(
      'https://api.openrouteservice.org/v2/directions/driving-car/geojson',
      {
        method: 'POST',
        headers: {
          Authorization: key,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          coordinates: [
            [from.lng, from.lat],
            [to.lng, to.lat],
          ],
          instructions: true,
          units: 'm',
        }),
      },
    );

    const body = await response.json();
    if (!response.ok) {
      return json({
        error: body?.error?.message ?? 'Routing provider rejected the request.',
      }, 502);
    }

    const feature = body?.features?.[0];
    if (!feature) return json({ error: 'No route found between those points.' }, 404);

    const summary = feature.properties?.summary ?? {};
    const steps = feature.properties?.segments?.[0]?.steps ?? [];

    // Hand back only what a map needs, in {lat, lng} order, so the app
    // never has to know ORS's response shape or its axis order.
    return json({
      distance_meters: summary.distance ?? null,
      duration_seconds: summary.duration ?? null,
      points: (feature.geometry?.coordinates ?? []).map(
        ([lng, lat]: [number, number]) => ({ lat, lng }),
      ),
      steps: steps.map((s: Record<string, unknown>) => ({
        instruction: s.instruction,
        distance_meters: s.distance,
        duration_seconds: s.duration,
      })),
    });
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
