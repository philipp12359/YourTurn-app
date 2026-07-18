# PWA & Push — Origin-Dateien

Diese Dateien **müssen vom eigenen Origin** (Vercel) ausgeliefert werden — sie
funktionieren nicht aus der Datenbank oder von einem CDN:

| Datei                | Zweck                                                      |
|----------------------|-----------------------------------------------------------|
| `sw.js`              | Service Worker, empfängt Web-Push, zeigt die Notification |
| `push.js`            | Subscribe-Flow, schreibt in `push_subscriptions`          |
| `manifest.json`      | „Zum Home-Bildschirm" (auf iOS Pflicht, damit Push geht)  |
| `icon-192/512.png`   | App-Icons                                                  |
| `apple-touch-icon.png` | iOS-Homescreen-Icon                                     |

## In index.html verdrahtet
- `<head>`: Manifest, Apple-Touch-Icon, `apple-mobile-web-app-capable`
- vor `</body>`: Service-Worker-Registrierung + `push.js` als Modul

## Wichtige Design-Entscheidung: push.js nutzt KEINEN eigenen Supabase-Client
Zwei `createClient()`-Instanzen im selben Tab teilen sich den localStorage-Auth-Key
und streiten sich um den Token-Refresh. Ergebnis: Session stirbt, `create_trip`
läuft ins „not authenticated". Deshalb liest `push.js` die Session nur aus dem
localStorage und spricht per REST mit Supabase.

## push.js überlagert die Bottom-Nav nicht
Die Hinweis-Pille sitzt auf z-index:70 (nicht 9999) und 104px über dem unteren Rand,
damit sie die Navigations-Buttons darunter nicht abfängt.

## vercel.json
`/sw.js` ist vom `no-store` ausgenommen und bekommt `must-revalidate` +
`Service-Worker-Allowed: /`. Ohne das hängt man an einer veralteten SW-Version fest.

## Secrets (Supabase → Edge Functions → Secrets), NICHT committen
    VAPID_PUBLIC_KEY   (steht auch in push.js — bei Wechsel dort mitziehen)
    VAPID_PRIVATE_KEY
    VAPID_SUBJECT      z. B. mailto:philipp12359@gmail.com
    CRON_SECRET        (identisch mit private_config.cron_secret in der DB)
