import 'package:cloud_firestore/cloud_firestore.dart';

/// Reja kategoriyalari — shogird maqsadlari bilan bir xil nomlar (AppUser.goalLabel, Plan.category)
const planCategories = ['Ozish', 'Massa nabor'];

class AppUser {
  final String id;
  final String name;
  final String email;
  final String phone; // 998901234567 — kirish telefon raqam + parol bilan
  /// 'user' — shogird, 'admin' — trener, 'barmen' — zal bari (faqat do'kon),
  /// 'owner' — bosh admin (zal egasi).
  /// Rolni faqat bosh admin o'zgartira oladi (firestore.rules).
  final String role;
  final String gender; // 'male' | 'female'
  final int age;
  final double height;
  final double weight;
  final double activity; // 1.2 .. 1.725 — eski; kaloriya endi trener formulasi bilan hisoblanadi

  /// Moddalar almashinuvi (metabolizm): 'slow' — sekin, 'fast' — tez, '' — hali tanlanmagan.
  /// Trener formulasi: kunlik kkal = vazn × (ayol: 31 / 33, erkak: 33 / 35).
  final String metabolism;

  /// Shogird anketada tanlaydi: 'lose' — ozish, 'gain' — massa nabor, '' — hali tanlanmagan
  final String goal;
  final String? planId;

  /// Reja qachon biriktirilgan (trener beradi; eski hujjatlarda yo'q — null).
  /// toMap() ga kirmaydi: shogird profilini saqlaganda ustidan yozilmasin.
  final DateTime? planAssignedAt;

  /// Shogird qaysi trenerga biriktirilgan (null — hali biriktirilmagan)
  final String? trainerId;

  /// Trener qaysi zalga tegishli (`gyms/{id}`). Faqat bosh admin yozadi —
  /// shuning uchun toMap() ga kirmaydi (shogird o'z profilini saqlaganda tegmasin).
  final String? gymId;

  /// Zal kunlari (DateTime.weekday, aynan 3 ta) — shogird o'zi tanlaydi. toMap() ga kirmaydi.
  final List<int> gymDays;

  /// Trener "bugun uyda mashq" belgilagan sana (yyyy-MM-dd) — faqat trener yozadi. toMap() ga kirmaydi.
  final String? homeWorkoutDate;

