// node --test cloudflare/video/test — tarmoqsiz: soxta R2, o'zimiz yaratgan RSA kalit bilan soxta token.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handle, parseRange, MAX_BYTES } from '../src/index.js';

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
    async delete(key) { files.delete(key); },
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
