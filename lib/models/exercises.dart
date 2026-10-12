// Mushak guruhlari va mashqlar — "Tana xaritasi" ekrani uchun (sinov versiyasi).
// Nomlar o'zbekcha (kalit); ekranda `tr()` bilan tarjima qilinadi.
// Ro'yxat standart mashqlardan tuzilgan — trener ko'rib chiqishi kerak.

/// Mushak guruhi: [id] — `BodyMap` dagi shakllar bilan bog'laydi
class Muscle {
  final String id;
  final String name;
  const Muscle(this.id, this.name);
}

const muscles = [
  Muscle('chest', "Ko'krak"),
  Muscle('shoulders', 'Yelka'),
  Muscle('biceps', "Qo'lning oldi (biceps)"),
  Muscle('triceps', "Qo'lning orqasi (triceps)"),
  Muscle('forearms', 'Bilak'),
  Muscle('abs', 'Qorin (press)'),
  Muscle('back', 'Qanot (orqa)'),
  Muscle('traps', 'Trapetsiya'),
  Muscle('glutes', 'Dumba'),
  Muscle('quads', 'Sonning oldi'),
  Muscle('hamstrings', 'Sonning orqasi'),
  Muscle('calves', 'Boldir'),
];

Muscle? muscleById(String id) {
  for (final m in muscles) {
    if (m.id == id) return m;
  }
  return null;
}

class Exercise {
  final String name;

  /// Asosiy ishlaydigan mushak ([Muscle.id])
  final String muscle;

  /// Yordamchi mushaklar
  final List<String> also;

  /// Yondashuv × takror, masalan "4 × 10"
  final String sets;

  /// Qisqa maslahat: qanday bajariladi
  final String tip;
  const Exercise(this.name, this.muscle, this.sets, this.tip, {this.also = const []});
}

