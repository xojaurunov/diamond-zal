// Mashq videolari — Cloudflare R2 (`zalpro-files`) oldidagi Worker.
//   POST   /upload        — video yuklash (faqat trener va bosh admin), javob: { url }
//   DELETE /v/<kalit>     — videoni o'chirish (faqat trener va bosh admin)
//   GET    /v/<kalit>     — videoni ko'rsatish (hammaga; `Range` — oldinga surish; keshlanadi)
// Kimligi: Firebase ID token (ilova `Authorization: Bearer` bilan yuboradi). Rol — foydalanuvchining
// o'z Firestore hujjatidan, o'z tokeni bilan o'qiladi. Firebase'ga hech narsa yozilmaydi.

export const MAX_BYTES = 80 * 1024 * 1024;
const TYPES = { 'video/mp4': 'mp4', 'video/quicktime': 'mov', 'video/webm': 'webm', 'video/3gpp': '3gp' };
const KEYS_URL = 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
const STAFF = ['admin', 'owner'];

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
const fail = (status, message) => json({ error: message }, status);

const b64url = (s) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));
const decodePart = (s) => JSON.parse(new TextDecoder().decode(b64url(s)));

let keyCache = { until: 0, keys: {} };

/** Google'ning ochiq kalitlari (kid -> JWK); Cache-Control muddati davomida xotirada */
export async function googleKeys(fetchFn = fetch, now = Date.now()) {
  if (now < keyCache.until) return keyCache.keys;
  const res = await fetchFn(KEYS_URL);
  const age = Number(/max-age=(\d+)/.exec(res.headers.get('cache-control') ?? '')?.[1] ?? 3600);
  const keys = Object.fromEntries((await res.json()).keys.map((k) => [k.kid, k]));
  keyCache = { until: now + age * 1000, keys };
  return keys;
}

/** Firebase ID tokenini tekshiradi; to'g'ri bo'lsa — uid, aks holda null */
export async function verifyToken(token, project, keys, now = Date.now()) {
  try {
    const [h, p, s] = token.split('.');
    const header = decodePart(h);
    const claims = decodePart(p);
    const jwk = keys[header.kid];
    if (header.alg !== 'RS256' || !jwk) return null;
    const key = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false, ['verify']);
    const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, b64url(s),
      new TextEncoder().encode(`${h}.${p}`));
    const sec = now / 1000;
    if (!ok || claims.aud !== project || claims.iss !== `https://securetoken.google.com/${project}`
      || !(claims.exp > sec) || !(claims.iat <= sec + 300) || !claims.sub) return null;
    return claims.sub;
  } catch {
    return null;
  }
}

/** Foydalanuvchining roli — o'z hujjatidan, o'z tokeni bilan (Firestore qoidalari ruxsat beradi) */
export async function firestoreRole(uid, token, project, fetchFn = fetch) {
  const res = await fetchFn(
    `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/users/${uid}`,
    { headers: { authorization: `Bearer ${token}` } });
  if (!res.ok) return null;
  return (await res.json()).fields?.role?.stringValue ?? null;
}

async function staffOnly(request, env, deps) {
  const token = /^Bearer (.+)$/.exec(request.headers.get('authorization') ?? '')?.[1];
  if (!token) return fail(401, 'token yo\'q');
  const uid = await verifyToken(token, env.FIREBASE_PROJECT, await deps.keys(), deps.now());
  if (!uid) return fail(401, 'token noto\'g\'ri');
  const role = await deps.role(uid, token, env.FIREBASE_PROJECT);
  if (!STAFF.includes(role)) return fail(403, 'faqat trener va bosh admin');
  return null;
}

