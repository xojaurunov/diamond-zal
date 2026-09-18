// Zal: haftasiga 3 mashg'ulot. Shogird o'ziga qulay 3 kunni tanlaydi,
// mashg'ulotlar tanlangan kunlarga tartib bo'yicha tushadi.

/// 3 ta mashg'ulot (tartib bilan)
const workoutGroups = [
  "Ko'krak (grud) + qo'lning oldi (biceps)",
  'Qanot (orqa) + oyoq',
  "Yelka + qo'lning orqasi (triceps)",
];

/// Hafta kunlari: DateTime.weekday bo'yicha (1 — dushanba)
const weekdayNames = {
  1: 'Dushanba',
  2: 'Seshanba',
  3: 'Chorshanba',
  4: 'Payshanba',
  5: 'Juma',
  6: 'Shanba',
  7: 'Yakshanba',
};

const weekdayShort = {1: 'Du', 2: 'Se', 3: 'Chor', 4: 'Pay', 5: 'Ju', 6: 'Sha', 7: 'Yak'};

/// Ikki variant (zal qoidasi): Seshanba/Payshanba/Shanba yoki Dushanba/Chorshanba/Juma
const evenDays = [2, 4, 6]; // Se, Pay, Sha
const oddDays = [1, 3, 5]; // Du, Chor, Ju

/// Tanlov to'g'rimi: ikki variantdan biri
bool validGymDays(List<int> days) {
  final s = ([...days]..sort()).join(',');
  return s == evenDays.join(',') || s == oddDays.join(',');
}

/// Shu hafta kuni qaysi mashg'ulot (dam olish kuni bo'lsa null)
String? workoutFor(List<int> days, int weekday) {
  if (!validGymDays(days)) return null;
  final sorted = [...days]..sort();
  final i = sorted.indexOf(weekday);
  return i < 0 ? null : workoutGroups[i];
}

/// Keyingi mashg'ulot kuni (bugundan keyin) — (hafta kuni, mashg'ulot)
(int, String)? nextWorkout(List<int> days, int todayWeekday) {
  if (!validGymDays(days)) return null;
  for (var k = 1; k <= 7; k++) {
    final wd = (todayWeekday - 1 + k) % 7 + 1;
    final w = workoutFor(days, wd);
    if (w != null) return (wd, w);
  }
  return null;
}

/// Shogird chatda bugun zalga kela olmasligini yozganmi ("bugun kelolmayman", "borolmayman"...)
/// Og'zaki yozuvlar ham: "kelolmayman", "kela olmayman", "boromiman", "borolmiman", "kelmayman"
bool saysCantCome(String text) => RegExp(
      r"(kel|bor)(a\s*)?(ol|o)?\s*m[ai]y?man|uyda\s+qil",
      caseSensitive: false,
    ).hasMatch(text.replaceAll(RegExp("[’'ʻ‘`ʼ]"), ''));
