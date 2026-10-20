-- Firestore'ning aynan nusxasi: 17 to'plam -> 17 jadval.
-- Nomlar: Firestore maydoni camelCase -> snake_case; ID'lar text (Firebase hujjat id va uid saqlanadi).
-- Tashqi kalitlar (foreign key) YO'Q — Firestore'da ham yo'q: o'chirilgan akkauntga ishora
-- qiluvchi eski yozuvlar ko'chirishda (02) yo'qolmasligi uchun. Qiymat tekshiruvlari jadvalda emas,
-- policies.sql da (Firestore qoidalari faqat YANGI yozuvni tekshiradi — eski ma'lumot to'xtamaydi).
-- Qayta yuklash xavfsiz: `if not exists`.

-- users/{uid}
create table if not exists users (
  id text primary key,
  name text,
  email text,
  phone text,
  role text not null default 'user' check (role in ('user', 'admin', 'owner', 'barmen')),
  gender text,
  age int,
  height double precision,
  weight double precision,
  activity double precision,
  metabolism text,
  goal text,
  plan_id text,
  plan_assigned_at timestamptz,
  trainer_id text,
  gym_id text,
  gym_days int[],
  home_workout_date text,
  subscription_expires_at timestamptz,
  last_weigh_in timestamptz,
  program jsonb,
  fcm_tokens text[]
);
create index if not exists users_trainer_id on users (trainer_id);
create index if not exists users_gym_id on users (gym_id);

-- users/{uid}/days/{sana} — ovqat belgilari, "+ Yedim", zal mashg'uloti, suv
create table if not exists user_days (
  user_id text not null,
  day text not null,
  done int[],
  extras jsonb,
  gym_started boolean,
  gym_done text[],
  water int,
  primary key (user_id, day)
);

-- users/{uid}/weights
create table if not exists weights (
  user_id text not null,
  id text not null default gen_random_uuid()::text,
  date timestamptz,
  weight double precision,
  primary key (user_id, id)
);

-- users/{uid}/photos — "oldin / keyin" rasmi hujjat ichida (350 KB gacha)
create table if not exists photos (
  user_id text not null,
  id text not null default gen_random_uuid()::text,
  data bytea,
  taken_at timestamptz,
  weight double precision,
  primary key (user_id, id)
);

-- users/{uid}/subscriptions
create table if not exists subscriptions (
  user_id text not null,
  id text not null default gen_random_uuid()::text,
  start_date timestamptz,
  months int,
  days int not null default 0,
  price bigint,
  currency text not null default 'UZS',
  paid_date timestamptz,
  created_at timestamptz,
  primary key (user_id, id)
);

-- users/{uid}/attendance/{sana}
create table if not exists attendance (
  user_id text not null,
  day text not null,
  present boolean,
  marked_by text,
  marked_at timestamptz,
  primary key (user_id, day)
);

-- memberships/{uid} — mijozning oxirgi to'lovi ko'zgusi
create table if not exists memberships (
  user_id text primary key,
  name text,
  gym_id text not null default '',
  months int,
  days int,
  price bigint,
  currency text,
  paid_date timestamptz,
  expires_at timestamptz,
  updated_at timestamptz
);
create index if not exists memberships_gym_id on memberships (gym_id);

-- trainers/{uid} — trenerlar katalogi
create table if not exists trainers (
  id text primary key,
  name text,
  bio text not null default '',
  accepting boolean not null default true,
  gym_id text not null default ''
);

-- ratings/{trenerUid} — bosh admin bahosi
create table if not exists ratings (
  trainer_id text primary key,
  stars int,
  comment text not null default '',
  updated_at timestamptz
);

create table if not exists foods (
  id text primary key default gen_random_uuid()::text,
  name text,
  kcal double precision,
  protein double precision,
  fat double precision,
  carbs double precision,
  image text not null default ''
);

-- plans — ratsion; menyular ichki tuzilma (jsonb), Firestore'dagidek
create table if not exists plans (
  id text primary key default gen_random_uuid()::text,
  title text,
  note text not null default '',
  meals jsonb,
  week jsonb,
  photos jsonb,
  forbidden text[]
);

create table if not exists exercises (
  id text primary key default gen_random_uuid()::text,
  name text,
  muscle text,
  sets text,
  tip text,
  also text[],
  video text,
  created_at bigint,
  created_by text,
  base text not null default '',
  level text not null default ''
);

create table if not exists gyms (
  id text primary key default gen_random_uuid()::text,
  name text,
  address text not null default '',
  country text not null default '',
  region text not null default '',
  district text not null default ''
);

-- shop — zal do'koni tovari
create table if not exists shop (
  id text primary key default gen_random_uuid()::text,
  category text,
  name text,
  name_ru text not null default '',
  name_en text not null default '',
  note text not null default '',
  note_ru text not null default '',
  note_en text not null default '',
  price bigint,
  cost_price bigint not null default 0,
  currency text not null default 'UZS',
  stock int not null default 0,
  sizes text[],
  size_stock jsonb,
  colors text[],
  image text not null default '',
  images text[],
  active boolean not null default true
);

create table if not exists orders (
  id text primary key default gen_random_uuid()::text,
  client_id text,
  client_name text,
  client_phone text,
  trainer_id text not null default '',
  gym_id text not null default '',
  product_id text,
  product_name text,
  category text,
  size text not null default '',
  color text not null default '',
  price bigint,
  currency text not null default 'UZS',
  qty int,
  status text,
  created_at timestamptz,
  updated_at timestamptz,
  given_by text,
  given_at timestamptz
);
create index if not exists orders_client_id on orders (client_id);
create index if not exists orders_trainer_id on orders (trainer_id);
create index if not exists orders_gym_id on orders (gym_id);

-- reminders — abonement tugashi eslatmalari jurnali
create table if not exists reminders (
  id text primary key default gen_random_uuid()::text,
  client_id text,
  client_name text,
  trainer_id text,
  sent_by text,
  sent_at timestamptz,
  days_left int
);
create index if not exists reminders_trainer_id on reminders (trainer_id);

-- chats/{uid}/messages — `chat_user_id` = Firestore'dagi {uid} (shogird)
create table if not exists chat_messages (
  chat_user_id text not null,
  id text not null default gen_random_uuid()::text,
  sender_id text,
  text text,
  created_at timestamptz not null default now(),
  primary key (chat_user_id, id)
);
create index if not exists chat_messages_time on chat_messages (chat_user_id, created_at desc);

-- ---------- kirish (akkauntlar) ----------
-- Firebase Auth akkauntlarining nusxasi. Ilovaga (app_user) umuman ochilmaydi: sxemaga ruxsat
-- berilmaydi. Parol: `firebase` — hali ko'chmagan (birinchi kirishda Firebase orqali tekshiriladi),
-- `scrypt` — bizning xesh (kochirish/parol.py).
create schema if not exists kirish;

create table if not exists kirish.accounts (
  id text primary key,
  email text unique,
  phone text,
  password_algo text not null default 'firebase' check (password_algo in ('firebase', 'scrypt')),
  password_hash text,
  created_at timestamptz,
  last_sign_in timestamptz,
  disabled boolean not null default false
);
