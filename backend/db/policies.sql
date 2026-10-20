-- Rollar va ruxsatlar — firestore.rules ning aynan nusxasi.
--   * kim ko'radi / qo'shadi / o'chiradi  -> RLS siyosatlari (policy)
--   * qaysi maydonni kim o'zgartiradi       -> `before update` triggerlar (eski va yangi qator)
--   * server tekshiradigan qiymatlar         -> trigger va `with check`
-- Kim so'rayapti: app.uid() <- `app.uid` sozlamasi. Python servis har so'rovda
-- `set local app.uid = '<uid>'` qiladi; Supabase'da app.uid() ni auth.uid() ga ulash kifoya.
-- Ilova `app_user` roli bilan ishlaydi (RLS majburiy). RLS'ni chetlab o'tadigan rol (postgres,
-- ko'chirish skripti) uchun triggerlar tekshirmaydi.
-- Qayta yuklash xavfsiz: `create or replace`, `drop ... if exists`.

create schema if not exists app;

do $$ begin
  create role app_user nologin;
exception when duplicate_object then null;
end $$;

-- ---------- kim so'rayapti ----------

create or replace function app.uid() returns text language sql stable as $$
  select nullif(current_setting('app.uid', true), '')
$$;

create or replace function app.signed_in() returns boolean language sql stable as $$
  select app.uid() is not null
$$;

-- RLS'ni chetlab o'tadigan rol (servis, ko'chirish) — triggerlar unga tegmaydi.
-- `security definer` EMAS: current_user so'rovchining o'zi bo'lishi kerak.
create or replace function app.is_bypass() returns boolean language sql stable as $$
  select coalesce((select rolsuper or rolbypassrls from pg_roles where rolname = current_user), false)
$$;

-- ---------- firestore.rules dagi yordamchilar ----------
-- `security definer` — users jadvalini RLS'siz o'qiydi (siyosat o'zini o'zi chaqirib qolmasin)

create or replace function app.my_role() returns text
language sql stable security definer set search_path = public as $$
  select role from users where id = app.uid()
$$;

-- Bosh admin (zal egasi) — rol tayinlaydi, akkaunt o'chiradi, hammani ko'radi
create or replace function app.is_owner() returns boolean language sql stable as $$
  select coalesce(app.my_role() = 'owner', false)
$$;

-- Trener paneliga kiradiganlar: trener va bosh admin
create or replace function app.is_staff() returns boolean language sql stable as $$
  select coalesce(app.my_role() in ('admin', 'owner'), false)
$$;

-- Barmen — faqat do'kon (tovar va buyurtma)
create or replace function app.is_barmen() returns boolean language sql stable as $$
  select coalesce(app.my_role() = 'barmen', false)
$$;

create or replace function app.trainer_of(uid text) returns text
language sql stable security definer set search_path = public as $$
  select trainer_id from users where id = uid
$$;

-- Trener faqat O'ZIGA biriktirilgan shogird bilan ishlaydi (bosh admin — hamma bilan)
create or replace function app.is_trainer_of(uid text) returns boolean language sql stable as $$
  select app.is_staff() and coalesce(app.trainer_of(uid) = app.uid(), false)
$$;

create or replace function app.can_manage(uid text) returns boolean language sql stable as $$
  select app.is_owner() or app.is_trainer_of(uid)
$$;

-- Foydalanuvchining zali ('' — zalsiz yoki akkaunt yo'q)
create or replace function app.gym_of(uid text) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select gym_id from users where id = uid), '')
$$;

-- Mijoz trenerining zali ('' — trenersiz yoki trener zalsiz)
create or replace function app.client_gym(uid text) returns text language sql stable as $$
  select case when coalesce(app.trainer_of(uid), '') = '' then '' else app.gym_of(app.trainer_of(uid)) end
$$;

-- Shogird trenerini o'zi tanlaydi — faqat katalogda shogird qabul qilayotgan trenerga
create or replace function app.trainer_choice_ok(old_t text, new_t text) returns boolean
language sql stable security definer set search_path = public as $$
  select old_t is not distinct from new_t
    or (new_t is not null and exists (select 1 from trainers where id = new_t and accepting))
$$;

-- Vazn haftada 1 marta: faqat birinchi marta (anketa) yoki yangi o'lchov bilan; o'lchovlar orasi > 6 kun
create or replace function app.weight_change_ok(
  old_w double precision, old_at timestamptz, new_w double precision, new_at timestamptz
) returns boolean language sql stable as $$
  select (old_w is not distinct from new_w and old_at is not distinct from new_at)
    or (coalesce(old_w, 0) = 0 and old_at is not distinct from new_at)
    or (new_at = now() and (old_at is null or now() > old_at + interval '6 days'))
$$;

create or replace function app.last_weigh_in(uid text) returns timestamptz
language sql stable security definer set search_path = public as $$
  select last_weigh_in from users where id = uid
$$;

create or replace function app.is_this_trainer(tid text) returns boolean language sql stable as $$
  select tid = app.uid() and coalesce(app.my_role() = 'admin', false)
$$;

-- Ikki qator faqat [keys] ustunlarida farq qiladimi
create or replace function app.only_changed(old_row jsonb, new_row jsonb, keys text[]) returns boolean
language sql immutable as $$
  select (old_row - keys) = (new_row - keys)
$$;

-- ---------- users ----------

alter table users enable row level security;

drop policy if exists users_select on users;
create policy users_select on users for select using (
  id = app.uid() or app.is_owner()
  -- trener: faqat o'z shogirdlari (bosh admin va boshqa trenerlarni ko'rmaydi)
  or (app.is_staff() and trainer_id = app.uid()));

