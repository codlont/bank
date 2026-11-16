// Public browser configuration for the Vercel Bank simulation.
// Publishable keys are intended for browser use. Never add a Supabase secret/service-role key here.
window.VERCEL_BANK_SUPABASE_URL = "https://jxcazwazjrmtshyzsivw.supabase.co";
window.VERCEL_BANK_SUPABASE_KEY = "sb_publishable_q6ffqUMPjzFyxp6iX3VnJg_91QtG41t";
window.vercelBankClient = window.supabase.createClient(
  window.VERCEL_BANK_SUPABASE_URL,
  window.VERCEL_BANK_SUPABASE_KEY
);
