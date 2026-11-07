// shade – kostenloser Benachrichtigungs-Server (Cloudflare Worker, Web Push)
// POST /sub    {idToken, sub}          → Gerät für Benachrichtigungen anmelden
// POST /unsub  {idToken, sub}          → Gerät abmelden
// POST /send   {idToken, to, kind, text} → Freunden eine Benachrichtigung schicken
const PROJECT = "shade-56574";
const FS = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const ORIGINS = ["https://shadechat.github.io", "https://tahirdemirci559-hub.github.io"];

const enc = new TextEncoder();
const b64u = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const unb64u = (s) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - s.length % 4) % 4)), (c) => c.charCodeAt(0));
const concat = (...a) => { const out = new Uint8Array(a.reduce((n, x) => n + x.length, 0)); let o = 0; for (const x of a) { out.set(x, o); o += x.length; } return out; };

function cors(req) {
  const o = req.headers.get("Origin") || "";
  return { "Access-Control-Allow-Origin": ORIGINS.includes(o) ? o : ORIGINS[0], "Access-Control-Allow-Methods": "POST, OPTIONS", "Access-Control-Allow-Headers": "content-type", "Vary": "Origin" };
}
const json = (req, data, status = 200) => new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json", ...cors(req) } });

// Wer ist der Absender? Firestore prüft das Token: nur der Besitzer darf push/{uid} lesen.
async function whoAmI(idToken) {
  if (!idToken || idToken.split(".").length !== 3) return null;
  let uid;
  try { uid = JSON.parse(new TextDecoder().decode(unb64u(idToken.split(".")[1]))).user_id; } catch { return null; }
  if (!uid || !/^[A-Za-z0-9]{10,40}$/.test(uid)) return null;
  const r = await fetch(`${FS}/push/${uid}`, { headers: { Authorization: "Bearer " + idToken } });
  if (r.status !== 200 && r.status !== 404) return null;
  return uid;
}
async function userDoc(uid, idToken) {
  const r = await fetch(`${FS}/users/${uid}`, { headers: { Authorization: "Bearer " + idToken } });
  if (!r.ok) return null;
  const f = (await r.json()).fields || {};
  return { name: f.name?.stringValue || "Jemand", friends: (f.friends?.arrayValue?.values || []).map((v) => v.stringValue) };
}

