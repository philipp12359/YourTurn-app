import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return new Response(JSON.stringify({ error: "method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const authHeader = request.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) throw new Error("missing authorization");

    const token = authHeader.slice(7);
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );

    const { data: userData, error: userError } = await admin.auth.getUser(token);
    if (userError || !userData.user) {
      return new Response(JSON.stringify({ error: "invalid session" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await request.json().catch(() => ({}));
    const tripId = typeof body.trip_id === "string" ? body.trip_id : "";
    if (!tripId) throw new Error("trip_id is required");

    const { data: trip, error: tripError } = await admin
      .from("trips")
      .select("id, name, slug, created_by")
      .eq("id", tripId)
      .maybeSingle();

    if (tripError) throw tripError;
    if (!trip) {
      return new Response(JSON.stringify({ error: "trip not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    if (trip.created_by !== userData.user.id) {
      return new Response(JSON.stringify({ error: "only the trip creator can delete this trip" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    let removedFiles = 0;
    const limit = 100;
    while (true) {
      const { data: objects, error: listError } = await admin.storage
        .from("photos")
        .list(tripId, { limit, offset: 0, sortBy: { column: "name", order: "asc" } });
      if (listError) throw listError;
      const paths = (objects || [])
        .filter((object) => object.id && object.name)
        .map((object) => `${tripId}/${object.name}`);
      if (!paths.length) break;
      const { error: removeError } = await admin.storage.from("photos").remove(paths);
      if (removeError) throw removeError;
      removedFiles += paths.length;
      if (paths.length < limit) break;
    }

    const { error: deleteError } = await admin.from("trips").delete().eq("id", tripId);
    if (deleteError) throw deleteError;

    return new Response(JSON.stringify({
      deleted: true,
      trip_id: trip.id,
      trip_name: trip.name,
      removed_files: removedFiles,
    }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({
      error: error instanceof Error ? error.message : String(error),
    }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
