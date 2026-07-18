import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const headers = {
  "Content-Type": "text/html; charset=utf-8",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers });
  try {
    const base = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    if (!base || !anon) throw new Error("Missing runtime environment");
    const response = await fetch(base + "/rest/v1/rpc/get_yourturn_stable_app", {
      method: "POST",
      headers: {
        apikey: anon,
        Authorization: `Bearer ${anon}`,
        "Content-Type": "application/json",
      },
      body: "{}",
      cache: "no-store",
    });
    if (!response.ok) throw new Error(`Stable app request failed ${response.status}`);
    const html = await response.json();
    if (typeof html !== "string" || !html.includes("document.open();document.write(h);document.close()")) {
      throw new Error("Stable app validation failed");
    }
    return new Response(req.method === "HEAD" ? null : html, { status: 200, headers });
  } catch (error) {
    return new Response(`YourTurn failed to load: ${error instanceof Error ? error.message : String(error)}`, {
      status: 500,
      headers: { ...headers, "Content-Type": "text/plain; charset=utf-8" },
    });
  }
});
