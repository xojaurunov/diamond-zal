// firestore.rules ni lokal emulyatorda sinaydi (haqiqiy bazaga tegmaydi).
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, addDoc, collection, query, where,
  writeBatch, serverTimestamp,
} from 'firebase/firestore';

const RULES = readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8');

const OWNER = 'owner1';
const TRAINER = 'trainer1';
const TRAINER2 = 'trainer2';
const TRAINER3 = 'trainer3'; // boshqa trener — USER unga tegishli emas
const USER = 'user1'; // TRAINER ning shogirdi
const USER2 = 'user2';
const USER3 = 'user3'; // TRAINER3 ning shogirdi
const USER4 = 'user4'; // hali trener tanlamagan
const USER5 = 'user5'; // hali trener tanlamagan
const TRAINER4 = 'trainer4'; // shogird qabul qiladigan ikkinchi trener
const W1 = 'w1', W2 = 'w2', W3 = 'w3';
const BARMEN = 'barmen1';

let pass = 0, fail = 0;
async function check(name, fn) {
  try { await fn(); console.log('  OK   ' + name); pass++; }
  catch (e) { console.log('  XATO ' + name + '\n         ' + String(e.message).split('\n')[0]); fail++; }
}

const env = await initializeTestEnvironment({
  projectId: 'demo-rules-test',
  firestore: { rules: RULES, host: '127.0.0.1', port: 8085 },
});

await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'users', OWNER), { name: 'Egasi', role: 'owner', phone: '998900000000', planId: null, trainerId: null });
  await setDoc(doc(db, 'users', TRAINER), { name: 'Trener', role: 'admin', phone: '998901111111', planId: null, trainerId: null });
  await setDoc(doc(db, 'users', TRAINER2), { name: 'Trener2', role: 'admin', phone: '998902222222', planId: null, trainerId: null });
  await setDoc(doc(db, 'users', TRAINER3), { name: 'Trener3', role: 'admin', phone: '998908888888', planId: null, trainerId: null });
  await setDoc(doc(db, 'users', USER), { name: 'Shogird', role: 'user', phone: '998903333333', planId: null, trainerId: TRAINER, weight: 80 });
  await setDoc(doc(db, 'users', USER2), { name: 'Eski', role: 'user', phone: '998904444444', planId: null });
  await setDoc(doc(db, 'users', USER3), { name: 'Boshqaning shogirdi', role: 'user', phone: '998909999999', planId: null, trainerId: TRAINER3 });
  await setDoc(doc(db, 'users', USER4), { name: 'Yangi shogird', role: 'user', phone: '998901010101', planId: null, trainerId: null });
  await setDoc(doc(db, 'users', USER5), { name: 'Yana yangi', role: 'user', phone: '998902020202', planId: null, trainerId: null });
  await setDoc(doc(db, 'trainers', TRAINER), { name: 'Trener', bio: '', accepting: true });
  await setDoc(doc(db, 'trainers', TRAINER3), { name: 'Trener3', bio: '', accepting: false });
  await setDoc(doc(db, 'users', TRAINER4), { name: 'Trener4', role: 'admin', phone: '998903030303' });
  await setDoc(doc(db, 'trainers', TRAINER4), { name: 'Trener4', bio: '', accepting: true });
  // vazn testlari: W1 — hali o'lchov yo'q, W2 — oxirgi o'lchov 8 kun oldin, W3 — anketa to'ldirmagan
  await setDoc(doc(db, 'users', W1), { name: 'W1', role: 'user', weight: 72, trainerId: null });
  await setDoc(doc(db, 'users', W2), { name: 'W2', role: 'user', weight: 90, trainerId: null,
    lastWeighIn: new Date(Date.now() - 8 * 24 * 3600 * 1000) });
  await setDoc(doc(db, 'users', W3), { name: 'W3', role: 'user', weight: 0, trainerId: null });
  await setDoc(doc(db, 'users', BARMEN), { name: 'Barmen', role: 'barmen', phone: '998905050505' });
  await setDoc(doc(db, 'users', USER, 'days', '2026-09-15'), { done: [0] });
  await setDoc(doc(db, 'plans', 'p1'), { title: 'Reja', meals: [] });
  await setDoc(doc(db, 'foods', 'f1'), { name: 'Tovuq', kcal: 165 });
});