async function upload(request, env, deps) {
  const denied = await staffOnly(request, env, deps);
  if (denied) return denied;
  const type = (request.headers.get('content-type') ?? '').split(';')[0].trim().toLowerCase();
  if (!TYPES[type]) return fail(415, 'faqat video (mp4, mov, webm, 3gp)');
  const size = Number(request.headers.get('content-length'));
  if (!size) return fail(411, 'hajm (Content-Length) kerak');
  if (size > MAX_BYTES) return fail(413, `video ${MAX_BYTES / 1024 / 1024} MB dan katta`);
  const key = `videos/${crypto.randomUUID()}.${TYPES[type]}`;
  const put = await env.BUCKET.put(key, request.body, { httpMetadata: { contentType: type } });
  if (put.size > MAX_BYTES) {
    await env.BUCKET.delete(key);
    return fail(413, 'video katta');
  }
  return json({ url: `${new URL(request.url).origin}/v/${key}` });
}

async function remove(key, request, env, deps) {
  const denied = await staffOnly(request, env, deps);
  if (denied) return denied;
  await env.BUCKET.delete(key);
  // o'chirilgan video keshdan ham ketsin (bir yil keshlanadi). Cache API faqat shu ma'lumot markazini
  // tozalaydi; boshqa joylarda havola taxmin qilib bo'lmaydigan bo'lib qoladi va ilovada ko'rinmaydi.
  if (typeof caches !== 'undefined') {
    await caches.default.delete(new Request(new URL(request.url).toString(), { method: 'GET' }));
  }
  return new Response(null, { status: 204 });
}

/** `Range: bytes=a-b` / `bytes=a-` / `bytes=-n` -> { offset, length } (hajmga moslab) */
export function parseRange(header, size) {
  const m = /^bytes=(\d*)-(\d*)$/.exec(header ?? '');
  if (!m || (m[1] === '' && m[2] === '')) return null;
  let start, end;
  if (m[1] === '') {
    start = Math.max(0, size - Number(m[2]));
    end = size - 1;
  } else {
    start = Number(m[1]);
    end = m[2] === '' ? size - 1 : Math.min(Number(m[2]), size - 1);
  }
  if (start > end || start >= size) return 'invalid';
  return { offset: start, length: end - start + 1 };
}

async function serve(key, request, env, ctx) {
  const cache = typeof caches === 'undefined' ? null : caches.default;
  const hit = cache && await cache.match(request);
  if (hit) return hit;
  const head = await env.BUCKET.head(key);
  if (!head) return fail(404, 'video yo\'q');
  const range = parseRange(request.headers.get('range'), head.size);
  if (range === 'invalid') {
    return new Response(null, { status: 416, headers: { 'content-range': `bytes */${head.size}` } });
  }
  const obj = await env.BUCKET.get(key, range ? { range } : undefined);
  const headers = new Headers({
    'accept-ranges': 'bytes',
    'cache-control': 'public, max-age=31536000, immutable',
    'content-type': head.httpMetadata?.contentType ?? 'video/mp4',
    etag: head.httpEtag,
  });
  if (!range) {
    headers.set('content-length', String(head.size));
    const res = new Response(obj.body, { headers });
    if (cache) ctx?.waitUntil(cache.put(request, res.clone()));
    return res;
  }
  headers.set('content-length', String(range.length));
  headers.set('content-range', `bytes ${range.offset}-${range.offset + range.length - 1}/${head.size}`);
  return new Response(obj.body, { status: 206, headers });
}

export async function handle(request, env, ctx, deps) {
  const url = new URL(request.url);
  const key = url.pathname.startsWith('/v/') ? decodeURIComponent(url.pathname.slice(3)) : null;
  if (key !== null && !/^videos\/[0-9a-f-]{36}\.(mp4|mov|webm|3gp)$/.test(key)) return fail(404, 'yo\'q');
  if (request.method === 'POST' && url.pathname === '/upload') return upload(request, env, deps);
  if (key && request.method === 'DELETE') return remove(key, request, env, deps);
  if (key && (request.method === 'GET' || request.method === 'HEAD')) return serve(key, request, env, ctx);
  return fail(404, 'yo\'q');
}

export default {
  fetch: (request, env, ctx) => handle(request, env, ctx, {
    keys: () => googleKeys(),
    role: (uid, token, project) => firestoreRole(uid, token, project),
    now: () => Date.now(),
  }),
};
