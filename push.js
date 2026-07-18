// YourTurn Push-Anbindung (v2).
//
// WICHTIG gegenüber v1: Diese Datei legt KEINEN eigenen Supabase-Client an.
// Zwei GoTrue-Instanzen im selben Tab teilen sich denselben localStorage-Key
// und streiten sich um den Token-Refresh — das kann die Session der App
// zerschießen (Symptom: "not authenticated", Trip erstellen schlägt fehl).
// Stattdessen: Session nur lesen, REST direkt aufrufen.

const SUPA_URL = 'https://hvjvcdhknqajoyjudweg.supabase.co';
const SUPA_KEY = 'sb_publishable_ADk5veGqnLjQthZ0FfK3fQ_1xsyWPu3';
const VAPID_PUBLIC = 'BIHxDHXPVSisrsH1VvZvAbrGRkXSp67sqb_y24JZycBT4Ge8Vv_eJhEHwCFNK4HcMsCtCmTNNI8Go7Oh-zXPs7k';
const STORAGE_KEY = 'sb-hvjvcdhknqajoyjudweg-auth-token';

/* ---------- Session nur lesen, nie anfassen ---------- */
function session() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const j = JSON.parse(raw);
    const s = j?.currentSession ?? j;
    return s?.access_token ? s : null;
  } catch { return null; }
}
function userId(token) {
  try {
    const p = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
    return p.sub || null;
  } catch { return null; }
}
async function rest(path, opts = {}) {
  const s = session();
  if (!s) throw new Error('no session');
  const res = await fetch(SUPA_URL + '/rest/v1/' + path, {
    ...opts,
    headers: {
      apikey: SUPA_KEY,
      Authorization: 'Bearer ' + s.access_token,
      'Content-Type': 'application/json',
      ...(opts.headers || {}),
    },
  });
  if (!res.ok) throw new Error('HTTP ' + res.status + ' ' + (await res.text()).slice(0, 120));
  return res.status === 204 ? null : res.json();
}

/* ---------- Helfer ---------- */
const standalone = () =>
  window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
const isIOS = () => /iphone|ipad|ipod/i.test(navigator.userAgent);

function b64ToUint8(base64) {
  const pad = '='.repeat((4 - (base64.length % 4)) % 4);
  const raw = atob((base64 + pad).replace(/-/g, '+').replace(/_/g, '/'));
  return Uint8Array.from([...raw].map((c) => c.charCodeAt(0)));
}

function pill(html, onGo) {
  document.getElementById('yt-push-pill')?.remove();
  const el = document.createElement('div');
  el.id = 'yt-push-pill';
  el.style.cssText =
    'position:fixed;left:50%;transform:translateX(-50%);bottom:calc(104px + env(safe-area-inset-bottom));' +
    'z-index:70;background:#102033;color:#F6F1E8;border-radius:16px;padding:12px 14px;' +
    'max-width:min(400px,calc(100% - 32px));font:500 12.5px/1.45 system-ui,sans-serif;' +
    'box-shadow:0 12px 34px rgba(16,32,51,.32);display:flex;gap:10px;align-items:center';
  el.innerHTML =
    '<span style="flex:1">' + html + '</span>' +
    '<button id="yt-push-x" style="border:0;background:none;color:rgba(246,241,232,.5);font:inherit;cursor:pointer;padding:4px">✕</button>';
  document.body.appendChild(el);
  el.querySelector('#yt-push-x').onclick = () => {
    el.remove();
    sessionStorage.setItem('yt_push_dismissed', '1');
  };
  if (onGo) {
    const btn = el.querySelector('#yt-push-go');
    if (btn) btn.onclick = onGo;
  }
  return el;
}

async function myMembers() {
  const s = session();
  if (!s) return [];
  const uid = userId(s.access_token);
  if (!uid) return [];
  return (await rest('members?select=id,trip_id&user_id=eq.' + uid)) || [];
}

async function saveSubscription(sub, members) {
  const json = sub.toJSON();
  const rows = members.map((m) => ({
    member_id: m.id,
    endpoint: json.endpoint,
    p256dh: json.keys.p256dh,
    auth: json.keys.auth,
  }));
  await rest('push_subscriptions?on_conflict=member_id,endpoint', {
    method: 'POST',
    headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
    body: JSON.stringify(rows),
  });
}

/* ---------- Ablauf ---------- */
async function subscribe() {
  try {
    const perm = await Notification.requestPermission();
    if (perm !== 'granted') {
      pill('Kein Problem — ohne Ping siehst du deinen Turn, wenn du die App öffnest.');
      return;
    }
    const reg = await navigator.serviceWorker.ready;
    const sub =
      (await reg.pushManager.getSubscription()) ||
      (await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: b64ToUint8(VAPID_PUBLIC),
      }));

    const members = await myMembers();
    if (!members.length) return;
    await saveSubscription(sub, members);

    pill('Passt — du bekommst einen Ping, wenn du dran bist. ✓');
    setTimeout(() => document.getElementById('yt-push-pill')?.remove(), 3500);
  } catch (e) {
    pill('Ping-Anmeldung fehlgeschlagen: ' + (e.message || e));
  }
}

async function boot() {
  if (sessionStorage.getItem('yt_push_dismissed')) return;
  await new Promise((r) => setTimeout(r, 2500)); // App zuerst rendern lassen

  let members = [];
  try { members = await myMembers(); } catch { return; }
  if (!members.length) return; // nur wer in einem Trip ist, braucht Pings

  if (isIOS() && !standalone()) {
    pill('Damit dich dein Turn erreicht: <b>Teilen → Zum Home-Bildschirm</b>. Dann kommt der Ping.');
    return;
  }
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) return;
  if (Notification.permission === 'denied') return;

  if (Notification.permission === 'granted') {
    const reg = await navigator.serviceWorker.ready;
    const existing = await reg.pushManager.getSubscription();
    if (existing) {
      // neue Trips still nachtragen
      try { await saveSubscription(existing, members); } catch {}
      return;
    }
    return subscribe();
  }

  pill(
    'Turn-Pings an? Einmal am Tag ist jemand dran — sonst verpasst du es. ' +
      '<button id="yt-push-go" style="border:0;background:#FF6B4A;color:#fff;font:700 12.5px system-ui;padding:8px 12px;border-radius:10px;cursor:pointer;margin-left:6px">Aktivieren</button>',
    subscribe
  );
}

boot().catch((e) => console.warn('push init', e));