const as = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

console.log('\n== ROL OZGARTIRISH ==');
await check('bosh admin foydalanuvchini trener qiladi', () =>
  assertSucceeds(updateDoc(doc(as(OWNER), 'users', USER2), { role: 'admin' })));
await check('bosh admin trenerni tushiradi', () =>
  assertSucceeds(updateDoc(doc(as(OWNER), 'users', TRAINER2), { role: 'user' })));
await check('TRENER rol ozgartira OLMAYDI', () =>
  assertFails(updateDoc(doc(as(TRAINER), 'users', USER), { role: 'admin' })));
await check('trener ozini bosh admin qila OLMAYDI', () =>
  assertFails(updateDoc(doc(as(TRAINER), 'users', TRAINER), { role: 'owner' })));
await check('shogird ozini trener qila OLMAYDI', () =>
  assertFails(updateDoc(doc(as(USER), 'users', USER), { role: 'admin' })));
await check('bosh admin boshqani BOSH ADMIN qiladi', () =>
  assertSucceeds(updateDoc(doc(as(OWNER), 'users', TRAINER), { role: 'owner' })));
await check('bosh admin boshqa bosh adminni trenerga tushiradi', () =>
  assertSucceeds(updateDoc(doc(as(OWNER), 'users', TRAINER), { role: 'admin' })));
await check('trener boshqani bosh admin qila OLMAYDI', () =>
  assertFails(updateDoc(doc(as(TRAINER), 'users', USER), { role: 'owner' })));

console.log('\n== OCHIRISH ==');
await check('bosh admin akkauntni ochiradi', () =>
  assertSucceeds(deleteDoc(doc(as(OWNER), 'users', USER2))));
await check('trener ochira OLMAYDI', () =>
  assertFails(deleteDoc(doc(as(TRAINER), 'users', USER))));
await check('shogird ozini ochira OLMAYDI', () =>
  assertFails(deleteDoc(doc(as(USER), 'users', USER))));

console.log('\n== TRENER BIRIKTIRISH ==');
await check('bosh admin trener biriktiradi', () =>
  assertSucceeds(updateDoc(doc(as(OWNER), 'users', USER), { trainerId: TRAINER3 })));
await check('bosh admin qaytarib biriktiradi', () =>
  assertSucceeds(updateDoc(doc(as(OWNER), 'users', USER), { trainerId: TRAINER })));
await check('trener oz shogirdini boshqa trenerga bera OLMAYDI', () =>
  assertFails(updateDoc(doc(as(TRAINER), 'users', USER), { trainerId: TRAINER3 })));
await check('trener BOSHQANING shogirdini oziga ola OLMAYDI', () =>
  assertFails(updateDoc(doc(as(TRAINER), 'users', USER3), { trainerId: TRAINER })));
await check('shogird oz trenerini ozgartira OLMAYDI', () =>
  assertFails(updateDoc(doc(as(USER), 'users', USER), { trainerId: TRAINER3 })));

console.log('\n== SHOGIRD OZ MALUMOTI ==');
await check('shogird vaznni olchovsiz (batchsiz) ozgartira OLMAYDI', () =>
  assertFails(updateDoc(doc(as(USER), 'users', USER), { weight: 78 })));
await check('shogird oziga reja biriktira OLMAYDI', () =>
  assertFails(updateDoc(doc(as(USER), 'users', USER), { planId: 'p1' })));
await check('trener oz shogirdiga reja biriktiradi', () =>
  assertSucceeds(updateDoc(doc(as(TRAINER), 'users', USER), { planId: 'p1', planAssignedAt: new Date() })));
await check('trener BOSHQANING shogirdiga reja bera OLMAYDI', () =>
  assertFails(updateDoc(doc(as(TRAINER), 'users', USER3), { planId: 'p1' })));
await check('shogird reja berilgan vaqtni ozgartira OLMAYDI', () =>
  assertFails(updateDoc(doc(as(USER), 'users', USER), { planAssignedAt: new Date(2020, 0, 1) })));