-- Ro'yxatdan o'tayotgan har kim faqat oddiy foydalanuvchi bo'la oladi
drop policy if exists users_insert on users;
create policy users_insert on users for insert with check (id = app.uid() and role = 'user');

drop policy if exists users_update on users;
create policy users_update on users for update
  using (app.is_owner() or (app.is_staff() and trainer_id = app.uid()) or id = app.uid())
  with check (true);  -- maydonlar users_guard triggerida

-- Akkauntni faqat bosh admin o'chiradi
drop policy if exists users_delete on users;
create policy users_delete on users for delete using (app.is_owner());

create or replace function app.users_guard() returns trigger language plpgsql as $$
declare
  me text := app.uid();
begin
  if app.is_bypass() then return new; end if;
  if new.id is distinct from old.id then raise exception 'users: id o''zgarmaydi' using errcode = '42501'; end if;
  -- bosh admin — hamma maydon, rol ham
  if app.is_owner() then return new; end if;
  -- trener — faqat o'z shogirdi: ROL, TRENER va ZAL emas
  if app.is_staff() and old.trainer_id = me
     and new.role is not distinct from old.role
     and new.trainer_id is not distinct from old.trainer_id
     and new.gym_id is not distinct from old.gym_id then
    return new;
  end if;
  -- foydalanuvchi o'zi — rol, reja, dastur, zal, "uyda mashq", abonement muddatiga tegmaydi;
  -- trenerni katalogdan tanlaydi; vazn haftada 1; zal kunlari — aynan 2-4-6 yoki 1-3-5
  if old.id = me
     and new.role is not distinct from old.role
     and new.plan_id is not distinct from old.plan_id
     and new.plan_assigned_at is not distinct from old.plan_assigned_at
     and new.program is not distinct from old.program
     and new.gym_id is not distinct from old.gym_id
     and app.trainer_choice_ok(old.trainer_id, new.trainer_id)
     and app.weight_change_ok(old.weight, old.last_weigh_in, new.weight, new.last_weigh_in)
     and new.home_workout_date is not distinct from old.home_workout_date
     and new.subscription_expires_at is not distinct from old.subscription_expires_at
     and (new.gym_days is not distinct from old.gym_days
          or new.gym_days in ('{2,4,6}'::int[], '{1,3,5}'::int[])) then
    return new;
  end if;
  raise exception 'users: bu maydonni o''zgartirishga ruxsat yo''q' using errcode = '42501';
end $$;

drop trigger if exists users_guard on users;
create trigger users_guard before update on users for each row execute function app.users_guard();

-- ---------- users/{uid}/days ----------

alter table user_days enable row level security;
drop policy if exists user_days_select on user_days;
create policy user_days_select on user_days for select using (user_id = app.uid() or app.can_manage(user_id));
drop policy if exists user_days_insert on user_days;
create policy user_days_insert on user_days for insert with check (user_id = app.uid());
drop policy if exists user_days_update on user_days;
create policy user_days_update on user_days for update using (user_id = app.uid()) with check (user_id = app.uid());
drop policy if exists user_days_delete on user_days;
create policy user_days_delete on user_days for delete using (user_id = app.uid());