// ---- Web Push (RFC 8291 Verschlüsselung + RFC 8292 VAPID) ----
async function hkdf(salt, ikm, info, bits) {
  const k = await crypto.subtle.importKey("raw", ikm, "HKDF", false, ["deriveBits"]);
  return new Uint8Array(await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt, info }, k, bits));
}
async function encrypt(sub, payload) {
  const uaPub = unb64u(sub.keys.p256dh), auth = unb64u(sub.keys.auth);
  const as = await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
  const asPub = new Uint8Array(await crypto.subtle.exportKey("raw", as.publicKey));
  const uaKey = await crypto.subtle.importKey("raw", uaPub, { name: "ECDH", namedCurve: "P-256" }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: "ECDH", public: uaKey }, as.privateKey, 256));
  const ikm = await hkdf(auth, shared, concat(enc.encode("WebPush: info\0"), uaPub, asPub), 256);
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const cek = await hkdf(salt, ikm, enc.encode("Content-Encoding: aes128gcm\0"), 128);
  const nonce = await hkdf(salt, ikm, enc.encode("Content-Encoding: nonce\0"), 96);
  const key = await crypto.subtle.importKey("raw", cek, "AES-GCM", false, ["encrypt"]);
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, key, concat(enc.encode(payload), new Uint8Array([2]))));
  const head = new Uint8Array(21); head.set(salt, 0); new DataView(head.buffer).setUint32(16, 4096); head[20] = 65;
  return concat(head, asPub, ct);
}
let vapidKey = null;
async function vapidAuth(env, endpoint) {
  if (!vapidKey) {
    const pub = unb64u(env.VAPID_PUBLIC);
    vapidKey = await crypto.subtle.importKey("jwk", { kty: "EC", crv: "P-256", d: env.VAPID_PRIVATE, x: b64u(pub.slice(1, 33)), y: b64u(pub.slice(33, 65)), ext: true },
      { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  }
  const head = b64u(enc.encode(JSON.stringify({ typ: "JWT", alg: "ES256" })));
  const body = b64u(enc.encode(JSON.stringify({ aud: new URL(endpoint).origin, exp: Math.floor(Date.now() / 1000) + 12 * 3600, sub: "mailto:shade@example.com" })));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, vapidKey, enc.encode(head + "." + body));
  return `vapid t=${head}.${body}.${b64u(sig)}, k=${env.VAPID_PUBLIC}`;
}
async function pushOne(env, sub, payload) {
  const r = await fetch(sub.endpoint, {
    method: "POST",
    headers: { Authorization: await vapidAuth(env, sub.endpoint), TTL: "3600", Urgency: "high", "Content-Encoding": "aes128gcm", "Content-Type": "application/octet-stream" },
    body: await encrypt(sub, JSON.stringify(payload)),
  });
  return r.status;
}
async function pushTo(env, uid, payload) {
  const subs = JSON.parse((await env.SUBS.get("s:" + uid)) || "[]");
  if (!subs.length) return 0;
  const keep = [];
  for (const s of subs) {
    let st = 0; try { st = await pushOne(env, s, payload); } catch { st = 0; }
    if (st !== 404 && st !== 410) keep.push(s);
  }
  if (keep.length !== subs.length) await env.SUBS.put("s:" + uid, JSON.stringify(keep));
  return subs.length;
}

const TEXT = {
  msg: (t) => (t || "Neue Nachricht").slice(0, 140),
  shot: () => "hat dir einen Shot geschickt",
  share: () => "hat dir etwas geteilt",
  story: () => "hat eine neue Story gepostet",
  call: () => "ruft dich an 📞 – tippe zum Annehmen",
  vcall: () => "ruft dich per Video an 🎥 – tippe zum Annehmen",
  missed: () => "Verpasster Anruf",
};

export default {
  async fetch(req, env) {
    if (req.method === "OPTIONS") return new Response(null, { headers: cors(req) });
    const url = new URL(req.url);
    if (req.method === "GET" && url.pathname === "/") return json(req, { ok: true, service: "shade push" });
    if (req.method !== "POST") return json(req, { error: "method" }, 405);
    let b; try { b = await req.json(); } catch { return json(req, { error: "json" }, 400); }
    const uid = await whoAmI(b.idToken);
    if (!uid) return json(req, { error: "auth" }, 401);

    if (url.pathname === "/sub" || url.pathname === "/unsub") {
      const s = b.sub;
      if (!s || typeof s.endpoint !== "string" || !s.endpoint.startsWith("https://") || !s.keys?.p256dh || !s.keys?.auth) return json(req, { error: "sub" }, 400);
      let subs = JSON.parse((await env.SUBS.get("s:" + uid)) || "[]").filter((x) => x.endpoint !== s.endpoint);
      if (url.pathname === "/sub") subs = [...subs, { endpoint: s.endpoint, keys: { p256dh: s.keys.p256dh, auth: s.keys.auth } }].slice(-5);
      await env.SUBS.put("s:" + uid, JSON.stringify(subs));
      return json(req, { ok: true, devices: subs.length });
    }
    if (url.pathname === "/send") {
      const kind = TEXT[b.kind] ? b.kind : "msg";
      const me = await userDoc(uid, b.idToken);
      if (!me) return json(req, { error: "user" }, 400);
      let to = kind === "story" ? me.friends : (Array.isArray(b.to) ? b.to : [b.to]);
      to = [...new Set(to)].filter((t) => typeof t === "string" && t !== uid && me.friends.includes(t)).slice(0, 50);
      const payload = { title: me.name, body: TEXT[kind](b.text), tag: (kind === "story" ? "story-" : kind.includes("call") || kind === "missed" ? "call-" : "chat-") + uid, url: kind === "story" ? "./#stories" : "./#chat=" + uid };
      let n = 0; for (const t of to) n += await pushTo(env, t, payload);
      return json(req, { ok: true, devices: n });
    }
    return json(req, { error: "path" }, 404);
  },
};