await check('shogird oz maqsadi va metabolizmini tanlaydi', () =>
  assertSucceeds(updateDoc(doc(as(USER), 'users', USER), { goal: 'gain', metabolism: 'fast' })));
await check('trener oz shogirdi maqsadini belgilaydi', () =>
  assertSucceeds(updateDoc(doc(as(TRAINER), 'users', USER), { goal: 'lose' })));

console.log('\n== OQISH ==');
await check('shogird oz hujjatini oqiydi', () =>
  assertSucceeds(getDoc(doc(as(USER), 'users', USER))));
await check('shogird BOSHQANI oqiy OLMAYDI', () =>
  assertFails(getDoc(doc(as(USER), 'users', TRAINER))));
await check('trener oz shogirdini oqiydi', () =>
  assertSucceeds(getDoc(doc(as(TRAINER), 'users', USER))));
await check('trener BOSHQANING shogirdini oqiy OLMAYDI', () =>
  assertFails(getDoc(doc(as(TRAINER), 'users', USER3))));
await check('trener oz shogirdlari royxatini oladi', () =>
  assertSucceeds(getDocs(query(collection(as(TRAINER), 'users'), where('trainerId', '==', TRAINER)))));
await check('trener HAMMA shogird royxatini ola OLMAYDI', () =>
  assertFails(getDocs(query(collection(as(TRAINER), 'users'), where('role', '==', 'user')))));
await check('trener xodimlar royxatini ola OLMAYDI (bosh admin korinmaydi)', () =>
  assertFails(getDocs(query(collection(as(TRAINER), 'users'), where('role', 'in', ['admin', 'owner'])))));
await check('trener bosh admin hujjatini oqiy OLMAYDI', () =>
  assertFails(getDoc(doc(as(TRAINER), 'users', OWNER))));
await check('trener boshqa trener hujjatini oqiy OLMAYDI', () =>
  assertFails(getDoc(doc(as(TRAINER), 'users', TRAINER3))));
await check('bosh admin hamma shogirdni oladi', () =>
  assertSucceeds(getDocs(query(collection(as(OWNER), 'users'), where('role', '==', 'user')))));
await check('bosh admin hammani oqiydi', () =>
  assertSucceeds(getDoc(doc(as(OWNER), 'users', USER3))));
await check('kirmagan odam oqiy OLMAYDI', () =>
  assertFails(getDoc(doc(anon(), 'users', USER))));
await check('trener oz shogirdi kunlarini oqiydi', () =>
  assertSucceeds(getDoc(doc(as(TRAINER), 'users', USER, 'days', '2026-09-15'))));
await check('boshqa trener kunlarni oqiy OLMAYDI', () =>
  assertFails(getDoc(doc(as(TRAINER3), 'users', USER, 'days', '2026-09-15'))));
await check('bosh admin kunlarni oqiydi (reyting)', () =>
  assertSucceeds(getDoc(doc(as(OWNER), 'users', USER, 'days', '2026-09-15'))));

console.log('\n== REJA VA MAHSULOT ==');
await check('trener reja yozadi', () =>
  assertSucceeds(setDoc(doc(as(TRAINER), 'plans', 'p2'), { title: 'Yangi', meals: [] })));
await check('bosh admin mahsulot yozadi', () =>
  assertSucceeds(setDoc(doc(as(OWNER), 'foods', 'f2'), { name: 'Guruch', kcal: 130 })));
await check('shogird reja yoza OLMAYDI', () =>
  assertFails(setDoc(doc(as(USER), 'plans', 'p3'), { title: 'Ozim', meals: [] })));
await check('shogird rejani oqiydi', () =>
  assertSucceeds(getDoc(doc(as(USER), 'plans', 'p1'))));

console.log('\n== CHAT ==');
await check('shogird oz chatiga yozadi', () =>
  assertSucceeds(addDoc(collection(as(USER), 'chats', USER, 'messages'), { senderId: USER, text: 'salom' })));
await check('trener oz shogirdi chatiga yozadi', () =>
  assertSucceeds(addDoc(collection(as(TRAINER), 'chats', USER, 'messages'), { senderId: TRAINER, text: 'javob' })));
