import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

serve((_req) => {
  return new Response("Supabase Edge Runtime OK\n", {
    headers: { "content-type": "text/plain" },
  });
});