  /// Abonement qachon tugaydi — `Db.addSubscription` yozadi (subscription qo'shilganda).
  /// Faqat trener/bosh admin yozadi. toMap() ga kirmaydi.
  final DateTime? subscriptionExpiresAt;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.phone = '',
    this.role = 'user',
    this.gender = 'male',
    this.age = 0,
    this.height = 0,
    this.weight = 0,
    this.activity = 1.375,
    this.metabolism = '',
    this.goal = '',
    this.planId,
    this.planAssignedAt,
    this.trainerId,
    this.gymId,
    this.gymDays = const [],
    this.homeWorkoutDate,
    this.subscriptionExpiresAt,
  });

  /// Bosh admin — zal egasi: trener tayinlaydi, hammani ko'radi, o'chira oladi
  bool get isOwner => role == 'owner';

  /// Trener paneliga kirish huquqi (bosh admin ham trener paneliga kiradi)
  bool get isAdmin => role == 'admin' || role == 'owner';

  /// Faqat trener (bosh admin emas)
  bool get isTrainer => role == 'admin';

  /// Barmen — zal bari/sotuvchisi: faqat do'kon bilan ishlaydi.
  /// Shogirdlar, rejalar va chatga kirmaydi.
  bool get isBarmen => role == 'barmen';

  /// Xodimmi (shogird emas) — Xodimlar ro'yxatida chiqadi
  bool get isStaff => isAdmin || isBarmen;

  bool get profileDone => age > 0 && height > 0 && weight > 0;

  bool get isGain => goal == 'gain';

  /// Maqsad nomi — reja shablonlari kategoriyasi bilan bir xil (Plan.category)
  String get goalLabel => switch (goal) {
        'lose' => 'Ozish',
        'gain' => 'Massa nabor',
        _ => '',
      };

  /// Reja shu shogirdga mosmi. Kategoriyali reja faqat bir xil maqsaddagi shogirdga mos;
  /// maqsad tanlanmagan bo'lsa — hech bir kategoriyali reja mos emas.
  /// Kategoriyasiz (qo'lda tuzilgan eski) reja — mos deb olinadi.
  bool fitsPlan(Plan p) =>
      !planCategories.contains(p.category) || (goalLabel.isNotEmpty && p.category == goalLabel);

  /// BMI 18,5 dan past (vazn kam) — ozish tavsiya etilmaydi
  static const minBmiToLose = 18.5;

  /// Ozish maqsadi mumkinmi: vazn kam bo'lsa — yo'q (BMI noma'lum bo'lsa — mumkin)
  bool get canLose => bmi == 0 || bmi >= minBmiToLose;

  /// Trener formulasi koeffitsiyenti: 1 kg vaznga kkal
  int get kcalPerKg => switch ((gender, metabolism)) {
        ('female', 'fast') => 33,
        ('female', _) => 31,
        (_, 'fast') => 35,
        _ => 33,
      };

  /// Norma qanday hisoblangani — foydalanuvchiga ko'rsatish uchun: "80 kg × 33 − 20%"
  String get kcalFormula {
    final w = weight == weight.roundToDouble() ? '${weight.round()}' : '$weight';
    final base = '$w kg × $kcalPerKg';
    if (isGain) return '$base + 10%';
    final deficit = bmi >= 23 ? ' − 20%' : '';
    final raw = bmi >= 23 ? weight * kcalPerKg * 0.8 : weight * kcalPerKg;
    final min = gender == 'male' ? 1500 : 1200;
    return raw < min ? '$base$deficit (minimum $min)' : '$base$deficit';
  }

  double get bmi => height > 0 ? weight / ((height / 100) * (height / 100)) : 0;

  /// Kunlik norma — trener formulasi: vazn × [kcalPerKg] (metabolizm tanlanmagan bo'lsa — sekin).
  /// Ozish: −20% defitsit (BMI < 23 bo'lsa defitsit yo'q), xavfsiz minimum bilan.
  /// Massa nabor: +10%.
  int get targetKcal {
    if (!profileDone) return 0;
    final base = weight * kcalPerKg;
    if (isGain) return (base * 1.1).round();
    final target = bmi < 23 ? base : base * 0.8;
    final minKcal = gender == 'male' ? 1500 : 1200;
    return target < minKcal ? minKcal : target.round();
  }

  AppUser copyWith({
    String? name,
    String? gender,
    int? age,
    double? height,
    double? weight,
    double? activity,
    String? metabolism,
    String? goal,
    String? planId,
    String? trainerId,
  }) =>
      AppUser(
        id: id,
        name: name ?? this.name,
        email: email,
        phone: phone,
        role: role,
        gender: gender ?? this.gender,
        age: age ?? this.age,
        height: height ?? this.height,
        weight: weight ?? this.weight,
        activity: activity ?? this.activity,
        metabolism: metabolism ?? this.metabolism,
        goal: goal ?? this.goal,
        planId: planId ?? this.planId,
        planAssignedAt: planAssignedAt,
        trainerId: trainerId ?? this.trainerId,
        gymId: gymId,
        gymDays: gymDays,
        homeWorkoutDate: homeWorkoutDate,
        subscriptionExpiresAt: subscriptionExpiresAt,
      );

  factory AppUser.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return AppUser(
      id: doc.id,
      name: d['name'] ?? '',
      email: d['email'] ?? '',
      phone: d['phone'] ?? '',
      role: d['role'] ?? 'user',
      gender: d['gender'] ?? 'male',
      age: (d['age'] ?? 0) as int,
      height: (d['height'] ?? 0).toDouble(),
      weight: (d['weight'] ?? 0).toDouble(),
      activity: (d['activity'] ?? 1.375).toDouble(),
      metabolism: d['metabolism'] ?? '',
      goal: d['goal'] ?? '',
      planId: d['planId'],
      planAssignedAt: (d['planAssignedAt'] as Timestamp?)?.toDate(),
      trainerId: d['trainerId'],
      gymId: d['gymId'],
      gymDays: ((d['gymDays'] ?? []) as List).map((e) => (e as num).toInt()).toList(),
      homeWorkoutDate: d['homeWorkoutDate'] as String?,
      subscriptionExpiresAt: (d['subscriptionExpiresAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'email': email,
        'phone': phone,
        'role': role,
        'gender': gender,
        'age': age,
        'height': height,
        'weight': weight,
        'activity': activity,
        'metabolism': metabolism,
        'goal': goal,
        'planId': planId,
        'trainerId': trainerId,
      };
}

/// `gyms/{id}` — zal (filial). Faqat bosh admin qo'shadi va o'chiradi.
/// Har trener bitta zalga tegishli (`AppUser.gymId`); shogird esa o'z treneri orqali
/// shu zalga kiradi — shuning uchun shogirdda alohida maydon yo'q.
class Gym {
  final String id;
  final String name;

  /// Joylashuvi: mamlakat → viloyat → tuman (bosh admin tanlaydi)
  final String country;
  final String region;
  final String district;

  /// Ko'cha va uy raqami (ixtiyoriy)
  final String address;

  const Gym({
    this.id = '',
    required this.name,
    this.country = '',
    this.region = '',
    this.district = '',
    this.address = '',
  });

  /// Ro'yxatda ko'rsatish uchun: "Chilonzor, Toshkent shahri"
  String get place => [district, region].where((e) => e.isNotEmpty).join(', ');

  /// To'liq manzil: "Chilonzor, Toshkent shahri · Bunyodkor 12"
  String get fullAddress =>
      [place, address].where((e) => e.isNotEmpty).join(' · ');

  factory Gym.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return Gym(
      id: doc.id,
      name: (d['name'] ?? '') as String,
      country: (d['country'] ?? '') as String,
      region: (d['region'] ?? '') as String,
      district: (d['district'] ?? '') as String,
      address: (d['address'] ?? '') as String,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'country': country,
        'region': region,
        'district': district,
        'address': address,
      };
}

/// Trenerlar katalogi (`trainers/{uid}`) — shogird anketada trenerini shundan tanlaydi.
/// Shogird trenerning telefoni va boshqa ma'lumotlarini ko'rmaydi — faqat shu yozuvni.
/// Yozuvni TRENER o'zi boshqaradi (ism, qisqa ma'lumot, shogird qabul qilish);
/// bosh admin faqat trener tayinlanganda qo'shadi va trenerlikdan olinganda o'chiradi.
class TrainerInfo {
  final String id;
  final String name;
  final String bio;

  /// false — trener hozir yangi shogird qabul qilmaydi, anketada ko'rinmaydi
  final bool accepting;

  /// Trener zali — `users/{id}.gymId` ning ko'zgusi. Shogird trener hujjatini o'qiy olmaydi,
  /// katalogni esa o'qiydi: buyurtmaga zal shu yerdan yoziladi (barmen faqat o'z zalini ko'radi).
  /// Qoidalar uni `users` dagi qiymatga teng bo'lishga majbur qiladi.
  final String gymId;
  const TrainerInfo(this.id, this.name, {this.bio = '', this.accepting = true, this.gymId = ''});

  factory TrainerInfo.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return TrainerInfo(
      doc.id,
      (d['name'] ?? '') as String,
      bio: (d['bio'] ?? '') as String,
      accepting: (d['accepting'] ?? true) as bool,
      gymId: (d['gymId'] ?? '') as String,
    );
  }

  Map<String, dynamic> toMap() =>
      {'name': name, 'bio': bio, 'accepting': accepting, 'gymId': gymId};
}