await check('boshqa trener shogird chatiga yoza OLMAYDI', () =>
  assertFails(addDoc(collection(as(TRAINER3), 'chats', USER, 'messages'), { senderId: TRAINER3, text: 'x' })));
await check('bosh admin istalgan chatga yozadi', () =>
  assertSucceeds(addDoc(collection(as(OWNER), 'chats', USER3, 'messages'), { senderId: OWNER, text: 'salom' })));
await check('shogird BOSHQANING chatiga yoza OLMAYDI', () =>
  assertFails(addDoc(collection(as(USER), 'chats', TRAINER, 'messages'), { senderId: USER, text: 'x' })));
await check('boshqa nom bilan yoza OLMAYDI', () =>
  assertFails(addDoc(collection(as(USER), 'chats', USER, 'messages'), { senderId: TRAINER, text: 'soxta' })));

console.log('\n== TRENER KATALOGI VA TRENER TANLASH ==');
await check('shogird trenerlar katalogini oqiydi', () =>
  assertSucceeds(getDocs(collection(as(USER4), 'trainers'))));
await check('shogird trenerini ozi tanlaydi (hali treneri yoq)', () =>
  assertSucceeds(updateDoc(doc(as(USER4), 'users', USER4), { trainerId: TRAINER })));
await check('shogird qabul qilmayotgan trenerga ota OLMAYDI', () =>
  assertFails(updateDoc(doc(as(USER4), 'users', USER4), { trainerId: TRAINER3 })));
await check('shogird qabul qilmayotgan trenerni tanlay OLMAYDI', () =>
  assertFails(updateDoc(doc(as(USER5), 'users', USER5), { trainerId: TRAINER3 })));
await check('shogird katalogda yoq odamni (bosh adminni) tanlay OLMAYDI', () =>
  assertFails(updateDoc(doc(as(USER5), 'users', USER5), { trainerId: OWNER })));
await check('trener tanlagan shogirdini koradi', () =>
  assertSucceeds(getDoc(doc(as(TRAINER), 'users', USER4))));
await check('trener oz katalog yozuvini ozgartiradi', () =>
  assertSucceeds(setDoc(doc(as(TRAINER), 'trainers', TRAINER), { name: 'Ali trener', bio: '5 yil tajriba', accepting: false })));
await check('trener BOSHQA trener yozuvini ozgartira OLMAYDI', () =>
  assertFails(setDoc(doc(as(TRAINER), 'trainers', TRAINER3), { name: 'X', bio: '', accepting: true })));
await check('trener yozuviga ortiqcha maydon (telefon) qosha OLMAYDI', () =>
  assertFails(setDoc(doc(as(TRAINER), 'trainers', TRAINER), { name: 'A', bio: '', accepting: true, phone: '998' })));
await check('bosh admin trener sozlamalarini ozgartira OLMAYDI (trener boshqaradi)', () =>
  assertFails(updateDoc(doc(as(OWNER), 'trainers', TRAINER3), { accepting: true })));
await check('bosh admin yangi trenerga yozuv qoshadi', () =>
  assertSucceeds(setDoc(doc(as(OWNER), 'trainers', 'yangiTrener'), { name: 'Yangi', bio: '', accepting: true })));
await check('bosh admin yozuvni ochiradi (trenerlikdan olinganda)', () =>
  assertSucceeds(deleteDoc(doc(as(OWNER), 'trainers', 'yangiTrener'))));
await check('shogird katalogga yoza OLMAYDI', () =>
  assertFails(setDoc(doc(as(USER4), 'trainers', USER4), { name: 'Men trener', bio: '', accepting: true })));

console.log('\n== VAZN HAFTADA 1 MARTA (SERVER) ==');
const weighIn = (db, uid, w) => {
  const b = writeBatch(db);
  b.set(doc(collection(db, 'users', uid, 'weights')), { date: new Date(), weight: w });
  b.update(doc(db, 'users', uid), { weight: w, lastWeighIn: serverTimestamp() });
  return b.commit();
};
await check('birinchi olchov (profil + yozuv bitta batchda) otadi', () =>
  assertSucceeds(weighIn(as(W1), W1, 70)));
await check('ertasi kuni ikkinchi olchov OTMAYDI', () =>
  assertFails(weighIn(as(W1), W1, 69)));
