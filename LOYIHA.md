# Qobil Fitness — loyiha qanday ishlaydi

> Bu fayl loyihani **birinchi marta ko'rgan odam** (dasturchi yoki sun'iy intellekt) uchun.
> Shuni o'qib, ilova nima qilishini, qanday qismlardan iboratligini, ma'lumot qayerda
> turishini va qanday yig'ilib joylanishini tushunsa bo'ladi.
>
> Holat: **2026-11-05**. Ishlar tarixi va kunlik holat — [DAVOM.md](DAVOM.md)
> (eng yangisi `docs/davom-noyabr` shoxida). Foydalanuvchi qo'llanmasi — [QOLLANMA.md](QOLLANMA.md).
> [README.md](README.md) va [HOLAT.md](HOLAT.md) — sentabr holati, eskirgan.

---

## 1. Bu nima

**Qobil Fitness** — Toshkentdagi sport zali uchun mobil ilova (oldingi nomlari: "Kotta Qani",
"Diamond", "Qobil"). Zal egasi bitta, u loyihaning buyurtmachisi.

Ilova zalning kundalik ishini bir joyga yig'adi:

- shogirdning **ovqatlanish rejasi** va kunlik kaloriya hisobi;
- **mashg'ulotlar**: tana xaritasi, haftalik reja, mashqlar va video darslar;
- **progress**: vazn grafigi, oldin/keyin rasmlari;
- trener bilan **chat**;
- zal **do'koni**: forma, anjomlar, sport pitaniya;
- **abonement**, davomat (QR), to'lovlar va oylik hisobot;
- zal **e'lonlari** va bildirishnomalar.

Ilova **Android** (APK) va **brauzerda** (iPhone va kompyuter uchun) ishlaydi. Ikkalasi bitta
bazani ko'radi. Til: o'zbek, rus, ingliz.

---

## 2. Rollar

Rol `users/{uid}.role` maydonida turadi. Rolni **faqat bosh admin** o'zgartiradi
(qoida bilan himoyalangan).

| Rol | Kim | Pastki menyu |
|---|---|---|
| `user` | shogird (zal mijozi) | Bugun, Progress, Zal, Do'kon, Eslatma, Trener (chat), Profil |
| `admin` | trener | Mijozlar, Abonement, Zal, Rejalar, Ovqat, Do'kon, Eslatma |
| `barmen` | zal bari / sotuvchi | Do'kon, Hisobim, To'lovlar, Eslatma |
| `owner` | bosh admin (zal egasi) | trenerdagi hamma narsa + **Xodimlar** |

Muhim qoidalar:

- Trener **faqat o'ziga biriktirilgan** shogirdlarni ko'radi (`users/{uid}.trainerId`).
- Shogird trenerini anketada **trenerlar katalogidan** (`trainers/`) o'zi tanlaydi.
- Barmen **faqat o'z zali** do'konini ko'radi; shogird, reja va chatni ko'rmaydi.
- Bosh admin trener tayinlaydi va oladi, akkaunt o'chiradi, zallar qo'shadi,
  trenerlar reytingini, sotuv va oylik hisobotni ko'radi. Yagona bosh adminni tushirib bo'lmaydi.
- Kodda: `AppUser.isOwner`, `isAdmin` (trener **yoki** bosh admin), `isTrainer` (faqat trener).

Kirish — **telefon raqam + parol**, SMS yo'q. Firebase ichida telefon emailga aylanadi:
`99XXXXXXX` → `998XXXXXXXXX@phone.kottaqani.uz`. Foydalanuvchi buni ko'rmaydi.

---

## 3. Arxitektura

```
 Telefon (APK)  ─┐
                 ├──►  Firebase Auth        (kirish: telefon+parol)
 Brauzer (web) ──┤     Cloud Firestore      (hamma ma'lumot, xavfsizlik — firestore.rules)
                 │     Firebase Hosting     (yuklab olish sahifasi, APK, web ilova /ilova/)
                 │     Cloud Functions      (push bildirishnoma — Blaze tarif kerak)
                 │
                 └──►  Cloudflare Worker `qobil-video` + R2 bucket
                       (trener videolari, muqovalar, profil rasmlari)

 Kompyuterda, hali internetda emas:
   backend/  — Python FastAPI servis + Postgres nusxasi (Firebase'dan chiqish uchun zaxira yo'l)
```

Asosiy g'oya: **server kodi deyarli yo'q.** Ilova Firestore'ga to'g'ridan-to'g'ri yozadi va
o'qiydi. Kim nimani o'qiy/yoza olishini **[firestore.rules](firestore.rules)** hal qiladi.
Shuning uchun qoidalar — loyihaning eng muhim xavfsizlik qismi.

