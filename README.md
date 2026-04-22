# Berbers Review — Online (Vercel + Supabase)

Deze versie is bedoeld om publiek te hosten. Deelnemers vullen de vragenlijst in
(identificeren zich met naam / e-mail), en jij ziet alles terug in een admin-dashboard.

## Architectuur

```
┌──────────────┐       ┌────────────┐       ┌───────────────┐
│ index.html   │  ───► │  Supabase  │ ◄───  │  admin.html   │
│ (publiek)    │       │  Postgres  │       │  (admin login)│
└──────────────┘       └────────────┘       └───────────────┘
```

- `index.html` → publieke vragenlijst (jouw huidige app + naam-invoer + auto-sync)
- `admin.html` → dashboard met filters, tabellen en CSV-export (login vereist)
- `schema.sql` → tabelstructuur + Row Level Security
- `api/config.js` → Vercel serverless function die Supabase keys als JS levert
- `vercel.json` → rewrite zodat `/config.js` door de serverless functie wordt gedraaid

## Stappenplan (éénmalig opzetten)

### 1. Supabase project ✅ al gedaan via MCP

- Project URL: `https://mprjorbmbgafekguipjo.supabase.co`
- Publishable (anon) key: `sb_publishable_Z4EhQacChFjCkhEeL0M-1w_DWYk8X5T`
- Deze staan al ingevuld in `config.js`.

### 2. Database schema ✅ al geïnstalleerd via MCP

Tabellen `participants` en `responses` zijn aangemaakt met Row Level Security.
Zie `schema.sql` voor referentie.

### 3. Admin-account aanmaken (nog doen)

1. In Supabase: **Authentication → Users → Add user**.
2. Kies "Create new user", vul jouw **e-mail + wachtwoord** in, zet **Auto Confirm User** aan.
3. Dit account gebruik je straks om op `/admin.html` in te loggen.

> Publiek (anoniem) kan alleen INSERTen. Alleen ingelogde users kunnen SELECTen.
> De admin-controle zit in het Row Level Security-beleid (zie `schema.sql`).

### 4. Vercel deploy

**Optie A — via GitHub (aanrader):**

1. Zet deze `online/` map in een nieuwe GitHub-repo.
2. Ga naar https://vercel.com → **Add New Project** → importeer repo.
3. Laat alle build-instellingen op default (Vercel herkent statische site + `/api`).
4. Bij **Environment Variables** voeg je toe:
   - `SUPABASE_URL` = jouw project URL
   - `SUPABASE_ANON_KEY` = jouw anon key
5. Deploy. Je krijgt een URL zoals `https://jouwproject.vercel.app`.

**Optie B — via Vercel CLI:**

```bash
npm i -g vercel
cd online
vercel
# volg de prompts, bij environment variables voeg toe:
vercel env add SUPABASE_URL
vercel env add SUPABASE_ANON_KEY
vercel --prod
```

### 5. Gebruik

- **Vragenlijst** (deelnemers): `https://jouwproject.vercel.app/`
- **Admin dashboard** (alleen jij): `https://jouwproject.vercel.app/admin.html`

## Lokaal testen vóór deploy

`config.js` is al ingevuld met jouw Supabase keys. Start **altijd** een lokale server (niet
`file://` of dubbelklik, want dan werken fetch-calls naar Supabase niet):

```bash
cd online
npx --yes serve .
# open http://localhost:3000            (vragenlijst)
# open http://localhost:3000/admin.html  (admin dashboard)
# open http://localhost:3000/debug.html  (diagnose-pagina)
```

Let op: `config.js` staat in `.gitignore`, dus die komt niet per ongeluk online.
Op Vercel wordt die dynamisch gegenereerd door `/api/config` (op basis van env vars).

## "Ik heb antwoorden gegeven maar er wordt niks opgeslagen"

Doorloop deze checklist:

1. **Open `/debug.html`** in dezelfde browser/tab waar het misgaat. Die pagina doet
   5 automatische checks (config → library → client → schrijftest → voltooiing). Eerste
   rode bolletje wijst de oorzaak aan.
2. **Tik op de status-strook** op het hoofdscherm (bovenaan, bij je naam) — die opent
   een diagnose-paneel met de laatste foutmelding en een "Kopieer debug"-knop.
3. **Check browser-console** (F12 → Console). Fouten beginnen met `[pushResponse]`,
   `[flushQueue]`, `[startOnboard]` of `[initEnsure]`.
