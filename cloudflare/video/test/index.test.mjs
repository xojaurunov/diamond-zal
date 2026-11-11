// node --test cloudflare/video/test — tarmoqsiz: soxta R2, o'zimiz yaratgan RSA kalit bilan soxta token.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handle, parseRange, MAX_BYTES, MAX_AVATAR_BYTES, MAX_PHOTO_BYTES } from '../src/index.js';

const PROJECT = 'kotta-qani-09111753';
const NOW = 1_800_000_000_000;
const ROLES = { owner1: 'owner', trainer1: 'admin', user1: 'user', barmen1: 'barmen' };

const pair = await crypto.subtle.generateKey(
  { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
  true, ['sign', 'verify']);
const other = await crypto.subtle.generateKey(
  { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
  true, ['sign', 'verify']);
const jwk = { ...(await crypto.subtle.exportKey('jwk', pair.publicKey)), kid: 'k1' };

const b64url = (bytes) => Buffer.from(bytes).toString('base64url');
async function token(uid, { key = pair.privateKey, exp = NOW / 1000 + 3600, aud = PROJECT } = {}) {
  const h = b64url(JSON.stringify({ alg: 'RS256', kid: 'k1' }));
  const p = b64url(JSON.stringify({
    sub: uid, aud, iss: `https://securetoken.google.com/${aud}`, iat: NOW / 1000 - 10, exp }));
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${h}.${p}`));
  return `${h}.${p}.${b64url(new Uint8Array(sig))}`;
}

function bucket() {
  const files = new Map();
  return {
    files,
    async put(key, body, opts) {
      const data = new Uint8Array(await new Response(body).arrayBuffer());
      files.set(key, { data, contentType: opts.httpMetadata.contentType });
      return { size: data.length };
    },
    async head(key) {
      const f = files.get(key);
      return f && { size: f.data.length, httpEtag: '"e"', httpMetadata: { contentType: f.contentType } };
    },
    async get(key, opts) {
      const f = files.get(key);
      const r = opts?.range;
      return f && { body: r ? f.data.slice(r.offset, r.offset + r.length) : f.data };
    },
    async delete(keys) { for (const k of [].concat(keys)) files.delete(k); },
    async list({ prefix }) {
      return { objects: [...files.keys()].filter((k) => k.startsWith(prefix)).map((key) => ({ key })) };
    },
  };
}

const env = () => ({ FIREBASE_PROJECT: PROJECT, BUCKET: bucket() });
const deps = { keys: async () => ({ k1: jwk }), role: async (uid) => ROLES[uid] ?? null, now: () => NOW };
const BASE = 'https://qobil-video.example.workers.dev';

async function upload(e, auth, { type = 'video/mp4', size = 1000 } = {}) {
  const headers = { 'content-type': type, 'content-length': String(size) };
  if (auth) headers.authorization = `Bearer ${auth}`;
  return handle(new Request(`${BASE}/upload`, { method: 'POST', headers, body: new Uint8Array(size).fill(7) }),
    e, null, deps);
}

test('token yoq — 401', async () => {
  assert.equal((await upload(env(), null)).status, 401);
});

test('soxta imzo, muddati otgan, boshqa loyiha — 401', async () => {
  assert.equal((await upload(env(), await token('trainer1', { key: other.privateKey }))).status, 401);
  assert.equal((await upload(env(), await token('trainer1', { exp: NOW / 1000 - 1 }))).status, 401);
  assert.equal((await upload(env(), await token('trainer1', { aud: 'boshqa-loyiha' }))).status, 401);
  assert.equal((await upload(env(), 'buzuq.token.xx')).status, 401);
});

test('shogird va barmen yuklay olmaydi — 403', async () => {
  assert.equal((await upload(env(), await token('user1'))).status, 403);
  assert.equal((await upload(env(), await token('barmen1'))).status, 403);
  assert.equal((await upload(env(), await token('notanish'))).status, 403);
});

test('trener yuklaydi — R2 da fayl, havola qaytadi', async () => {
  const e = env();
  const res = await upload(e, await token('trainer1'));
  assert.equal(res.status, 200);
  const { url } = await res.json();
  assert.match(url, /^https:\/\/qobil-video\.example\.workers\.dev\/v\/videos\/[0-9a-f-]{36}\.mp4$/);
  const [key] = e.BUCKET.files.keys();
  assert.equal(e.BUCKET.files.get(key).data.length, 1000);
});

test('bosh admin ham yuklaydi', async () => {
  assert.equal((await upload(env(), await token('owner1'))).status, 200);
});

test('50 MB dan katta — 413, video emas — 415', async () => {
  const t = await token('trainer1');
  const e = env();
  const big = await handle(new Request(`${BASE}/upload`, {
    method: 'POST',
    headers: { authorization: `Bearer ${t}`, 'content-type': 'video/mp4', 'content-length': String(MAX_BYTES + 1) },
    body: new Uint8Array(1),
  }), e, null, deps);
  assert.equal(big.status, 413);
  assert.equal((await upload(e, t, { type: 'image/png' })).status, 415);
  assert.equal(e.BUCKET.files.size, 0);
});

test('korish: toliq, Range bilan 206, notogri Range 416', async () => {
  const e = env();
  const { url } = await (await upload(e, await token('trainer1'))).json();
  const full = await handle(new Request(url), e, null, deps);
  assert.equal(full.status, 200);
  assert.equal(full.headers.get('accept-ranges'), 'bytes');
  assert.equal((await full.arrayBuffer()).byteLength, 1000);
  const part = await handle(new Request(url, { headers: { range: 'bytes=0-99' } }), e, null, deps);
  assert.equal(part.status, 206);
  assert.equal(part.headers.get('content-range'), 'bytes 0-99/1000');
  assert.equal((await part.arrayBuffer()).byteLength, 100);
  const bad = await handle(new Request(url, { headers: { range: 'bytes=5000-' } }), e, null, deps);
  assert.equal(bad.status, 416);
});

test('ochirish: shogird 403, trener 204, keyin 404', async () => {
  const e = env();
  const { url } = await (await upload(e, await token('trainer1'))).json();
  const del = async (uid) => handle(new Request(url, {
    method: 'DELETE', headers: { authorization: `Bearer ${await token(uid)}` } }), e, null, deps);
  assert.equal((await del('user1')).status, 403);
  assert.equal(e.BUCKET.files.size, 1);
  assert.equal((await del('trainer1')).status, 204);
  assert.equal(e.BUCKET.files.size, 0);
  assert.equal((await handle(new Request(url), e, null, deps)).status, 404);
});

test('begona kalit (bucket ichidagi boshqa fayl) ochilmaydi', async () => {
  const e = env();
  e.BUCKET.files.set('maxfiy/hujjat.pdf', { data: new Uint8Array(3), contentType: 'application/pdf' });
  assert.equal((await handle(new Request(`${BASE}/v/maxfiy/hujjat.pdf`), e, null, deps)).status, 404);
  assert.equal((await handle(new Request(`${BASE}/v/..%2Fmaxfiy%2Fhujjat.pdf`), e, null, deps)).status, 404);
});

test('parseRange', () => {
  assert.deepEqual(parseRange('bytes=0-99', 1000), { offset: 0, length: 100 });
  assert.deepEqual(parseRange('bytes=900-', 1000), { offset: 900, length: 100 });
  assert.deepEqual(parseRange('bytes=-10', 1000), { offset: 990, length: 10 });
  assert.deepEqual(parseRange('bytes=0-5000', 1000), { offset: 0, length: 1000 });
  assert.equal(parseRange('bytes=1000-', 1000), 'invalid');
  assert.equal(parseRange(null, 1000), null);
});

test("muqova: trener qo'yadi, shogird yo'q, JPEG emas 415, katta 413; video o'chsa muqova ham", async () => {
  const e = env();
  const { url } = await (await upload(e, await token('trainer1'))).json();
  const thumb = url.replace(/\.mp4$/, '.jpg');
  const put = async (uid, type = 'image/jpeg', size = 1000) => handle(new Request(thumb, {
    method: 'PUT', headers: { authorization: `Bearer ${await token(uid)}`, 'content-type': type },
    body: new Uint8Array(size) }), e, null, deps);
  assert.equal((await put('user1')).status, 403);
  assert.equal((await put('trainer1', 'image/png')).status, 415);
  assert.equal((await put('trainer1', 'image/jpeg', 600 * 1024)).status, 413);
  assert.equal((await put('trainer1')).status, 204);
  const got = await handle(new Request(thumb), e, null, deps);
  assert.equal(got.status, 200);
  assert.equal(got.headers.get('content-type'), 'image/jpeg');
  const del = await handle(new Request(url, {
    method: 'DELETE', headers: { authorization: `Bearer ${await token('trainer1')}` } }), e, null, deps);
  assert.equal(del.status, 204);
  assert.equal(e.BUCKET.files.size, 0, "video va muqova ikkalasi ham o'chdi");
});

// ---------- profil rasmi (/avatar) ----------

async function avatar(e, uid, { method = 'POST', type = 'image/jpeg', size = 2000, auth = true } = {}) {
  const headers = {};
  if (auth) headers.authorization = `Bearer ${typeof auth === 'string' ? auth : await token(uid)}`;
  const init = { method, headers };
  if (method === 'POST') {
    headers['content-type'] = type;
    headers['content-length'] = String(size);
    init.body = new Uint8Array(size).fill(9);
  }
  return handle(new Request(`${BASE}/avatar`, init), e, null, deps);
}

test('avatar: tokensiz va soxta token — 401', async () => {
  const e = env();
  assert.equal((await avatar(e, 'user1', { auth: false })).status, 401);
  assert.equal((await avatar(e, 'user1', { auth: 'buzuq.token.xx' })).status, 401);
  assert.equal((await avatar(e, 'user1', { method: 'DELETE', auth: false })).status, 401);
  assert.equal(e.BUCKET.files.size, 0);
});

test("avatar: har qanday rol o'ziga yuklaydi, havola avatars/<uid>/ ostida va ochiladi", async () => {
  for (const uid of ['user1', 'barmen1', 'trainer1', 'owner1', 'notanish']) {
    const e = env();
    const res = await avatar(e, uid);
    assert.equal(res.status, 200, uid);
    assert.equal(res.headers.get('access-control-allow-origin'), '*');
    const { url } = await res.json();
    assert.match(url, new RegExp(`^${BASE.replace(/\./g, '\.')}/v/avatars/${uid}/[0-9a-f-]{36}\.jpg$`));
    const got = await handle(new Request(url), e, null, deps);
    assert.equal(got.status, 200);
    assert.equal(got.headers.get('content-type'), 'image/jpeg');
    assert.equal(got.headers.get('access-control-allow-origin'), '*');
    assert.equal((await got.arrayBuffer()).byteLength, 2000);
  }
});

test("avatar: yangisi yuklansa eskisi o'chadi; PNG va WebP — o'z kengaytmasi bilan", async () => {
  const e = env();
  const first = (await (await avatar(e, 'user1')).json()).url;
  const second = (await (await avatar(e, 'user1', { type: 'image/png' })).json()).url;
  assert.match(second, /\.png$/);
  assert.equal(e.BUCKET.files.size, 1);
  assert.equal((await handle(new Request(first), e, null, deps)).status, 404);
  assert.match((await (await avatar(e, 'user1', { type: 'image/webp' })).json()).url, /\.webp$/);
  assert.equal(e.BUCKET.files.size, 1);
});

test('avatar: katta 413, rasm emas 415, hajmsiz 411', async () => {
  const e = env();
  assert.equal((await avatar(e, 'user1', { size: MAX_AVATAR_BYTES + 1 })).status, 413);
  assert.equal((await avatar(e, 'user1', { type: 'video/mp4' })).status, 415);
  assert.equal((await avatar(e, 'user1', { type: 'image/svg+xml' })).status, 415);
  const noLen = await handle(new Request(`${BASE}/avatar`, {
    method: 'POST', headers: { authorization: `Bearer ${await token('user1')}`, 'content-type': 'image/jpeg' },
  }), e, null, deps);
  assert.equal(noLen.status, 411);
  assert.equal(e.BUCKET.files.size, 0);
});

test("avatar: meros kalit turi (constructor, __proto__) — 415, eski rasm o'chmaydi", async () => {
  const e = env();
  await avatar(e, 'user1');
  for (const type of ['constructor', '__proto__', 'tostring', 'hasownproperty']) {
    assert.equal((await avatar(e, 'user1', { type })).status, 415, type);
  }
  assert.equal(e.BUCKET.files.size, 1);
});

test("avatar: DELETE faqat o'zinikini o'chiradi", async () => {
  const e = env();
  await avatar(e, 'user1');
  const theirs = (await (await avatar(e, 'trainer1')).json()).url;
  const del = await avatar(e, 'user1', { method: 'DELETE' });
  assert.equal(del.status, 204);
  assert.equal(e.BUCKET.files.size, 1);
  assert.equal((await handle(new Request(theirs), e, null, deps)).status, 200);
  // rasmi yo'q odam o'chirsa ham — 204
  assert.equal((await avatar(e, 'user1', { method: 'DELETE' })).status, 204);
});

test("avatar: /v/avatars/... ni PUT/DELETE bilan o'zgartirib bo'lmaydi (bosh admin ham)", async () => {
  const e = env();
  const url = (await (await avatar(e, 'user1')).json()).url;
  for (const uid of ['owner1', 'trainer1']) {
    const t = `Bearer ${await token(uid)}`;
    const del = await handle(new Request(url, { method: 'DELETE', headers: { authorization: t } }), e, null, deps);
    assert.equal(del.status, 404);
    const put = await handle(new Request(url, {
      method: 'PUT', headers: { authorization: t, 'content-type': 'image/jpeg' }, body: new Uint8Array(10),
    }), e, null, deps);
    assert.equal(put.status, 404);
  }
  assert.equal(e.BUCKET.files.get(new URL(url).pathname.slice(3)).data.length, 2000);
});

test("avatar: begona yo'l ochilmaydi; brauzer preflight (OPTIONS) — 204 va CORS", async () => {
  const e = env();
  e.BUCKET.files.set('avatars/user1/x.jpg', { data: new Uint8Array(3), contentType: 'image/jpeg' });
  assert.equal((await handle(new Request(`${BASE}/v/avatars/user1/x.jpg`), e, null, deps)).status, 404);
  assert.equal((await handle(new Request(`${BASE}/v/avatars/..%2Fvideos%2Fa.mp4`), e, null, deps)).status, 404);
  const pre = await handle(new Request(`${BASE}/avatar`, { method: 'OPTIONS' }), e, null, deps);
  assert.equal(pre.status, 204);
  assert.equal(pre.headers.get('access-control-allow-origin'), '*');
  assert.match(pre.headers.get('access-control-allow-headers'), /authorization/);
  assert.equal((await handle(new Request(`${BASE}/avatar`, { method: 'GET' }), e, null, deps)).status, 405);
});

test("avatar yo'li video ruxsatini o'zgartirmadi: shogird video yuklay olmaydi", async () => {
  assert.equal((await upload(env(), await token('user1'))).status, 403);
});

// ---------- progress ("oldin / keyin") rasmlari ----------
// Soxta Firestore: hujjatlar va ko'rish ruxsati (qoidalar o'rnida): o'zi, treneri (trainer1 — user1 ning), bosh admin
const PHOTO_DOCS = new Map();
const MAY_READ = (viewer, owner) => viewer === owner || viewer === 'owner1' || (viewer === 'trainer1' && owner === 'user1');
const photoDeps = {
  ...deps,
  photo: async (uid, id, tok) => {
    const viewer = JSON.parse(Buffer.from(tok.split('.')[1], 'base64url')).sub;
    if (!MAY_READ(viewer, uid)) return { status: 403 };
    const d = PHOTO_DOCS.get(`${uid}/${id}`);
    return d ? { status: 200, key: d } : { status: 404 };
  },
};

// rasm baytlari: boshida tur belgisi (JPEG FF D8 FF, WebP RIFF....WEBP), qolgani to'ldirilgan
function photoBytes(size, magic) {
  const b = new Uint8Array(size).fill(5);
  if (size < 12) return b;
  if (magic === 'image/jpeg') b.set([0xff, 0xd8, 0xff]);
  if (magic === 'image/webp') b.set([...'RIFF'].map((c) => c.charCodeAt(0)).concat([0, 0, 0, 0],
    [...'WEBP'].map((c) => c.charCodeAt(0))));
  return b;
}

async function photoPost(e, uid, { type = 'image/jpeg', size = 3000, auth = true, magic = type } = {}) {
  const headers = { 'content-type': type, 'content-length': String(size) };
  if (auth) headers.authorization = `Bearer ${auth === true ? await token(uid) : auth}`;
  return handle(new Request(`${BASE}/photo`, { method: 'POST', headers, body: photoBytes(size, magic) }),
    e, null, photoDeps);
}

test('progress rasmi: tur baytlarga mos bolmasa 415; korishda nosniff; buzuq % — 404', async () => {
  const e = env();
  assert.equal((await photoPost(e, 'user1', { magic: null })).status, 415);
  assert.equal((await photoPost(e, 'user1', { type: 'image/jpeg', magic: 'image/webp' })).status, 415);
  assert.equal(e.BUCKET.files.size, 0);
  const { key } = await (await photoPost(e, 'user1')).json();
  PHOTO_DOCS.set('user1/doc9', key);
  assert.equal((await photoGet(e, 'user1', 'user1', 'doc9')).headers.get('x-content-type-options'), 'nosniff');
  const bad = await handle(new Request(`${BASE}/photo/%E0%A4%A`, {
    method: 'DELETE', headers: { authorization: `Bearer ${await token('user1')}` } }), e, null, photoDeps);
  assert.equal(bad.status, 404);
});
async function photoGet(e, viewer, owner, id) {
  const headers = viewer ? { authorization: `Bearer ${await token(viewer)}` } : {};
  return handle(new Request(`${BASE}/p/${owner}/${id}`, { headers }), e, null, photoDeps);
}
async function photoDelete(e, uid, key) {
  return handle(new Request(`${BASE}/photo/${encodeURIComponent(key)}`, {
    method: 'DELETE', headers: { authorization: `Bearer ${await token(uid)}` } }), e, null, photoDeps);
}

test("progress rasmi: o'ziga yuklaydi, kalit photos/<uid>/ ostida, ommaviy havola yo'q", async () => {
  const e = env();
  const res = await photoPost(e, 'user1');
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('access-control-allow-origin'), '*');
  const { key, url } = await res.json();
  assert.equal(url, undefined);
  assert.match(key, /^photos\/user1\/[0-9a-f-]{36}\.jpg$/);
  assert.equal(e.BUCKET.files.get(key).data.length, 3000);
  // /v/ orqali (ommaviy yo'l) ochilmaydi
  assert.equal((await handle(new Request(`${BASE}/v/${key}`), e, null, photoDeps)).status, 404);
  const webp = await (await photoPost(e, 'user1', { type: 'image/webp' })).json();
  assert.match(webp.key, /\.webp$/);
});

test('progress rasmi yuklash: tokensiz 401, PNG/video 415, 1 MB dan katta 413, hajmsiz 411', async () => {
  const e = env();
  assert.equal((await photoPost(e, 'user1', { auth: false })).status, 401);
  assert.equal((await photoPost(e, 'user1', { auth: 'buzuq.token.xx' })).status, 401);
  assert.equal((await photoPost(e, 'user1', { type: 'image/png' })).status, 415);
  assert.equal((await photoPost(e, 'user1', { type: 'constructor' })).status, 415);
  assert.equal((await photoPost(e, 'user1', { size: MAX_PHOTO_BYTES + 1 })).status, 413);
  assert.equal((await photoPost(e, 'user1', { size: 0 })).status, 411);
  assert.equal(e.BUCKET.files.size, 0);
});

test("progress rasmini ko'rish: o'zi, treneri, bosh admin — ha; boshqa shogird, tokensiz — yo'q", async () => {
  const e = env();
  const { key } = await (await photoPost(e, 'user1')).json();
  PHOTO_DOCS.set('user1/doc1', key);
  for (const v of ['user1', 'trainer1', 'owner1']) {
    const res = await photoGet(e, v, 'user1', 'doc1');
    assert.equal(res.status, 200, v);
    assert.equal(res.headers.get('content-type'), 'image/jpeg');
    assert.equal(res.headers.get('cache-control'), 'private, no-store');
    assert.equal((await res.arrayBuffer()).byteLength, 3000);
  }
  assert.equal((await photoGet(e, 'user2', 'user1', 'doc1')).status, 403);
  assert.equal((await photoGet(e, 'barmen1', 'user1', 'doc1')).status, 403);
  assert.equal((await photoGet(e, null, 'user1', 'doc1')).status, 401);
  assert.equal((await photoGet(e, 'user1', 'user1', 'yoq')).status, 404);
});

test("progress rasmi: hujjatdagi kalit boshqa papkada yoki kalitsiz (eski shakl) — 404", async () => {
  const e = env();
  const { key } = await (await photoPost(e, 'user2')).json();
  PHOTO_DOCS.set('user1/doc2', key); // user1 hujjatiga user2 rasmi kaliti
  assert.equal((await photoGet(e, 'user1', 'user1', 'doc2')).status, 404);
  PHOTO_DOCS.set('user1/doc3', null); // eski shakl: rasm hujjat ichida
  assert.equal((await photoGet(e, 'user1', 'user1', 'doc3')).status, 404);
  PHOTO_DOCS.set('user1/doc4', 'avatars/user1/x.jpg');
  assert.equal((await photoGet(e, 'user1', 'user1', 'doc4')).status, 404);
  assert.equal((await handle(new Request(`${BASE}/p/user1/doc1/ortiqcha`), e, null, photoDeps)).status, 404);
  assert.equal((await handle(new Request(`${BASE}/p/..%2Fx/doc1`), e, null, photoDeps)).status, 404);
});

test("progress rasmini o'chirish: faqat egasi; preflight va noto'g'ri usul", async () => {
  const e = env();
  const { key } = await (await photoPost(e, 'user1')).json();
  assert.equal((await photoDelete(e, 'trainer1', key)).status, 403);
  assert.equal((await photoDelete(e, 'owner1', key)).status, 403);
  assert.ok(e.BUCKET.files.has(key));
  assert.equal((await photoDelete(e, 'user1', 'videos/x.mp4')).status, 404);
  assert.equal((await photoDelete(e, 'user1', key)).status, 204);
  assert.ok(!e.BUCKET.files.has(key));
  const pre = await handle(new Request(`${BASE}/p/user1/doc1`, { method: 'OPTIONS' }), e, null, photoDeps);
  assert.equal(pre.status, 204);
  assert.match(pre.headers.get('access-control-allow-methods'), /GET/);
  assert.equal((await handle(new Request(`${BASE}/photo`, { method: 'GET' }), e, null, photoDeps)).status, 405);
});

test("progress yo'llari video va avatar ruxsatlarini o'zgartirmadi", async () => {
  assert.equal((await upload(env(), await token('user1'))).status, 403);
  const e = env();
  assert.equal((await avatar(e, 'user1')).status, 200);
});