await check('olchov yozuvini profilsiz qoshib bolmaydi', () =>
  assertFails(addDoc(collection(as(W1), 'users', W1, 'weights'), { date: new Date(), weight: 60 })));
await check('lastWeighIn ni ozi orqaga surib qoya OLMAYDI', () =>
  assertFails(updateDoc(doc(as(W1), 'users', W1), { lastWeighIn: new Date(2020, 0, 1) })));
await check('7 kun otgan bolsa olchov otadi', () =>
  assertSucceeds(weighIn(as(W2), W2, 88)));
await check('anketada birinchi marta vazn kiritish otadi (vazn 0 edi)', () =>
  assertSucceeds(updateDoc(doc(as(W3), 'users', W3), { weight: 65, age: 20 })));
await check('boshqa maydonlarni ozgartirish vaznga tegmasa otadi', () =>
  assertSucceeds(updateDoc(doc(as(W2), 'users', W2), { name: 'Yangi ism', fcmTokens: ['t1'] })));

console.log('\n== TRENERNI ALMASHTIRISH ==');
await check('shogird boshqa qabul qilayotgan trenerga otadi', () =>
  assertSucceeds(updateDoc(doc(as(USER4), 'users', USER4), { trainerId: TRAINER4 })));
await check('shogird trenersiz qola OLMAYDI', () =>
  assertFails(updateDoc(doc(as(USER4), 'users', USER4), { trainerId: null })));

console.log('\n== BOSH ADMIN BAHOLARI ==');
await check('bosh admin trenerga baho qoyadi', () =>
  assertSucceeds(setDoc(doc(as(OWNER), 'ratings', TRAINER), { stars: 4, comment: 'Yaxshi', updatedAt: serverTimestamp() })));
await check('baho 1..5 oraligida bolishi kerak', () =>
  assertFails(setDoc(doc(as(OWNER), 'ratings', TRAINER), { stars: 7, comment: '' })));
await check('trener oz bahosini koora OLMAYDI', () =>
  assertFails(getDoc(doc(as(TRAINER), 'ratings', TRAINER))));
await check('trener oziga baho qoya OLMAYDI', () =>
  assertFails(setDoc(doc(as(TRAINER), 'ratings', TRAINER), { stars: 5, comment: '' })));

console.log('\n== ZAL ==');
await check('shogird Se/Pay/Sha variantini tanlaydi', () =>
  assertSucceeds(updateDoc(doc(as(USER), 'users', USER), { gymDays: [2, 4, 6] })));
await check('shogird Du/Chor/Ju variantini tanlaydi', () =>
  assertSucceeds(updateDoc(doc(as(USER), 'users', USER), { gymDays: [1, 3, 5] })));
await check('variantdan tashqari kunlar (Du/Pay/Sha) OTMAYDI', () =>
  assertFails(updateDoc(doc(as(USER), 'users', USER), { gymDays: [1, 4, 6] })));
await check('5 kun tanlab bolmaydi', () =>
  assertFails(updateDoc(doc(as(USER), 'users', USER), { gymDays: [1, 2, 3, 4, 5] })));
await check('shogird ozi "uyda mashq" belgilay OLMAYDI', () =>
  assertFails(updateDoc(doc(as(USER), 'users', USER), { homeWorkoutDate: '2026-09-15' })));
await check('trener oz shogirdiga "uyda mashq" belgilaydi', () =>
  assertSucceeds(updateDoc(doc(as(TRAINER), 'users', USER), { homeWorkoutDate: '2026-09-15' })));
await check('boshqa trener "uyda mashq" belgilay OLMAYDI', () =>
  assertFails(updateDoc(doc(as(TRAINER3), 'users', USER), { homeWorkoutDate: '2026-09-16' })));

console.log('\n== ROYXATDAN OTISH ==');
await check('yangi odam ozini user qilib yaratadi', () =>
  assertSucceeds(setDoc(doc(as('newbie'), 'users', 'newbie'), { name: 'Yangi', role: 'user', phone: '998905555555' })));
await check('yangi odam ozini admin qilib yarata OLMAYDI', () =>
  assertFails(setDoc(doc(as('hacker'), 'users', 'hacker'), { name: 'X', role: 'admin', phone: '998906666666' })));