Firebase loyihasi: `kotta-qani-09111753` (Firestore `eur3`, tarif **Spark** — bepul).
Sayt: **https://kotta-qani-09111753.web.app**, brauzerdagi ilova: `/ilova/`.

---

## 4. Texnologiyalar

| Qism | Nima |
|---|---|
| Ilova | **Flutter 3.47** (Dart 3.13), Material 3, faqat qorong'i tema |
| Holat boshqaruvi | `flutter_riverpod` (providerlar `lib/services/db.dart` da) |
| Baza | `cloud_firestore`, `firebase_auth` |
| Grafik | `fl_chart` |
| Bildirishnoma | `firebase_messaging` (push), `flutter_local_notifications` (lokal eslatma) |
| Rasm | `image_picker`, `cached_network_image` |
| Video | `video_compress` (telefonda 720p ga kichraytirish), `webview_flutter` (YouTube) |
| QR | `qr_flutter` (chizish), `mobile_scanner` (o'qish) |
| Tarjima | o'z yechimi: `lib/l10n/` (`tr('...')`), kutubxonasiz |
| Video/rasm serveri | Cloudflare Worker (JavaScript) + R2 |
| Push funksiyalari | Node.js, `firebase-functions` v1 |
| Zaxira servis | Python FastAPI + PostgreSQL (Docker) |

Yangi kutubxona yoki texnologiya faqat zal egasi bilan kelishib qo'shiladi.

---

## 5. Papkalar

```
lib/
  main.dart               Firebase ulanishi, tema, til; useEmulator = false (haqiqiy baza)
  firebase_options.dart   Firebase sozlamalari
  theme.dart              Dizayn tizimi: ranglar, radiuslar, bo'shliqlar
  models/                 Ma'lumot modellari (Firestore hujjat ↔ Dart obyekt)
    models.dart             AppUser, Food, Meal, Plan, WeightLog, ChatMessage, TrainerInfo ...
    exercises.dart          mashqlar, mushaklar, haftalik mashg'ulot
    shop.dart               tovar, buyurtma, o'lcham/rang qoldig'i
    subscription.dart       abonement, davomat
    finance.dart, stats.dart  oylik hisobot, trener statistikasi
    gym.dart, hudud.dart    zallar (filiallar); mamlakat → viloyat → tuman
    video_link.dart         video/rasm serveri manzili, havola tekshiruvi
    announcement.dart, lesson.dart, photo.dart, feed.dart
  services/
    db.dart                 HAMMA Firestore o'qish/yozish va Riverpod providerlar
    video_upload_*.dart     Worker'ga video va profil rasmini yuklash (io = telefon, web = brauzer)
    push.dart, notifications.dart, reminders.dart   bildirishnomalar
    settings.dart           til, sozlamalar (shared_preferences)
    screen_guard.dart       shogirdda skrinshotni bloklash (FLAG_SECURE)
  screens/
    auth/                   AuthGate (rolga qarab yo'naltiradi), Login
    user/                   shogird ekranlari (Bugun, Progress, Zal, Videolar, Do'kon, Chat, Profil, Anketa)
    admin/                  trener va bosh admin ekranlari (Mijozlar, Rejalar, Mashqlar, Xodimlar, hisobotlar, QR skaner — muzlatilgan)
    barmen/                 barmen paneli
  widgets/                  umumiy komponentlar (ui.dart — BentoTile, StatTile, UserAvatar, showSheet ...)
  l10n/                     tarjimalar: ru.dart, en.dart (kalit — o'zbekcha matn)

test/                     Flutter unit va widget testlar
firestore.rules           Xavfsizlik qoidalari (eng muhim fayl)
tools/rules_test/         Qoidalar testlari (emulyatorda)
functions/                Cloud Functions: chat xabari va yangi reja uchun push
cloudflare/video/         Video va rasm serveri (Worker) + testlari
backend/                  Python servis (manba faqat feat/servis-* shoxlarida)
public/                   Yuklab olish sahifasi; APK `app/kq.bin` nomida
assets/                   mahsulot rasmlari, brend rasmlari, ikonka
tools/                    yordamchi skriptlar (pastda)
hujjatlar/                TZ (Word) va ekran maketlari (SVG)
android/                  Android loyihasi; imzo kaliti diamond-release.jks (git'da emas)
*.bat, *.ps1              bir bosishda ishlaydigan skriptlar (pastda)
```

---

## 6. Ma'lumotlar (Firestore to'plamlari)

| To'plam | Nima saqlanadi | Kim yozadi |
|---|---|---|
| `users/{uid}` | profil: ism, telefon, rol, jins/yosh/bo'y/vazn, maqsad (`goal`: `lose`/`gain`), `trainerId`, `planId`, `gymId`, `photoUrl`, `fcmTokens` | o'zi (ruxsat etilgan maydonlar), trener, bosh admin |
| `users/{uid}/days/{kun}` | kunlik: yegan ovqatlar, suv, "rejadan tashqari yedim", mashg'ulot fikri (`gymFeel`) | shogird |
| `users/{uid}/weights` | vazn yozuvlari (haftada 1 marta) | shogird |
| `users/{uid}/photos` | progress rasmlari (oldin/keyin) | shogird |
| `users/{uid}/subscriptions` | abonementlar | trener, bosh admin, barmen |
| `users/{uid}/attendance/{kun}` | davomat (QR) | trener |
| `memberships/{uid}` | mijozning oxirgi to'lovi nusxasi (ism, muddat, narx) — zal treneri va barmeni `users` ni ochmasdan ko'radi | abonement qo'sha oladigan xodim |
| `trainers/{tid}` | trenerlar katalogi (shogird anketada tanlaydi): ism, bio, qabul, `photoUrl` | trener o'zi; bosh admin faqat `gymId` |
| `ratings/{tid}` | trener reytingi | shogird |
| `foods` | mahsulotlar bazasi (100 g uchun KBJU) | trener |
| `plans` | ovqatlanish rejalari (kategoriya: ozish / massa) | trener |
| `exercises` | mashqlar (mushak, daraja, video) | trener |
| `videos` | video darslar (R2'dagi fayl havolasi, muqova) | trener, bosh admin |
| `announcements` | zal e'lonlari (7 kun ko'rinadi) | trener, bosh admin |
| `gyms` | zallar (filiallar) | bosh admin |
| `shop`, `orders` | do'kon tovarlari va buyurtmalar | trener/barmen; buyurtma — shogird |
| `reminders` | abonement tugashi haqida yuborilgan eslatmalar jurnali | trener, bosh admin |
| `chats/{uid}/messages` | shogird ↔ trener chati | ikkalasi |

Fayllar (video, rasm) Firestore'da **emas** — Cloudflare R2'da. Bazada faqat havola turadi.

**Ma'lumot oqimiga misol** (shogird ovqat yedi):
1. Shogird "Bugun" ekranida "yedim" bosadi.
2. `Db` (`lib/services/db.dart`) `users/{uid}/days/{bugun}` hujjatiga yozadi.
3. `firestore.rules` tekshiradi: yozuvchi shu shogirdmi, maydonlar ruxsat etilganmi.
4. Riverpod provider yangi qiymatni oladi — shogird ekrani va trenerning "Mijozlar" ekrani
   darhol yangilanadi (Firestore jonli oqim).

---

## 7. Xavfsizlik

- **`firestore.rules`** — hamma ruxsat shu yerda. Asosiy funksiyalar: `isOwner()`, `isStaff()`,
  `isBarmen()`, `isTrainerOf(uid)`, `canManage(uid)`, `gymOf(uid)`.
  Har o'zgarishdan keyin `tools/rules_test/test.mjs` testlari o'tishi shart (hozir 283 ta).
- **Joylashdan oldin** bazadagi joriy qoidani o'qib, faylga solishtiring. Boshqa shoxdan joylab,
  u yerda yo'q qoidani o'chirib yubormang.
- **Worker** har so'rovda Firebase ID token'ni tekshiradi. Video yuklash va o'chirish — faqat
  trener va bosh admin. Profil rasmi — har kim faqat o'ziniki.
- Ilova faqat **o'z serverimizdagi** va egasining papkasidagi rasmni ko'rsatadi (`isAvatarUrlOf`).
- Shogirdda skrinshot bloklangan, "Bugun" ekranida suv belgisi bor.
- **Repo ochiq (public).** Parol, token va haqiqiy ma'lumot git'ga yozilmaydi.
  Ular faqat lokal fayllarda: `PAROLLAR.md`, `.env`, `backend/.env`. Zaxiralar (`zaxira/`) va
  `backend/data/` ham git'da emas.

---

## 8. Ishga tushirish va yig'ish

Kerak: Flutter 3.47+, Chrome; joylash uchun Node.js va `firebase-tools`; APK uchun Java 21 va
Android SDK. Bu kompyuterda hammasi foydalanuvchi papkasida o'rnatilgan
(batafsil — DAVOM.md, 5a-bo'lim).

```powershell
# Ilovani brauzerda ochish (haqiqiy bazaga ulanadi)
powershell -ExecutionPolicy Bypass -File .\start.ps1        # http://localhost:5173

# Tekshiruv
flutter analyze
flutter test

# Qoidalar testi (emulyator 8085-portda ishlab turgan bo'lsa)
node tools/rules_test/test.mjs

# Worker testlari
node --test cloudflare/video/test/index.test.mjs

# APK
flutter build apk --release --split-per-abi
```

Tarjima qo'shish: `python tools/l10n/l10n.py add/gen/check` (`PYTHONIOENCODING=utf-8` bilan).
Yangi matn `tr('O\'zbekcha matn')` bilan yoziladi, rus va ingliz tarjimasi `tools/l10n/tarjima.json` da.

---

## 9. Joylash (deploy)

| Nima | Qanday |
|---|---|
| Qoidalar + sayt + saytdagi APK | `deploy.ps1` (yangi APK'ni `public/app/kq.bin` ga o'zi ko'chiradi) |
| Faqat qoidalar | `firebase deploy --only firestore:rules` |
| Video/rasm serveri | `cd cloudflare/video` → `npx wrangler deploy` (`CLOUDFLARE_API_TOKEN` — `backend/.env`) |
| Push funksiyalari | `FUNKSIYALAR_JOYLASH.bat` (Blaze tarif kerak) |

Spark tarifida `.apk` fayl bloklanadi. Shuning uchun APK saytda `.bin` nomida turadi va
`firebase.json` dagi header uni `.apk` qilib yuklab beradi.

**Ish tartibi (zal egasi bilan kelishilgan):**
1. Har ish alohida **shoxda** (`feat/...`, `fix/...`) qilinadi.
2. Sinash uchun shoxlar `sinov/...` shoxiga yig'iladi, APK **Desktop'ga** chiqariladi.
3. Zal egasi APK'ni **telefonda** ko'radi va "yaxshi" deydi.
4. Shundan keyingina shoxlar `main` ga qo'shiladi, sayt va saytdagi APK yangilanadi.
5. Qoidalar va serverni joylash — faqat zal egasining ruxsati bilan.

---

## 10. Yordamchi skriptlar

| Fayl | Nima qiladi |
|---|---|
| `start.ps1` | ilovani Chrome'da ochadi |
| `deploy.ps1` | qoidalar va saytni joylaydi |
| `ZAXIRA.bat` | bazaning to'liq zaxirasi → `zaxira/` (haftada 1 marta) |
| `PAROL_TIKLASH.bat` | parolini unutgan foydalanuvchiga yangi parol |
| `AKKAUNT_OCHIRISH.bat` | shogird akkauntini to'liq o'chirish (ma'lumot + kirish) |
| `NARX_USTAMA.bat` | do'kondagi hamma tovar narxiga ustama foiz qo'shish |
| `emulators.ps1` | lokal Firebase emulyatori (akkauntsiz sinov) |
| `tools/dokon/` | do'kon tovarlarini qo'shish, tarjima, narx skriptlari |
| `tools/l10n/` | tarjimalar |
| `tools/brauzer/cdp.mjs` | sinov brauzerini boshqarish (ekranni ko'z bilan tekshirish) |
| `tools/sinov/` | vaqtinchalik sinov shogirdi yaratish |
| `tools/tana/` | tana xaritasi rasmlarini tayyorlash |

---

## 11. Hozirgi holat (2026-11-10)

**Jonli (hamma ishlatyapti), `main` = sayt:**
- Sayt va saytdagi APK — **10-noyabr** holati: "Qobil Fitness" nomi va logotipi, video yuklash va
  "Videolar" bo'limi, oldin/keyin slayderi, dam olish taymeri, mashg'ulot fikri, zal e'lonlari,
  profil rasmi (hamma rol), abonement tuzatishlari (to'langan sana, muddati o'tgan eslatma,
  xato to'lovni o'chirish).
- Firestore qoidalari — `main` dagi fayl (10-noyabr).
- Video/rasm serveri — joylangan (3-noyabr).

**Muzlatilgan:** QR davomat — kod izohda (`// QR davomat muzlatilgan`), ilovada ko'rinmaydi.

**Kompyuterda, internetga chiqmagan:** Python servis va Postgres nusxasi (`feat/servis-*`).

**Kutilayotgan:** zal egasi yangi APK'ni telefonda tekshiradi. Ochiq ishlar ro'yxati —
DAVOM.md, 0-bo'lim.

---

## 12. Yangi odam uchun qoidalar

- Zal egasi bilan **o'zbekcha** gaplashiladi. U dasturchi emas — natijani telefonda ko'radi.
- Hech narsa so'ramasdan o'chirilmaydi va joylanmaydi.
- Maxfiy ma'lumot git'ga yozilmaydi (repo ochiq).
- Har o'zgarishdan keyin: `flutter test`, qoida o'zgargan bo'lsa — qoida testlari.
- Bajarilgan har ish DAVOM.md ga yangi raqamli band bo'lib yoziladi.
