/* Safe client configuration only. Never put service-role/payment secrets here. */
window.VELUSH_CONFIG = window.VELUSH_CONFIG || {
  supabaseUrl: "https://YOUR-PROJECT.supabase.co",
  supabaseAnonKey: "YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY",
  orderFunctionUrl: "https://YOUR-PROJECT.supabase.co/functions/v1/create-order",
  currency: "BDT",
  storeName: "VELUSH"
};