await check('yangi odam ozini owner qilib yarata OLMAYDI', () =>
  assertFails(setDoc(doc(as('hacker2'), 'users', 'hacker2'), { name: 'X', role: 'owner', phone: '998907777777' })));

console.log('\n== DOKON: TOVARLAR ==');
await check('trener tovar qoshadi', () =>
  assertSucceeds(setDoc(doc(as(TRAINER), 'shop', 'prot1'), {
    category: 'Sport pitaniya', name: 'Protein 900 g', note: '', image: '',
    price: 450000, stock: 5, active: true })));
await check('bosh admin tovar qoshadi', () =>
  assertSucceeds(setDoc(doc(as(OWNER), 'shop', 'forma1'), {
    category: 'Forma', name: 'Mayka', note: '', image: '',
    price: 120000, stock: 10, active: true })));
await check('shogird tovarlarni koradi', () =>
  assertSucceeds(getDocs(collection(as(USER), 'shop'))));
await check('shogird tovar qosha OLMAYDI', () =>
  assertFails(setDoc(doc(as(USER), 'shop', 'hack'), {
    category: 'Forma', name: 'Tekin', price: 1, stock: 99, active: true })));
await check('shogird narxni ozgartira OLMAYDI', () =>
  assertFails(updateDoc(doc(as(USER), 'shop', 'prot1'), { price: 1000 })));

console.log('\n== DOKON: BUYURTMALAR ==');
const order = (extra = {}) => ({
  clientId: USER, clientName: 'Shogird', clientPhone: '998903333333', trainerId: TRAINER,
  productId: 'prot1', productName: 'Protein 900 g', category: 'Sport pitaniya',
  price: 450000, qty: 1, status: 'new', createdAt: serverTimestamp(), ...extra,
});
await check('shogird buyurtma beradi', () =>
  assertSucceeds(addDoc(collection(as(USER), 'orders'), order())));
await check('arzon narx yozib bolmaydi', () =>
  assertFails(addDoc(collection(as(USER), 'orders'), order({ price: 1000 }))));
await check('boshqa odam nomidan buyurtma OTMAYDI', () =>
  assertFails(addDoc(collection(as(USER), 'orders'), order({ clientId: USER3 }))));
await check('oz trenerinikidan boshqasiga yozib bolmaydi', () =>
  assertFails(addDoc(collection(as(USER), 'orders'), order({ trainerId: TRAINER3 }))));
await check('darhol "berildi" qilib yarata OLMAYDI', () =>
  assertFails(addDoc(collection(as(USER), 'orders'), order({ status: 'given' }))));
await check('0 dona buyurtma OTMAYDI', () =>
  assertFails(addDoc(collection(as(USER), 'orders'), order({ qty: 0 }))));
await check('sotuvda yoq tovarga buyurtma OTMAYDI', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'shop', 'off1'), {
      category: 'Anjomlar', name: 'Qolqop', price: 90000, stock: 3, active: false });
  });
  await assertFails(addDoc(collection(as(USER), 'orders'), order({
    productId: 'off1', productName: 'Qolqop', category: 'Anjomlar', price: 90000 })));
});

await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  const base = { clientId: USER, clientName: 'Shogird', clientPhone: '998903333333',
    trainerId: TRAINER, productId: 'prot1', productName: 'Protein 900 g',
    category: 'Sport pitaniya', price: 450000, qty: 1, status: 'new', createdAt: new Date() };
  await setDoc(doc(db, 'orders', 'o1'), base);
  await setDoc(doc(db, 'orders', 'o2'), base);
  await setDoc(doc(db, 'orders', 'o3'), { ...base, clientId: USER3, trainerId: TRAINER3 });
});

await check('shogird oz buyurtmasini koradi', () =>
  assertSucceeds(getDoc(doc(as(USER), 'orders', 'o1'))));
await check('shogird boshqaning buyurtmasini kora OLMAYDI', () =>
  assertFails(getDoc(doc(as(USER), 'orders', 'o3'))));
await check('trener oz shogirdi buyurtmasini koradi', () =>
  assertSucceeds(getDoc(doc(as(TRAINER), 'orders', 'o1'))));