-- ---------- users/{uid}/weights ----------
-- O'lchov faqat profildagi last_weigh_in bilan BIRGA (bitta tranzaksiya) yoziladi —
-- shunda haftalik cheklov chetlab o'tilmaydi

alter table weights enable row level security;
drop policy if exists weights_select on weights;
create policy weights_select on weights for select using (user_id = app.uid() or app.can_manage(user_id));
drop policy if exists weights_insert on weights;
create policy weights_insert on weights for insert with check (user_id = app.uid());

-- Profil bilan "birga" — tranzaksiya OXIRIDA tekshiriladi (Firestore `getAfter` kabi): batch ichida
-- yozuv profildan oldin kelsa ham o'tadi, profilsiz yolg'iz yozuv esa commit'da rad etiladi.
create or replace function app.weights_after_guard() returns trigger language plpgsql as $$
begin
  if app.is_bypass() then return null; end if;
  if app.last_weigh_in(new.user_id) is distinct from now() then
    raise exception 'weights: o''lchov faqat profil bilan birga' using errcode = '42501';
  end if;
  return null;
end $$;

drop trigger if exists weights_after_guard on weights;
create constraint trigger weights_after_guard after insert on weights
  deferrable initially deferred for each row execute function app.weights_after_guard();

-- ---------- users/{uid}/photos ----------

alter table photos enable row level security;
drop policy if exists photos_select on photos;
create policy photos_select on photos for select using (user_id = app.uid() or app.can_manage(user_id));
drop policy if exists photos_insert on photos;
create policy photos_insert on photos for insert with check (
  user_id = app.uid()
  and octet_length(data) between 1 and 358400
  and taken_at = now());
drop policy if exists photos_delete on photos;
create policy photos_delete on photos for delete using (user_id = app.uid());