const exercises = [
  // ko'krak
  Exercise('Shtanga bilan yotib siqish', 'chest', '4 × 8–10',
      "Kuraklarni siqib yoting, shtangani ko'krak o'rtasiga tushiring.",
      also: ['triceps', 'shoulders']),
  Exercise('Gantel bilan qiya skameykada siqish', 'chest', '3 × 10–12',
      "Skameyka 30° qiya. Ko'krakning tepa qismi ishlaydi.",
      also: ['shoulders', 'triceps']),
  Exercise('Otjimaniya', 'chest', '3 × 15',
      "Tana tekis, tirsaklar 45° burchakda. Ko'krak polga yaqin tushsin.",
      also: ['triceps', 'shoulders', 'abs']),
  // yelka
  Exercise("Gantelni tepaga ko'tarish (o'tirib)", 'shoulders', '4 × 10',
      "Bel tik, gantellarni quloq balandligidan tepaga siqing.",
      also: ['triceps', 'traps']),
  Exercise("Gantelni yonga ko'tarish", 'shoulders', '3 × 12–15',
      "Tirsak biroz bukilgan, yelka balandligigacha. Silkitmang.",
      also: ['traps']),
  Exercise("Egilib gantelni yonga ochish", 'shoulders', '3 × 12–15',
      'Bel tekis, oldinga egiling. Yelkaning orqa qismi ishlaydi.',
      also: ['back', 'traps']),
  // biceps
  Exercise("Shtangani tik turib bukish", 'biceps', '4 × 10',
      "Tirsaklar tanaga yopishgan, tanani tebratmang.",
      also: ['forearms']),
  Exercise('Gantel bilan navbatma-navbat bukish', 'biceps', '3 × 12',
      "Ko'tarayotganda kaftni tashqariga burang.",
      also: ['forearms']),
  Exercise('"Bolg\'a" usulida bukish', 'biceps', '3 × 12',
      "Kaftlar bir-biriga qaragan holda. Bilak ham kuchli ishlaydi.",
      also: ['forearms']),
  // triceps
  Exercise('Brusda siqilish', 'triceps', '3 × 8–12',
      "Tana tik, tirsaklar orqaga qaraydi. Chuqur tushmang.",
      also: ['chest', 'shoulders']),
  Exercise('Blokda pastga siqish', 'triceps', '4 × 12',
      "Tirsaklar tanaga yopishgan, faqat bilak harakatlanadi."),
  Exercise("Gantelni bosh orqasidan ko'tarish", 'triceps', '3 × 12',
      "Tirsaklar tepaga qaraydi va ochilib ketmaydi.",
      also: ['shoulders']),
  // bilak
  Exercise('Shtanga bilan kaftni bukish', 'forearms', '3 × 15',
      "Bilak sonda yotadi, faqat kaft harakatlanadi."),
  Exercise('Turnikda osilib turish', 'forearms', '3 × 30–40 soniya',
      "To'liq osiling, yelkalarni bo'shashtirmang.",
      also: ['back']),
  Exercise("\"Fermer yurishi\"", 'forearms', '3 × 30 metr',
      "Og'ir gantellarni ushlab, tik qomat bilan yuring.",
      also: ['traps', 'abs']),
  // qorin
  Exercise('Yotib tanani bukish', 'abs', '3 × 20',
      "Belni poldan uzmang, iyakni ko'krakka tortmang."),
  Exercise("Osilib oyoqni ko'tarish", 'abs', '3 × 12',
      "Tebranmasdan, tizzalarni ko'krakka torting.",
      also: ['forearms']),
  Exercise('Planka', 'abs', '3 × 40–60 soniya',
      "Tana bir chiziqda, bel pastga cho'kmasin.",
      also: ['shoulders', 'glutes']),
  // qanot
  Exercise('Turnikda tortilish', 'back', '4 × 8–10',
      "Ko'krakni turnikka torting, kuraklarni siqing.",
      also: ['biceps', 'forearms']),
  Exercise("Egilib shtangani tortish", 'back', '4 × 10',
      "Bel tekis, shtangani qoringa torting.",
      also: ['biceps', 'traps']),
  Exercise('Giperekstenziya', 'back', '3 × 15',
      "Belning pastki qismi ishlaydi. Keskin harakat qilmang.",
      also: ['glutes', 'hamstrings']),
  // trapetsiya
  Exercise('Gantel bilan yelka qisish', 'traps', '4 × 12–15',
      "Yelkalarni quloqqa torting, tepada 1 soniya ushlang.",
      also: ['forearms']),
  Exercise("Shtangani iyakka tortish", 'traps', '3 × 12',
      "Tirsaklar kaftdan baland ko'tariladi.",
      also: ['shoulders']),
  Exercise("Blokni yuzga tortish", 'traps', '3 × 15',
      "Arqonni peshonaga torting, tirsaklarni yoying.",
      also: ['shoulders', 'back']),
  // dumba
  Exercise("Shtanga bilan tosni ko'tarish", 'glutes', '4 × 10–12',
      "Kuraklar skameykada, tepada dumbani siqing.",
      also: ['hamstrings']),
  Exercise("Oldinga qadam tashlab o'tirish", 'glutes', '3 × 12',
      "Qadam keng, oldingi tizza oyoq uchidan o'tmasin.",
      also: ['quads', 'hamstrings']),
  Exercise("Oyoqni orqaga ko'tarish (blokda)", 'glutes', '3 × 15',
      "Belni bukmasdan, oyoqni dumba kuchi bilan ko'taring.",
      also: ['hamstrings']),
  // sonning oldi
  Exercise("Shtanga bilan o'tirib-turish", 'quads', '4 × 8–10',
      "Bel tekis, tizzalar oyoq uchi yo'nalishida. Son polga parallel bo'lguncha.",
      also: ['glutes', 'hamstrings', 'abs']),
  Exercise('Oyoq bilan platformani siqish', 'quads', '4 × 12',
      "Tizzani oxirigacha to'g'rilamang, bel suyanchiqdan uzilmasin.",
      also: ['glutes']),
  Exercise("O'tirib oyoqni yozish", 'quads', '3 × 15',
      "Tepada 1 soniya ushlab, sekin tushiring."),
  // sonning orqasi
  Exercise("To'g'ri oyoqda egilish (rumin tortishi)", 'hamstrings', '4 × 10',
      "Bel tekis, tosni orqaga suring. Shtanga oyoq bo'ylab sirpanadi.",
      also: ['glutes', 'back']),
  Exercise('Yotib oyoqni bukish', 'hamstrings', '3 × 12',
      "Tosni skameykadan ko'tarmang."),
  Exercise("\"Xayrli tong\" egilishi", 'hamstrings', '3 × 12',
      "Shtanga yelkada, bel tekis holda oldinga egiling.",
      also: ['back', 'glutes']),
  // boldir
  Exercise("Tik turib oyoq uchiga ko'tarilish", 'calves', '4 × 15–20',
      "Tepada 1 soniya ushlang, pastda to'liq cho'zing."),
  Exercise("O'tirib oyoq uchiga ko'tarilish", 'calves', '3 × 20',
      "Sekin va to'liq amplituda bilan."),
  Exercise('Arqonda sakrash', 'calves', '3 × 1 daqiqa',
      "Oyoq uchida, past sakrang.",
      also: ['shoulders', 'forearms']),
];

List<Exercise> exercisesFor(String muscleId) =>
    exercises.where((e) => e.muscle == muscleId).toList();