await check('trener boshqa shogird buyurtmasini kora OLMAYDI', () =>
  assertFails(getDoc(doc(as(TRAINER), 'orders', 'o3'))));
await check('trener oz buyurtmalarini soraydi (filtr bilan)', () =>
  assertSucceeds(getDocs(query(collection(as(TRAINER), 'orders'),
    where('trainerId', '==', TRAINER)))));
await check('trener HAMMA buyurtmani sorayolmaydi', () =>
  assertFails(getDocs(collection(as(TRAINER), 'orders'))));
await check('bosh admin hamma buyurtmani koradi', () =>
  assertSucceeds(getDocs(collection(as(OWNER), 'orders'))));
await check('trener "berildi" deb belgilaydi', () =>
  assertSucceeds(updateDoc(doc(as(TRAINER), 'orders', 'o1'),
    { status: 'given', updatedAt: serverTimestamp() })));
await check('shogird ozi "berildi" qila OLMAYDI', () =>
  assertFails(updateDoc(doc(as(USER), 'orders', 'o2'), { status: 'given' })));
await check('shogird buyurtmadagi narxni ozgartira OLMAYDI', () =>
  assertFails(updateDoc(doc(as(USER), 'orders', 'o2'), { price: 1000 })));
await check('shogird kutilayotgan buyurtmasini bekor qiladi', () =>
  assertSucceeds(updateDoc(doc(as(USER), 'orders', 'o2'),
    { status: 'canceled', updatedAt: serverTimestamp() })));
await check('berilgan buyurtmani shogird bekor qila OLMAYDI', () =>
  assertFails(updateDoc(doc(as(USER), 'orders', 'o1'), { status: 'canceled' })));
await check('boshqa trener holatni ozgartira OLMAYDI', () =>
  assertFails(updateDoc(doc(as(TRAINER3), 'orders', 'o1'), { status: 'canceled' })));
await check('trener buyurtmani ochira OLMAYDI', () =>
  assertFails(deleteDoc(doc(as(TRAINER), 'orders', 'o1'))));
await check('bosh admin buyurtmani ochiradi', () =>
  assertSucceeds(deleteDoc(doc(as(OWNER), 'orders', 'o1'))));

console.log('\n== ZALLAR ==');
await check('bosh admin zal qoshadi', () =>
  assertSucceeds(setDoc(doc(as(OWNER), 'gyms', 'zal1'),
    { name: 'Diamond Chilonzor', address: 'Bunyodkor 12' })));
await check('zal joyi bilan saqlanadi (mamlakat/viloyat/tuman)', () =>
  assertSucceeds(setDoc(doc(as(OWNER), 'gyms', 'zal1'), {
    name: 'Kotta Qani zali', address: 'Bunyodkor 12',
    country: 'Ozbekiston', region: 'Toshkent shahri', district: 'Chilonzor' })));
await check('notanish maydonli zal OTMAYDI', () =>
  assertFails(setDoc(doc(as(OWNER), 'gyms', 'zal1b'), {
    name: 'X', country: 'Ozbekiston', kenglik: 41.3 })));
await check('bosh admin zal nomini ozgartiradi', () =>
  assertSucceeds(setDoc(doc(as(OWNER), 'gyms', 'zal1'),
    { name: 'Diamond Chilonzor 2', address: '' })));
await check('nomsiz zal OTMAYDI', () =>
  assertFails(setDoc(doc(as(OWNER), 'gyms', 'zal2'), { name: '', address: '' })));
await check('ortiqcha maydonli zal OTMAYDI', () =>
  assertFails(setDoc(doc(as(OWNER), 'gyms', 'zal3'),
    { name: 'X', address: '', egasi: 'men' })));
await check('trener zal qosha OLMAYDI', () =>
  assertFails(setDoc(doc(as(TRAINER), 'gyms', 'zal4'), { name: 'Yangi', address: '' })));
await check('shogird zal qosha OLMAYDI', () =>
  assertFails(setDoc(doc(as(USER), 'gyms', 'zal5'), { name: 'Yangi', address: '' })));
await check('trener zallarni koradi', () =>
  assertSucceeds(getDocs(collection(as(TRAINER), 'gyms'))));
