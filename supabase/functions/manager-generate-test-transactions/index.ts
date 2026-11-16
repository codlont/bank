import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authHeader = req.headers.get("Authorization") || "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "Sign-in required" }, 401);

  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: authError } = await userClient.auth.getUser();
  if (authError || !userData.user) return json({ error: "Your session is invalid or expired" }, 401);

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: manager, error: managerError } = await admin
    .from("manager_users")
    .select("role")
    .eq("user_id", userData.user.id)
    .maybeSingle();
  if (managerError || !manager || !["manager", "admin"].includes(manager.role)) {
    return json({ error: "Manager authorization required" }, 403);
  }

  let body: { account_id?: string; transactions?: unknown };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON body" }, 400); }
  if (!body.account_id || !Array.isArray(body.transactions) ||
      body.transactions.length < 1 || body.transactions.length > 200) {
    return json({ error: "Select an account and generate between 1 and 200 records" }, 400);
  }

  const { data, error } = await admin.rpc("manager_generate_test_transactions", {
    p_manager_user_id: userData.user.id,
    p_account_id: body.account_id,
    p_transactions: body.transactions,
  });
  if (error) return json({ error: error.message }, 400);
  return json({ success: true, result: data });
});