/// Bosh admin trenerga qo'ygan baho (`ratings/{trainerId}`) — faqat bosh admin ko'radi va yozadi
class TrainerRating {
  final int stars; // 1..5
  final String comment;
  final DateTime? updatedAt;
  const TrainerRating({required this.stars, this.comment = '', this.updatedAt});

  factory TrainerRating.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return TrainerRating(
      stars: ((d['stars'] ?? 0) as num).toInt(),
      comment: (d['comment'] ?? '') as String,
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class Food {
  final String id;
  final String name;
  final double kcal, protein, fat, carbs; // 100 g uchun
  final String image; // ixtiyoriy rasm URL; bo'sh bo'lsa nomiga qarab ichki rasm tanlanadi

  Food({
    this.id = '',
    required this.name,
    required this.kcal,
    required this.protein,
    required this.fat,
    required this.carbs,
    this.image = '',
  });

  factory Food.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Food(
      id: doc.id,
      name: d['name'] ?? '',
      kcal: (d['kcal'] ?? 0).toDouble(),
      protein: (d['protein'] ?? 0).toDouble(),
      fat: (d['fat'] ?? 0).toDouble(),
      carbs: (d['carbs'] ?? 0).toDouble(),
      image: d['image'] ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'kcal': kcal,
        'protein': protein,
        'fat': fat,
        'carbs': carbs,
        'image': image,
      };
}

class MealItem {
  final String name;
  final double grams;
  final double kcal;
  final double protein;
  final String image; // mahsulotdan ko'chiriladi (ixtiyoriy URL)

  MealItem({
    required this.name,
    required this.grams,
    required this.kcal,
    this.protein = 0,
    this.image = '',
  });

  factory MealItem.fromFood(Food f, double grams) => MealItem(
        name: f.name,
        grams: grams,
        kcal: f.kcal * grams / 100,
        protein: f.protein * grams / 100,
        image: f.image,
      );

  factory MealItem.fromMap(Map<String, dynamic> m) => MealItem(
        name: m['name'] ?? '',
        grams: (m['grams'] ?? 0).toDouble(),
        kcal: (m['kcal'] ?? 0).toDouble(),
        protein: (m['protein'] ?? 0).toDouble(),
        image: m['image'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'grams': grams,
        'kcal': kcal,
        'protein': protein,
        if (image.isNotEmpty) 'image': image,
      };
}

class Meal {
  final String time; // "07:00"
  final String title; // "Nonushta"
  final List<MealItem> items;

  Meal({required this.time, required this.title, required this.items});

  double get kcal => items.fold(0, (s, i) => s + i.kcal);
  double get protein => items.fold(0, (s, i) => s + i.protein);

  factory Meal.fromMap(Map<String, dynamic> m) => Meal(
        time: m['time'] ?? '',
        title: m['title'] ?? '',
        items: ((m['items'] ?? []) as List)
            .map((e) => MealItem.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> toMap() =>
      {'time': time, 'title': title, 'items': items.map((e) => e.toMap()).toList()};
}

class Plan {
  final String id;
  final String title;
  final String note;

  /// Asosiy menyu — reja haftalik bo'lmasa har kuni shu.
  /// Haftalik rejada bu dushanba menyusining nusxasi bo'ladi (eski ilova versiyalari
  /// `week` ni bilmaydi — ular shuni ko'rsatadi).
  final List<Meal> meals;

  /// Hafta kunlari menyusi: 1 — dushanba ... 7 — yakshanba (DateTime.weekday).
  /// Bo'sh bo'lsa — reja har kuni bir xil.
  final Map<int, List<Meal>> week;

  /// Kun rasmi: hafta kuni -> rasm (ilova ichidagi `assets/...` yoki `https://...`).
  /// Trener bergan ratsion rasmi shogirdga o'sha kuni ko'rinadi.
  final Map<int, String> photos;

  final List<String> forbidden;

  Plan({
    this.id = '',
    required this.title,
    this.note = '',
    required this.meals,
    this.week = const {},
    this.photos = const {},
    this.forbidden = const [],
  });

  /// Shu kunning rasmi (yo'q bo'lsa null)
  String? photoFor(int weekday) => photos[weekday];

  /// Har kunga alohida menyu tuzilganmi
  bool get isWeekly => week.isNotEmpty;

  /// Shu hafta kunidagi mahallar (kun uchun alohida menyu bo'lmasa — asosiy menyu)
  List<Meal> mealsFor(int weekday) => week[weekday] ?? meals;

  static double _kcal(List<Meal> m) => m.fold(0, (s, x) => s + x.kcal);
  static double _protein(List<Meal> m) => m.fold(0, (s, x) => s + x.protein);

  double kcalFor(int weekday) => _kcal(mealsFor(weekday));
  double proteinFor(int weekday) => _protein(mealsFor(weekday));

  static const _weekdays = [1, 2, 3, 4, 5, 6, 7];

  double _avg(double Function(int) f) =>
      _weekdays.fold<double>(0, (s, d) => s + f(d)) / _weekdays.length;

  /// Kunlik kaloriya; haftalik rejada — 7 kunning o'rtachasi
  double get kcal => isWeekly ? _avg(kcalFor) : _kcal(meals);

  /// Kunlik oqsil; haftalik rejada — 7 kunning o'rtachasi
  double get protein => isWeekly ? _avg(proteinFor) : _protein(meals);

  /// Kunlik mahallar soni (rioya hisobida ishlatiladi); haftalik rejada — o'rtacha
  int get mealsPerDay =>
      isWeekly ? _avg((d) => mealsFor(d).length.toDouble()).round() : meals.length;

  /// Kategoriya — sarlavhaning " • " gacha qismi: "Ozish • 80-90 kg" -> "Ozish"
  String get category => title.split(' • ').first.trim();

  static List<Meal> _meals(Object? raw) => ((raw ?? []) as List)
      .map((e) => Meal.fromMap(Map<String, dynamic>.from(e)))
      .toList();

  factory Plan.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    // Eski rejalarda bu maydonlar yo'q — bo'sh xarita bilan almashtiriladi
    final rawWeek = (d['week'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final rawPhotos = (d['photos'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return Plan(
      id: doc.id,
      title: d['title'] ?? '',
      note: d['note'] ?? '',
      meals: _meals(d['meals']),
      week: {
        for (final e in rawWeek.entries)
          if (int.tryParse(e.key) case final day? when day >= 1 && day <= 7) day: _meals(e.value),
      },
      photos: {
        for (final e in rawPhotos.entries)
          if (int.tryParse(e.key) case final day? when day >= 1 && day <= 7)
            day: '${e.value ?? ''}',
      },
      forbidden: List<String>.from(d['forbidden'] ?? []),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'note': note,
        'meals': meals.map((e) => e.toMap()).toList(),
        if (isWeekly)
          'week': {
            for (final e in week.entries) '${e.key}': e.value.map((m) => m.toMap()).toList(),
          },
        if (photos.isNotEmpty)
          'photos': {for (final e in photos.entries) '${e.key}': e.value},
        'forbidden': forbidden,
      };
}

/// Vazn haftada faqat 1 marta kiritiladi (kunlik tebranish 1–2 kg natijani buzadi)
const weighInIntervalDays = 7;

class WeightLog {
  final DateTime date;
  final double weight;
  WeightLog(this.date, this.weight);

  /// Oxirgi o'lchovdan beri o'tgan kalendar kunlar (soatga qaramaydi:
  /// dushanba kechqurun kiritilsa, keyingi dushanba ertalab ham kiritsa bo'ladi)
  static int daysSince(DateTime last, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final a = DateTime(last.year, last.month, last.day);
    final b = DateTime(n.year, n.month, n.day);
    return (b.difference(a).inHours / 24).round();
  }

  /// Yangi vazn kiritish mumkinmi (birinchi o'lchov doim mumkin)
  static bool canAdd(WeightLog? last, [DateTime? now]) =>
      last == null || daysSince(last.date, now) >= weighInIntervalDays;

  /// Keyingi o'lchovgacha qolgan kunlar (0 — bugun kiritsa bo'ladi)
  static int daysLeft(WeightLog? last, [DateTime? now]) => last == null
      ? 0
      : (weighInIntervalDays - daysSince(last.date, now)).clamp(0, weighInIntervalDays);

  factory WeightLog.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WeightLog((d['date'] as Timestamp).toDate(), (d['weight'] ?? 0).toDouble());
  }
}

class ChatMessage {
  final String senderId;
  final String text;
  final DateTime createdAt;
  ChatMessage(this.senderId, this.text, this.createdAt);

  factory ChatMessage.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      d['senderId'] ?? '',
      d['text'] ?? '',
      (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