await check('shogird zallarni koradi', () =>
  assertSucceeds(getDocs(collection(as(USER), 'gyms'))));
await check('kirmagan odam zalni kora OLMAYDI', () =>
  assertFails(getDocs(collection(anon(), 'gyms'))));
await check('bosh admin trenerni zalga biriktiradi', () =>
  assertSucceeds(updateDoc(doc(as(OWNER), 'users', TRAINER), { gymId: 'zal1' })));
await check('trener ozini boshqa zalga kochira OLMAYDI', () =>
  assertFails(updateDoc(doc(as(TRAINER), 'users', TRAINER), { gymId: 'zal9' })));
await check('shogird ozining zalini ozgartira OLMAYDI', () =>
  assertFails(updateDoc(doc(as(USER), 'users', USER), { gymId: 'zal1' })));
await check('trener shogirdining zalini ozgartira OLMAYDI', () =>
  assertFails(updateDoc(doc(as(TRAINER), 'users', USER), { gymId: 'zal1' })));
await check('bosh admin zalni ochiradi', () =>
  assertSucceeds(deleteDoc(doc(as(OWNER), 'gyms', 'zal1'))));

console.log('\n== BARMEN ==');
await check('barmen tovar qoshadi', () =>
  assertSucceeds(setDoc(doc(as(BARMEN), 'shop', 'bar1'), {
    category: 'Sport pitaniya', name: 'Kreatin 300 g', note: '', image: '',
    price: 250000, stock: 4, active: true })));
await check('barmen tovar qoldigini ozgartiradi', () =>
  assertSucceeds(updateDoc(doc(as(BARMEN), 'shop', 'bar1'), { stock: 3 })));
await check('barmen hamma buyurtmani koradi', () =>
  assertSucceeds(getDocs(collection(as(BARMEN), 'orders'))));
await check('barmen "berildi" deb belgilaydi va kim bergani yoziladi', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'orders', 'ob1'), {
      clientId: USER, clientName: 'Shogird', clientPhone: '998903333333', trainerId: TRAINER,
      productId: 'bar1', productName: 'Kreatin 300 g', category: 'Sport pitaniya',
      price: 250000, qty: 1, status: 'new', createdAt: new Date() });
  });
  await assertSucceeds(updateDoc(doc(as(BARMEN), 'orders', 'ob1'), {
    status: 'given', updatedAt: serverTimestamp(), givenBy: BARMEN, givenAt: serverTimestamp() }));
});
await check('boshqa nomdan "men berdim" deb yozib bolmaydi', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'orders', 'ob2'), {
      clientId: USER, clientName: 'Shogird', trainerId: TRAINER,
      productId: 'bar1', productName: 'Kreatin', category: 'Sport pitaniya',
      price: 250000, qty: 1, status: 'new', createdAt: new Date() });
  });
  await assertFails(updateDoc(doc(as(BARMEN), 'orders', 'ob2'), {
    status: 'given', givenBy: TRAINER }));
});
await check('barmen buyurtmani ochira OLMAYDI', () =>
  assertFails(deleteDoc(doc(as(BARMEN), 'orders', 'ob1'))));
await check('barmen shogird hujjatini kora OLMAYDI', () =>
  assertFails(getDoc(doc(as(BARMEN), 'users', USER))));
await check('barmen shogird chatini kora OLMAYDI', () =>
  assertFails(getDocs(collection(as(BARMEN), 'chats', USER, 'messages'))));
await check('barmen rol ozgartira OLMAYDI', () =>
  assertFails(updateDoc(doc(as(BARMEN), 'users', USER), { role: 'admin' })));
await check('barmen reja yoza OLMAYDI', () =>
  assertFails(setDoc(doc(as(BARMEN), 'plans', 'pb1'), { title: 'X', meals: [] })));
await check('barmen zal qosha OLMAYDI', () =>
  assertFails(setDoc(doc(as(BARMEN), 'gyms', 'zalb'), { name: 'Yangi' })));

console.log('\n=== NATIJA: ' + pass + ' otdi, ' + fail + ' xato ===');
await env.cleanup();
process.exit(fail === 0 ? 0 : 1);
