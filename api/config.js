// Vercel Serverless Function: levert config.js dynamisch
// zodat je Supabase keys via Vercel env vars kunt beheren
// (in plaats van ze hardcoded in een file in je repo te zetten).
//
// De anon key is veilig om in de browser te tonen, mits je RLS-policies
// goed staan (zie schema.sql). Never expose SERVICE_ROLE_KEY here.
export default function handler(_req, res) {
  const url = process.env.SUPABASE_URL || '';
  const key = process.env.SUPABASE_ANON_KEY || '';
  res.setHeader('Content-Type', 'application/javascript; charset=utf-8');
  res.setHeader('Cache-Control', 'public, max-age=60');
  res.status(200).send(
    `window.APP_CONFIG = ${JSON.stringify({ SUPABASE_URL: url, SUPABASE_ANON_KEY: key })};`
  );
}