-- ---------- users/{uid}/subscriptions ----------
-- Faqat trener/bosh admin qo'shadi; mijoz, uning treneri va bosh admin o'qiydi
-- (bosh admin — hammasini bitta so'rovda: oylik hisobot)

alter table subscriptions enable row level security;
drop policy if exists subscriptions_select on subscriptions;
create policy subscriptions_select on subscriptions for select
  using (user_id = app.uid() or app.can_manage(user_id));
drop policy if exists subscriptions_insert on subscriptions;
create policy subscriptions_insert on subscriptions for insert with check (
  app.can_manage(user_id)
  and months between 0 and 24
  and days between 0 and 31
  -- oylik yoki kunlik, ikkalasi birga emas
  and (months > 0) <> (days > 0)
  and price >= 0
  and currency in ('UZS', 'USD'));

-- ---------- users/{uid}/attendance ----------

alter table attendance enable row level security;
drop policy if exists attendance_select on attendance;
create policy attendance_select on attendance for select using (user_id = app.uid() or app.can_manage(user_id));
drop policy if exists attendance_insert on attendance;
create policy attendance_insert on attendance for insert
  with check (app.can_manage(user_id) and present is not null and marked_by = app.uid());
drop policy if exists attendance_update on attendance;
create policy attendance_update on attendance for update using (app.can_manage(user_id))
  with check (app.can_manage(user_id) and present is not null and marked_by = app.uid());

-- ---------- memberships ----------
-- Mijozning OXIRGI to'lovi ko'zgusi — zalning hamma treneri va barmeni ko'radi

alter table memberships enable row level security;
drop policy if exists memberships_select on memberships;
create policy memberships_select on memberships for select using (
  user_id = app.uid() or app.is_owner()
  or ((app.is_staff() or app.is_barmen()) and app.gym_of(app.uid()) <> ''
      and gym_id = app.gym_of(app.uid())));

create or replace function app.membership_ok(m memberships) returns boolean language sql stable as $$
  select m.name is not null and char_length(m.name) <= 60
    and m.gym_id = app.client_gym(m.user_id)
    and m.months between 0 and 24
    and m.days between 0 and 31
    and m.price >= 0
    and m.currency in ('UZS', 'USD')
    and m.paid_date is not null and m.expires_at is not null
    and m.updated_at = now()
$$;

drop policy if exists memberships_insert on memberships;
create policy memberships_insert on memberships for insert
  with check (app.can_manage(user_id) and app.membership_ok(memberships));
drop policy if exists memberships_update on memberships;
create policy memberships_update on memberships for update using (app.can_manage(user_id))
  with check (app.can_manage(user_id) and app.membership_ok(memberships));
drop policy if exists memberships_delete on memberships;
create policy memberships_delete on memberships for delete using (app.is_owner());

-- ---------- trainers ----------
-- Hamma kirganlar o'qiydi. Yozuvni trenerning O'ZI boshqaradi; bosh admin qo'shadi/o'chiradi
-- va faqat zal ko'zgusini to'g'rilaydi.

alter table trainers enable row level security;

create or replace function app.trainer_entry_ok(t trainers) returns boolean language sql stable as $$
  select t.name is not null and char_length(t.name) <= 60
    and char_length(t.bio) <= 300
    -- zal — users.gym_id ko'zgusi: soxta qilib bo'lmaydi
    and t.gym_id = app.gym_of(t.id)
$$;

drop policy if exists trainers_select on trainers;
create policy trainers_select on trainers for select using (app.signed_in());
drop policy if exists trainers_insert on trainers;
create policy trainers_insert on trainers for insert
  with check (app.trainer_entry_ok(trainers) and (app.is_owner() or app.is_this_trainer(id)));
drop policy if exists trainers_update on trainers;
create policy trainers_update on trainers for update using (app.is_owner() or app.is_this_trainer(id))
  with check (app.trainer_entry_ok(trainers));
drop policy if exists trainers_delete on trainers;
create policy trainers_delete on trainers for delete using (app.is_owner());

create or replace function app.trainers_guard() returns trigger language plpgsql as $$
begin
  if app.is_bypass() or app.is_this_trainer(old.id) then return new; end if;
  -- bosh admin: faqat zal ko'zgusi
  if app.is_owner() and app.only_changed(to_jsonb(old), to_jsonb(new), array['gym_id']) then
    return new;
  end if;
  raise exception 'trainers: ruxsat yo''q' using errcode = '42501';
end $$;

drop trigger if exists trainers_guard on trainers;
create trigger trainers_guard before update on trainers for each row execute function app.trainers_guard();

-- ---------- ratings ----------
-- Bosh admin trenerlarga qo'ygan baholar — faqat bosh admin ko'radi (trener bilmaydi)

alter table ratings enable row level security;
drop policy if exists ratings_select on ratings;
create policy ratings_select on ratings for select using (app.is_owner());
drop policy if exists ratings_insert on ratings;
create policy ratings_insert on ratings for insert
  with check (app.is_owner() and stars between 1 and 5 and char_length(comment) <= 500);
drop policy if exists ratings_update on ratings;
create policy ratings_update on ratings for update using (app.is_owner())
  with check (app.is_owner() and stars between 1 and 5 and char_length(comment) <= 500);
drop policy if exists ratings_delete on ratings;
create policy ratings_delete on ratings for delete using (app.is_owner());

-- ---------- foods, plans ----------

alter table foods enable row level security;
drop policy if exists foods_select on foods;
create policy foods_select on foods for select using (app.signed_in());
drop policy if exists foods_insert on foods;
create policy foods_insert on foods for insert with check (app.is_staff());
drop policy if exists foods_update on foods;
create policy foods_update on foods for update using (app.is_staff()) with check (app.is_staff());
drop policy if exists foods_delete on foods;
create policy foods_delete on foods for delete using (app.is_staff());

alter table plans enable row level security;
drop policy if exists plans_select on plans;
create policy plans_select on plans for select using (app.signed_in());
drop policy if exists plans_insert on plans;
create policy plans_insert on plans for insert with check (app.is_staff());
drop policy if exists plans_update on plans;
create policy plans_update on plans for update using (app.is_staff()) with check (app.is_staff());
drop policy if exists plans_delete on plans;
create policy plans_delete on plans for delete using (app.is_staff());

-- ---------- exercises ----------
-- Hamma kirganlar o'qiydi; qo'shish, tahrirlash, o'chirish — trener va bosh admin

alter table exercises enable row level security;

create or replace function app.exercise_ok(e exercises) returns boolean language sql immutable as $$
  select char_length(e.name) between 1 and 80
    and e.muscle in ('chest', 'shoulders', 'biceps', 'triceps', 'forearms', 'abs',
                     'back', 'traps', 'glutes', 'quads', 'hamstrings', 'calves')
    and char_length(e.sets) <= 40
    and char_length(e.tip) <= 500
    and coalesce(cardinality(e.also) <= 6, false)
    and char_length(e.video) <= 300
    and e.created_at is not null
    and e.created_by is not null
    -- namunaviy mashqning o'zgartirilgan nusxasi bo'lsa — o'sha mashq nomi
    and char_length(e.base) <= 80
    -- daraja (faqat trener ko'radi): bo'sh yoki shu uchtadan biri
    and e.level in ('', 'beginner', 'middle', 'pro')
$$;

drop policy if exists exercises_select on exercises;
create policy exercises_select on exercises for select using (app.signed_in());
-- kim qo'shgani soxtalashtirilmaydi
drop policy if exists exercises_insert on exercises;
create policy exercises_insert on exercises for insert
  with check (app.is_staff() and app.exercise_ok(exercises) and created_by = app.uid());
drop policy if exists exercises_update on exercises;
create policy exercises_update on exercises for update using (app.is_staff())
  with check (app.is_staff() and app.exercise_ok(exercises));
drop policy if exists exercises_delete on exercises;
create policy exercises_delete on exercises for delete using (app.is_staff());

-- tahrirda birinchi muallif, vaqt va `base` saqlanadi
create or replace function app.exercises_guard() returns trigger language plpgsql as $$
begin
  if app.is_bypass() then return new; end if;
  if new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at
     or new.base is distinct from old.base then
    raise exception 'exercises: muallif, vaqt va base o''zgarmaydi' using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists exercises_guard on exercises;
create trigger exercises_guard before update on exercises for each row execute function app.exercises_guard();

-- ---------- gyms ----------

alter table gyms enable row level security;

create or replace function app.gym_ok(g gyms) returns boolean language sql immutable as $$
  select char_length(g.name) between 1 and 60
    and char_length(g.address) <= 200
    and char_length(g.country) <= 60
    and char_length(g.region) <= 60
    and char_length(g.district) <= 60
$$;

drop policy if exists gyms_select on gyms;
create policy gyms_select on gyms for select using (app.signed_in());
drop policy if exists gyms_insert on gyms;
create policy gyms_insert on gyms for insert with check (app.is_owner() and app.gym_ok(gyms));
drop policy if exists gyms_update on gyms;
create policy gyms_update on gyms for update using (app.is_owner()) with check (app.is_owner() and app.gym_ok(gyms));
drop policy if exists gyms_delete on gyms;
create policy gyms_delete on gyms for delete using (app.is_owner());

-- ---------- shop ----------
-- Tovarlarni trener, bosh admin va barmen kiritadi; hamma kirganlar ko'radi

alter table shop enable row level security;
drop policy if exists shop_select on shop;
create policy shop_select on shop for select using (app.signed_in());
drop policy if exists shop_insert on shop;
create policy shop_insert on shop for insert with check (app.is_staff() or app.is_barmen());
drop policy if exists shop_update on shop;
create policy shop_update on shop for update using (app.is_staff() or app.is_barmen())
  with check (app.is_staff() or app.is_barmen());
drop policy if exists shop_delete on shop;
create policy shop_delete on shop for delete using (app.is_staff() or app.is_barmen());

-- ---------- orders ----------
-- Shogird o'zi beradi; narx, valyuta, trener va zal yozuvdan emas — bazadan tekshiriladi.
-- Keyin faqat holati o'zgaradi (va kim bergani).

alter table orders enable row level security;

create or replace function app.manages_order(o orders) returns boolean language sql stable as $$
  select app.is_owner()
    or (app.is_staff() and o.trainer_id = app.uid())
    -- barmen — faqat o'z zalining buyurtmasi (zalsiz barmen hech narsani ko'rmaydi)
    or (app.is_barmen() and app.gym_of(app.uid()) <> '' and o.gym_id = app.gym_of(app.uid()))
$$;

drop policy if exists orders_select on orders;
create policy orders_select on orders for select
  using (app.signed_in() and (client_id = app.uid() or app.manages_order(orders)));
drop policy if exists orders_insert on orders;
create policy orders_insert on orders for insert with check (app.signed_in());  -- orders_new_guard
drop policy if exists orders_update on orders;
create policy orders_update on orders for update
  using (client_id = app.uid() or app.manages_order(orders)) with check (true);  -- orders_update_guard
drop policy if exists orders_delete on orders;
create policy orders_delete on orders for delete using (app.is_owner());

create or replace function app.orders_new_guard() returns trigger language plpgsql as $$
declare
  me text := app.uid();
  p shop;
begin
  if app.is_bypass() then return new; end if;
  select * into p from shop where id = new.product_id;
  if not found
     or char_length(new.size) > 20 or char_length(new.color) > 30
     -- valyuta tovardagi bilan bir xil
     or new.currency <> p.currency
     or new.client_id is distinct from me
     or new.status is distinct from 'new'
     or not coalesce(new.qty between 1 and 20, false)
     or new.trainer_id <> coalesce(app.trainer_of(me), '')
     -- zal — shogird trenerining zali (bo'sh trener — bo'sh zal)
     or new.gym_id <> (case when new.trainer_id = '' then '' else app.gym_of(new.trainer_id) end)
     or new.price is distinct from p.price
     or not p.active
     -- yaratishda faqat Firestore'dagi ruxsat etilgan maydonlar
     or new.updated_at is not null or new.given_by is not null or new.given_at is not null then
    raise exception 'orders: noto''g''ri buyurtma' using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists orders_new_guard on orders;
create trigger orders_new_guard before insert on orders for each row execute function app.orders_new_guard();

create or replace function app.orders_update_guard() returns trigger language plpgsql as $$
declare
  me text := app.uid();
begin
  if app.is_bypass() then return new; end if;
  if app.only_changed(to_jsonb(old), to_jsonb(new), array['status', 'updated_at', 'given_by', 'given_at'])
     and coalesce(new.given_by, '') in ('', me)
     and ((app.manages_order(old) and new.status in ('given', 'canceled'))
          -- shogird faqat hali berilmagan buyurtmasini bekor qiladi
          or (old.client_id = me and old.status = 'new' and new.status = 'canceled')) then
    return new;
  end if;
  raise exception 'orders: faqat holat o''zgaradi' using errcode = '42501';
end $$;

drop trigger if exists orders_update_guard on orders;
create trigger orders_update_guard before update on orders for each row execute function app.orders_update_guard();

-- ---------- reminders ----------
-- Faqat trener/bosh admin yozadi, faqat o'z shogirdiga (bosh admin — hammaga)

alter table reminders enable row level security;
drop policy if exists reminders_select on reminders;
create policy reminders_select on reminders for select
  using (app.signed_in() and (trainer_id = app.uid() or app.is_owner()));
drop policy if exists reminders_insert on reminders;
create policy reminders_insert on reminders for insert with check (
  app.is_staff()
  and sent_by = app.uid()
  and days_left is not null
  and (app.is_owner() or trainer_id = app.uid())
  and (app.is_owner() or app.trainer_of(client_id) = app.uid()));
drop policy if exists reminders_delete on reminders;
create policy reminders_delete on reminders for delete using (app.is_owner());

-- ---------- chats/{uid}/messages ----------

alter table chat_messages enable row level security;
drop policy if exists chat_messages_select on chat_messages;
create policy chat_messages_select on chat_messages for select
  using (chat_user_id = app.uid() or app.can_manage(chat_user_id));
drop policy if exists chat_messages_insert on chat_messages;
create policy chat_messages_insert on chat_messages for insert
  with check ((chat_user_id = app.uid() or app.can_manage(chat_user_id)) and sender_id = app.uid());

-- ---------- ruxsatlar (grant) ----------

grant usage on schema public, app to app_user;
grant select, insert, update, delete on all tables in schema public to app_user;
grant execute on all functions in schema app to app_user;

-- ---------- jonli yangilanish ----------
-- Jadval o'zgarsa commit'da `qobil` kanaliga jadval NOMI yuboriladi (ma'lumot emas). Servis uni
-- WebSocket orqali ilovaga uzatadi, ilova o'sha to'plamni qayta so'raydi (ruxsatni RLS tekshiradi).

create or replace function app.notify_change() returns trigger language plpgsql as $$
begin
  perform pg_notify('qobil', tg_table_name);
  return null;
end $$;

do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('drop trigger if exists %I on %I', t || '_notify', t);
    execute format('create trigger %I after insert or update or delete on %I '
                   'for each statement execute function app.notify_change()', t || '_notify', t);
  end loop;
end $$;