4. **Veelvoorkomende oorzaken**:
   - `config.js` bevat lege `SUPABASE_URL` of `SUPABASE_ANON_KEY` → vul in (lokaal)
     of zet de env vars in Vercel (productie) en deploy opnieuw.
   - Je hebt `file://index.html` geopend (dubbelklik) in plaats van via `npx serve`.
   - Een ad-blocker / privacy-extensie blokkeert `unpkg.com` (supabase-js bundle).
   - Je `participant.id` in localStorage is oud en geen geldig UUID (de app repareert
     dit automatisch vanaf deze versie; klik desnoods op "wissel gebruiker").
5. **Supabase-side verificatie**:
   ```sql
   select count(*) from public.participants;
   select count(*) from public.responses order by created_at desc limit 10;
   ```

## Sync-gedrag

Elke antwoordkeuze wordt:
1. direct in `localStorage` bewaard (volgorde per niveau + keuze),
2. naar Supabase gestuurd via de RPC `record_response`,
3. bij falen in een wachtrij in `localStorage` gezet. De wachtrij wordt elke 15 s en
   bij terug-online opnieuw geprobeerd; daarbij wordt ook `record_participant`
   opnieuw aangeroepen (idempotent, zodat een "unknown participant"-fout direct
   hersteld wordt).

Bij het indrukken van **"Klaar — verstuur en rond af"** wordt de wachtrij volledig
geflushed en de deelnemer krijgt `completed_at` in de database (via
`mark_participant_done`).

## Wat wordt er opgeslagen per keuze?

Per antwoord wordt één rij toegevoegd aan `responses` met:

- `participant_id`, `session_id` (welke deelnemer)
- `niveau`, `word_idx`, `nederlands`, `primair`, `thema` (welk woord)
- `status` — `primair` / `alternatief` / `eigen` / `open`
- `waarde` — wat de deelnemer koos (bij eigen: hun eigen vertaling)
- `is_edit` — of het een wijziging van een eerder antwoord was
- `created_at`

Per deelnemer komt één rij in `participants`:
- `id`, `session_id`, `name`, `email`, `user_agent`, `started_at`.

## Admin-dashboard — wat kun je ermee?

- Alle antwoorden zien (paginated, 50 per pagina).
- **Zoeken** (live, met debounce) in Nederlands / eigen vertaling / primair / thema.
- Filteren op **niveau**, **status**, **deelnemer** en **datumrange**.
- **CSV export** met 3 kolommen (Niveau · Woord · Antwoord). Bij gewijzigde antwoorden
  wordt automatisch alleen het meest recente antwoord per woord geëxporteerd.
- Tabblad **Deelnemers** met status (`klaar` / `bezig`), voortgang-% en totaal aantal
  antwoorden per persoon.
- **Verwijderen** per antwoord of per deelnemer (cascade) met bevestigingsdialoog,
  handig voor het opruimen van testdata.
- Live refresh-knop.

## Offline-resilience

Als een deelnemer tijdens het invullen even geen internet heeft:
- Zijn/haar voortgang blijft in `localStorage`
- Niet-verzonden keuzes worden in een queue bewaard
- Elke 15 seconden (en bij terug-online) probeert de app de queue alsnog te versturen

## Beveiliging checklist

- [ ] `SUPABASE_ANON_KEY` is in env vars, niet hardcoded in repo
- [ ] RLS (Row Level Security) staat aan op beide tabellen (`schema.sql` doet dit automatisch)
- [ ] Admin-account heeft sterk wachtwoord
- [ ] `SERVICE_ROLE_KEY` gebruik je NOOIT in de frontend (alleen in server-side functies, indien nodig)

## Veel gemaakte rapportages (SQL)

Onderin `schema.sql` staan voorbeelden. Voorbeelden om in Supabase SQL Editor te draaien:

```sql
-- Meest voorkomende "eigen" vertalingen per woord
select nederlands, waarde, count(*) as n
from responses
where status = 'eigen'
group by 1,2
order by n desc
limit 50;

-- Voltooiingspercentage per deelnemer
select p.name, p.email,
       count(r.*) filter (where r.status <> 'open') as beantwoord,
       count(r.*) as totaal
from participants p
left join responses r on r.participant_id = p.id
group by 1,2
order by beantwoord desc;
```
