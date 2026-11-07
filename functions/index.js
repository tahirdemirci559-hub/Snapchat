// shade – Benachrichtigungen (Web Push) für neue Nachrichten, Shots, Stories und Anrufe.
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const webpush = require("web-push");

admin.initializeApp();
const db = admin.firestore();
setGlobalOptions({ region: "europe-west3", maxInstances: 5 });

let vapidReady = false;
function vapid() {
  if (!vapidReady) {
    webpush.setVapidDetails("mailto:" + (process.env.VAPID_MAIL || "shade@example.com"), process.env.VAPID_PUBLIC, process.env.VAPID_PRIVATE);
    vapidReady = true;
  }
}

async function nameOf(uid) {
  const s = await db.collection("users").doc(uid).get();
  return (s.exists && s.data().name) || "Jemand";
}

// Schickt eine Benachrichtigung an alle Geräte eines Nutzers und räumt abgelaufene Geräte auf.
async function pushTo(uid, payload) {
  vapid();
  const ref = db.collection("push").doc(uid);
  const s = await ref.get();
  const subs = (s.exists && s.data().subs) || [];
  if (!subs.length) return;
  const dead = [];
  await Promise.all(subs.map(async (raw) => {
    try {
      await webpush.sendNotification(JSON.parse(raw), JSON.stringify(payload), { TTL: 3600, urgency: "high", topic: payload.tag ? payload.tag.replace(/[^A-Za-z0-9_-]/g, "").slice(0, 32) : undefined });
    } catch (e) {
      if (e.statusCode === 404 || e.statusCode === 410 || e.statusCode === 403) dead.push(raw);
      else console.warn("push failed", uid, e.statusCode, e.body);
    }
  }));
  if (dead.length) await ref.update({ subs: admin.firestore.FieldValue.arrayRemove(...dead) }).catch(() => {});
}

exports.onMessage = onDocumentCreated("chats/{chatId}/messages/{msgId}", async (event) => {
  const m = event.data && event.data.data();
  if (!m || !m.by) return;
  const chat = await db.collection("chats").doc(event.params.chatId).get();
  const members = (chat.exists && chat.data().members) || [];
  const name = await nameOf(m.by);
  const body = m.snap ? "hat dir einen Shot geschickt" : m.share ? "hat dir etwas geteilt" : (m.text || "Neue Nachricht").slice(0, 140);
  await Promise.all(members.filter((u) => u !== m.by).map((u) =>
    pushTo(u, { title: name, body, tag: "chat-" + event.params.chatId, url: "./#chat=" + m.by })));
});

exports.onStory = onDocumentCreated("stories/{storyId}", async (event) => {
  const st = event.data && event.data.data();
  if (!st || !st.by) return;
  const u = await db.collection("users").doc(st.by).get();
  if (!u.exists) return;
  const { name = "Jemand", friends = [] } = u.data();
  await Promise.all(friends.map((f) => pushTo(f, { title: name, body: "hat eine neue Story gepostet", tag: "story-" + st.by, url: "./#stories" })));
});

exports.onCall = onDocumentCreated("calls/{callId}", async (event) => {
  const c = event.data && event.data.data();
  if (!c || !c.to || c.status !== "ringing") return;
  const name = await nameOf(c.from);
  await pushTo(c.to, { title: name, body: c.video ? "ruft dich per Video an – öffne shade" : "ruft dich an – öffne shade", tag: "call-" + c.from, url: "./#chat=" + c.from });
});

