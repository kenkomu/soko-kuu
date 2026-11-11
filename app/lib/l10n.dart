import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'state/providers.dart';

const supportedLangs = [Locale('en'), Locale('sw')];
const localeDelegates = <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class Lang extends Notifier<String> {
  @override
  String build() => gLang = ref.read(prefsProvider).getString('lang') ?? 'en';
  void set(String v) {
    state = gLang = v;
    ref.read(prefsProvider).setString('lang', v);
  }
}

final langProvider = NotifierProvider<Lang, String>(Lang.new);

/// One plain sentence per API error code, English and Swahili.
/// Swahili copy should be checked by a Kenyan speaker before release.
const errorText = <String, Map<String, String>>{
  'BAD_SIG': {
    'en': 'We could not confirm it was you. Refresh and try again.',
    'sw': 'Hatukuweza kuthibitisha ni wewe. Onyesha upya ujaribu tena.',
  },
  'BAD_NONCE': {
    'en': 'Out of step with the market. Pull down to refresh and try again.',
    'sw': 'Umepitwa na soko. Vuta chini kuonyesha upya, kisha jaribu tena.',
  },
  'EXPIRED': {
    'en': 'That took too long. Please try again.',
    'sw': 'Imechukua muda mrefu. Tafadhali jaribu tena.',
  },
  'NOT_ENOUGH_PTS': {
    'en': 'You do not have enough pts for that. Try a smaller amount.',
    'sw': 'Pointi zako hazitoshi. Jaribu kiasi kidogo.',
  },
  'NOT_ENOUGH_STOCK': {
    'en': 'Not enough stock. Try a smaller amount or another stall.',
    'sw': 'Mzigo hautoshi. Jaribu kiasi kidogo au duka lingine.',
  },
  'CREDIT_DENIED': {
    'en': 'Credit was refused. Repay what you owe first, then ask again.',
    'sw': 'Deni limekataliwa. Lipa ulichodaiwa kwanza, kisha uombe tena.',
  },
  'NOT_MEMBER': {'en': 'Join a chama first.', 'sw': 'Jiunge na chama kwanza.'},
  'ALREADY_VOTED': {
    'en': 'You already voted on this lot.',
    'sw': 'Umeshapiga kura kwa mzigo huu.',
  },
  'WRONG_PHASE': {
    'en': 'The market trades at midday only.',
    'sw': 'Soko hufanya biashara adhuhuri tu.',
  },
  'RATE_LIMITED': {
    'en': 'Slow down a little, then try again.',
    'sw': 'Polepole kidogo, kisha jaribu tena.',
  },
  'PRICE_MOVED': {
    'en': 'The price moved while you were deciding. Check the new price and try again.',
    'sw': 'Bei imebadilika ulipokuwa unaamua. Angalia bei mpya kisha ujaribu tena.',
  },
  'FORBIDDEN': {
    'en': 'That action is not allowed for your account.',
    'sw': 'Hatua hiyo hairuhusiwi kwa akaunti yako.',
  },
  'INTERNAL': {
    'en': 'Something went wrong on our side. Try again in a moment.',
    'sw': 'Kuna hitilafu upande wetu. Jaribu tena baada ya muda.',
  },
  'OFFLINE': {
    'en': 'Cannot reach the market. Check your connection or use demo mode.',
    'sw': 'Soko halipatikani. Angalia mtandao wako au tumia hali ya majaribio.',
  },
};

String errorSentence(String code, String lang) =>
    (errorText[code] ?? errorText['INTERNAL']!)[lang] ??
    errorText['INTERNAL']!['en']!;

typedef _Tpl = String Function(List<String?> m);

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
String _g(String? id) => goodName(id ?? '', 'sw');

/// Swahili for the sentences the econ crate and the demo ledger produce for
/// "Why this price". Each pattern is anchored; numbers and good names are
/// captured and re-used. Unknown sentences stay English.
final _whyPatterns = <(RegExp, _Tpl)>[
  (
    RegExp(
      r'^Price rise limited to (\d+)% today; it may climb further tomorrow\.$',
    ),
    (m) =>
        'Bei imeruhusiwa kupanda ${m[1]}% tu leo; kesho inaweza kupanda tena.',
  ),
  (
    RegExp(
      r'^Price fall limited to (\d+)% today; it may drop further tomorrow\.$',
    ),
    (m) =>
        'Bei imeruhusiwa kushuka ${m[1]}% tu leo; kesho inaweza kushuka tena.',
  ),
  (
    RegExp(
      r'^(\w+) is scarce at this stall, so the price is (\d+)% above normal\.$',
    ),
    (m) =>
        '${_g(m[1])}: ni chache hapa, ndiyo maana bei iko ${m[2]}% juu ya kawaida.',
  ),
  (
    RegExp(
      r'^(\w+) is plentiful at this stall, so the price is (\d+)% below normal\.$',
    ),
    (m) =>
        '${_g(m[1])}: ni nyingi hapa, ndiyo maana bei iko ${m[2]}% chini ya kawaida.',
  ),
  (
    RegExp(
      r'^(\w+) stock is near normal, so the price sits near its usual level\.$',
    ),
    (m) =>
        '${_g(m[1])}: mzigo uko kawaida, kwa hiyo bei iko pale pale.',
  ),
  (
    RegExp(r'^Ukame \(drought\) cuts (\w+) supply\.$'),
    (m) => 'Ukame umebana: ${_g(m[1])} ni ngumu kupata.',
  ),
  (
    RegExp(r'^Fuel costs add about (\d+)% to (\w+)\.$'),
    (m) => 'Mafuta ni ghali: ${_g(m[2])} imeongezeka takriban ${m[1]}%.',
  ),
  (
    RegExp(r'^The cut road delays deliveries\.$'),
    (m) => 'Barabara imekatika, mizigo inachelewa kufika.',
  ),
  (
    RegExp(r'^Festival crowds push demand up\.$'),
    (m) => 'Ni sikukuu: wateja ni wengi, bei inapanda.',
  ),
  (
    RegExp(r'^Harvest season: (\w+) is arriving in bulk\.$'),
    (m) => 'Ni msimu wa mavuno: ${_g(m[1])} inaingia kwa wingi.',
  ),
  (
    RegExp(r'^A glut of (\w+) pushes its price down\.$'),
    (m) => 'Kuna ${_g(m[1])} nyingi sokoni, bei inashuka.',
  ),
  // Offline demo ledger.
  (
    RegExp(
      r'^(Fuel costs|Drought|Glut|Road delays) moved the mid price ([+-]?\d+)%\.$',
    ),
    (m) =>
        '${const {'Fuel costs': 'Gharama za mafuta zimesogeza', 'Drought': 'Ukame umesogeza', 'Glut': 'Wingi wa mazao umesogeza', 'Road delays': 'Ucheleweshaji barabarani umesogeza'}[m[1]]} bei ya kati kwa ${m[2]}%.',
  ),
  (
    RegExp(r'^Only (\d+) units left at (\w+), so the ask is firm\.$'),
    (m) =>
        'Vimebaki ${m[1]} tu kwa ${_cap(m[2]!)}, kwa hiyo bei haitetereki.',
  ),
  (
    RegExp(r'^(\w+) has (\d+) units, enough to hold the ask steady\.$'),
    (m) =>
        '${_cap(m[1]!)} ana ${m[2]}, vya kutosha bei itulie.',
  ),
  (
    RegExp(
      r'^Trader spread is (\d+)% each way: you buy at ask, sell at bid\.$',
    ),
    (m) =>
        'Mfanyabiashara huchukua ${m[1]}% kila upande: unanunua kwa bei ya kuuza, unauza kwa bei ya kununua.',
  ),
  (
    RegExp(r'^(\w+) spoils: (\d+)% of unsold stock is lost each night\.$'),
    (m) =>
        '${_g(m[1])}: huharibika, ${m[2]}% ya mzigo usiouzwa hupotea kila usiku.',
  ),
];

/// Swahili for the Radio Soko texts the econ crate writes (events.rs `text`).
final _newsPatterns = <(RegExp, _Tpl)>[
  (
    RegExp(
      r'^Ukame: the rains have failed\. Farm produce will cost about (\d+)% more and arrive slowly\.$',
    ),
    (m) =>
        'Ukame: mvua zimekosekana. Mazao ya shambani yatagharimu takriban ${m[1]}% zaidi na yatafika polepole.',
  ),
  (
    RegExp(
      r'^Fuel prices are up\. Transport costs lift every price a little, charcoal and fish most\.$',
    ),
    (m) => 'Bei ya mafuta imepanda. Gharama za usafiri zinapandisha kila bei kidogo, makaa na samaki zaidi.',
  ),
  (
    RegExp(
      r'^The main road is cut by floods\. Deliveries are late and stalls run low\.$',
    ),
    (m) => 'Barabara kuu imekatika kwa mafuriko. Mizigo imechelewa na maduka yanaishiwa.',
  ),
  (
    RegExp(
      r'^Festival this week: buyers are everywhere and prices run about (\d+)% higher\.$',
    ),
    (m) =>
        'Sikukuu wiki hii: wanunuzi kila mahali na bei ziko takriban ${m[1]}% juu.',
  ),
  (
    RegExp(
      r'^Harvest is in\. Farm produce is arriving fast and prices ease by about (\d+)%\.$',
    ),
    (m) =>
        'Mavuno yamefika. Mazao ya shambani yanaingia haraka na bei zinashuka takriban ${m[1]}%.',
  ),
  (
    RegExp(
      r'^A glut of (\w+) floods the market\. Sellers are cutting prices\.$',
    ),
    (m) => 'Wingi wa ${_g(m[1])} umejaa sokoni. Wauzaji wanashusha bei.',
  ),
];

String? _matchTpl(List<(RegExp, _Tpl)> pats, String s) {
  for (final (re, f) in pats) {
    final m = re.firstMatch(s);
    if (m != null) {
      return f([for (var i = 0; i <= m.groupCount; i++) m.group(i)]);
    }
  }
  return null;
}

/// Show server why[] text in Swahili when a template matches; otherwise as given.
String whyText(String s, String lang) =>
    lang == 'sw' ? (_matchTpl(_whyPatterns, s) ?? s) : s;

const tutorial = <String, Map<String, String>>{
  'title': {'en': 'Your first day', 'sw': 'Siku yako ya kwanza'},
  's1': {
    'en': 'Tap a price to see why it is what it is. Trading opens at midday.',
    'sw': 'Gusa bei uone kwa nini iko hivyo. Biashara hufunguka adhuhuri.',
  },
  's2': {
    'en': 'At midday, buy a few units of something.',
    'sw': 'Adhuhuri, nunua kiasi kidogo cha bidhaa.',
  },
  's3': {
    'en': 'Now sell it from the Duka tab to finish your first trade.',
    'sw': 'Sasa iuze kutoka kichupo cha Duka kumaliza biashara yako ya kwanza.',
  },
  's4': {
    'en': 'Come back at midday to sell what you bought.',
    'sw': 'Rudi adhuhuri kuuza ulichonunua.',
  },
  'skip': {'en': 'Skip', 'sw': 'Ruka'},
};

/// Radio Soko headlines in Swahili. Known demo bulletins are translated in
/// full; any other bulletin gets a headline for its `kind`; an unknown kind
/// keeps the English text. English always shows the text as sent.
const newsSwExact = <String, String>{
  'Soko is calm today. Prices are near their usual level.':
      'Soko ni tulivu leo. Bei ziko karibu na kiwango cha kawaida.',
  'Ukame in Kiambu: tomato supply is short, prices climb.':
      'Ukame Kiambu: nyanya ni chache, bei zinapanda.',
  'Fuel price up at the pump; every load costs more to bring in.':
      'Bei ya mafuta imepanda; kila mzigo unagharimu zaidi kuletwa.',
  'Maize glut from Trans Nzoia; sellers are cutting prices.':
      'Mahindi mengi kutoka Trans Nzoia; wauzaji wanashusha bei.',
  'Road wash-out near Naivasha delays onion lorries.': 'Barabara imeharibiwa karibu na Naivasha; malori ya vitunguu yamechelewa.',
};
const newsSwKind = <String, String>{
  'ukame': 'Ukame: mazao ni machache, bei zinaweza kupanda.',
  'fuel': 'Bei ya mafuta imebadilika; gharama za usafiri zinaathiri bei.',
  'road': 'Tatizo la barabara linachelewesha mizigo sokoni.',
  'festival': 'Sikukuu inakaribia; mahitaji yanaongezeka sokoni.',
  'harvest': 'Mavuno yameingia sokoni; bei zinaweza kushuka.',
  'glut': 'Mazao ni mengi kupita kiasi; wauzaji wanashusha bei.',
};
String newsText(String kind, String text, [String? lang]) {
  if ((lang ?? gLang) != 'sw') return text;
  return newsSwExact[text] ??
      _matchTpl(_newsPatterns, text) ??
      newsSwKind[kind] ??
      text;
}

/// Language used by tr(); kept in sync by [Lang]. The whole app is rebuilt
/// (keyed on the language) when it changes.
String gLang = 'en';

String tr(String en, [Map<String, Object>? p]) {
  var s = gLang == 'sw' ? (sw[en] ?? en) : en;
  p?.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

const _goods = {
  'tomato': ['Tomato', 'Nyanya'],
  'kale': ['Kale', 'Sukuma wiki'],
  'sukuma': ['Kale', 'Sukuma wiki'],
  'maize': ['Maize', 'Mahindi'],
  'onion': ['Onion', 'Vitunguu'],
  'beans': ['Beans', 'Maharagwe'],
  'fish': ['Fish', 'Samaki'],
  'charcoal': ['Charcoal', 'Makaa'],
};

String goodName(String g, [String? lang]) {
  final e = _goods[g];
  if (e == null) return g.isEmpty ? g : g[0].toUpperCase() + g.substring(1);
  return (lang ?? gLang) == 'sw' ? e[1] : e[0];
}

String phaseName(Object phase) => tr(switch ('$phase'.split('.').last) {
  'dawn' => 'Dawn',
  'midday' => 'Midday',
  _ => 'Dusk',
});

/// Server tier ids: mgeni, mfanyabiashara, mzoefu, mzee_wa_soko. The names are Swahili in both languages.
String tierName(String t) => switch (t.toLowerCase()) {
  'mgeni' => 'Mgeni',
  'mfanyabiashara' => 'Mfanyabiashara',
  'mzoefu' => 'Mzoefu',
  'mzee_wa_soko' => 'Mzee wa Soko',
  _ => t.isEmpty ? t : t[0].toUpperCase() + t.substring(1),
};

/// Swahili for every on-screen string, keyed by the English text.
/// Review this one file with a Kenyan speaker. {x} placeholders must stay.
const sw = <String, String>{
  'Added (allowances)': 'Zilizoongezwa (posho)',
  'Add your email to join a chama': 'Weka barua pepe yako ili ujiunge na chama',
  'Approve': 'Kubali',
  'Ask for credit': 'Omba deni',
  'Basket price index': 'Kielezo cha bei ya kapu',
  'Before you start': 'Kabla ya kuanza',
  'Bei za leo (today\'s prices)': 'Bei za leo',
  'Best bid {p} at {m}': 'Bei bora ya kuuza {p} kwa {m}',
  'Buy': 'Nunua',
  'Buy at {p}': 'Nunua kwa {p}',
  'Buying {q} costs {c}. Selling {s} brings about {r} before cess.': 'Kununua {q} kunagharimu {c}. Kuuza {s} kunaleta takriban {r} kabla ya ushuru wa soko.',
  'Chama': 'Chama',
  'Chama (buy together)': 'Chama (nunua pamoja)',
  'Chama members need a saved account so the group can trust each other. We email a sign-in link.': 'Wanachama wa chama wanahitaji akaunti iliyohifadhiwa ili kikundi kiaminiane. Tutakutumia kiungo cha kuingia kwa barua pepe.',
  'Close day': 'Funga siku',
  'Code from the link': 'Msimbo kutoka kwenye kiungo',
  'Common pot {p}': 'Mfuko wa pamoja {p}',
  'Confirm': 'Thibitisha',
  'Credit limit {l} · owed {o}': 'Kikomo cha deni {l} · unadaiwa {o}',
  'Day {d}': 'Siku ya {d}',
  'Day ledger': 'Daftari la siku',
  'Decline': 'Kataa',
  'Delete my account (removes email link)':
      'Futa akaunti yangu (huondoa barua pepe)',
  'Deni': 'Deni',
  'Deni (credit)': 'Deni (mkopo)',
  'Due in {n} day(s) (day {d})': 'Linadaiwa baada ya siku {n} (siku ya {d})',
  'Duka': 'Duka',
  'Duka lako (your stall)': 'Duka lako',
  '{g} at {m}': '{g} kwa {m}',
  'Goods on credit': 'Bidhaa kwa deni',
  'Go to dusk': 'Nenda jioni',
  'Go to midday': 'Nenda adhuhuri',
  'Group vote': 'Kura ya kikundi',
  'Haggle': 'Bembeleza bei',
  'I agree to be emailed a sign-in link and to keep my email on file for this account.': 'Nakubali kutumiwa kiungo cha kuingia kwa barua pepe na barua pepe yangu ihifadhiwe kwa akaunti hii.',
  'I am 18 or older. Start': 'Nina miaka 18 au zaidi. Anza',
  'I am under 18': 'Nina chini ya miaka 18',
  'Join (share {p})': 'Jiunge (hisa {p})',
  '{n} of {max} members': 'Wanachama {n} kati ya {max}',
  'A lot is open for voting.': 'Kuna mzigo unasubiri kura.',
  'This request is yours. The other members vote on it.':
      'Ombi hili ni lako. Wanachama wengine wanapiga kura.',
  '{r}% interest, from your chama': 'Riba ya {r}%, kutoka chama chako',
  '{r}% interest, from the trader': 'Riba ya {r}%, kutoka kwa mfanyabiashara',
  'Karibu sokoni. A market-trading game.':
      'Karibu sokoni. Mchezo wa biashara ya sokoni.',
  'Lot on offer: {q} {g}': 'Mzigo unaotolewa: {q} {g}',
  'Market: {m} · {c} · v{v}': 'Soko: {m} · {c} · v{v}',
  'Market unreachable. Try demo mode.':
      'Soko halipatikani. Jaribu hali ya majaribio.',
  '{m} · {n} left': '{m} · {n} zimebaki',
  'Net for the day': 'Jumla ya siku',
  'Next day': 'Siku inayofuata',
  'next in {t}': 'inayofuata baada ya {t}',
  'next phase soon': 'awamu inayofuata karibuni',
  'No chama here yet.': 'Bado hakuna chama hapa.',
  'No explanation yet.': 'Bado hakuna maelezo.',
  'No lot on offer today.': 'Hakuna mzigo unaotolewa leo.',
  'No open deni. Good standing.': 'Huna deni. Uko vizuri.',
  'Not enough pts for this quantity.': 'Pointi hazitoshi kwa kiasi hiki.',
  'Nothing recorded for this day yet.': 'Bado hakuna kilichoandikwa siku hii.',
  '{n} (you)': '{n} (wewe)',
  'Offline demo mode': 'Hali ya majaribio bila mtandao',
  'Overdue: late fees are adding up':
      'Umechelewa: ada za kuchelewa zinaongezeka',
  'Owe {p}': 'Unadaiwa {p}',
  'Play as a guest (no email)': 'Cheza kama mgeni (bila barua pepe)',
  'Play now as a guest. Add an email later to save progress on another device or join a chama.': 'Cheza sasa kama mgeni. Weka barua pepe baadaye ili kuhifadhi maendeleo kwenye kifaa kingine au kujiunga na chama.',
  'Plays against a built-in market. Nothing is sent anywhere.':
      'Unacheza na soko lililo ndani ya programu. Hakuna kinachotumwa popote.',
  'Play the offline demo instead': 'Cheza majaribio bila mtandao badala yake',
  'Pointi': 'Pointi',
  'Pointi (pts) are for play only. They cannot be bought, sent or cashed out.': 'Pointi (pts) ni za mchezo tu. Haziwezi kununuliwa, kutumwa wala kubadilishwa kuwa pesa.',
  'Points are for play only. They can\'t be cashed out.':
      'Pointi ni za mchezo tu. Haziwezi kubadilishwa kuwa pesa.',
  'Pooled price {t}. Your share of the cost: {s}.':
      'Bei ya pamoja {t}. Sehemu yako ya gharama: {s}.',
  'Previous day': 'Siku iliyopita',
  'Pts into and out of the market': 'Pts zinazoingia na kutoka sokoni',
  'Pts plus stock value, minus what you owe.':
      'Pts pamoja na thamani ya mzigo, toa unachodaiwa.',
  'pts / unit': 'pts / kipimo',
  '{q} {g} from {m}': '{q} {g} kutoka kwa {m}',
  'Quantity': 'Kiasi',
  'Radio Soko': 'Radio Soko',
  'Radio Soko: no bulletins yet.': 'Radio Soko: bado hakuna habari.',
  'Rankings': 'Orodha ya viwango',
  'Rankings unavailable.': 'Orodha ya viwango haipatikani.',
  'Removed (cess, fees, spoilage)': 'Zilizotolewa (ushuru, ada, kuharibika)',
  'Repay': 'Lipa',
  'Reputation': 'Sifa',
  'Reputation: {t}. Repay on time to raise your limit.':
      'Sifa: {t}. Lipa kwa wakati ili kuongeza kikomo chako.',
  'Ripoti': 'Ripoti',
  'Sell': 'Uza',
  'Sell at {p}': 'Uza kwa {p}',
  'Sell to them: {p}': 'Wakununua kwa: {p}',
  'Settings': 'Mipangilio',
  'Soko': 'Soko',
  'Soko Kuu is for players aged 18 and over. Please come back when you are older.': 'Soko Kuu ni kwa wachezaji wenye miaka 18 au zaidi. Tafadhali rudi ukifikisha umri huo.',
  'Soko Report': 'Ripoti ya Soko',
  'Sorry': 'Samahani',
  'Spoils: about 10% lost each night':
      'Huharibika: karibu 10% hupotea kila usiku',
  'Start my own': 'Anzisha changu',
  'Start playing': 'Anza kucheza',
  'Take goods on credit': 'Chukua bidhaa kwa deni',
  'The market trades at midday. Come back then.':
      'Soko hufanya biashara adhuhuri. Rudi wakati huo.',
  '• There are no prizes and no paid chances. Prices follow fixed market rules.': '• Hakuna zawadi wala bahati nasibu ya kulipia. Bei hufuata kanuni zilizowekwa za soko.',
  '• This game is for people aged 18 and over.':
      '• Mchezo huu ni kwa watu wenye miaka 18 na zaidi.',
  'Trader health': 'Hali ya wafanyabiashara',
  'Try again': 'Jaribu tena',
  'Value {c}. You will owe about {o} (6% interest) within 5 days. Late debts grow.': 'Thamani {c}. Utadaiwa takriban {o} (riba ya 6%) ndani ya siku 5. Madeni yaliyochelewa huongezeka.',
  'Vote closes day {d} ({n} days left).':
      'Kura inafungwa siku ya {d} (siku {n} zimebaki).',
  'Why this price': 'Kwa nini bei hii',
  'You hold {n}': 'Unashikilia {n}',
  '• You play with pointi (pts). Pts are only for play: they cannot be bought, sent, or cashed out.': '• Unacheza kwa pointi (pts). Pts ni za mchezo tu: haziwezi kununuliwa, kutumwa wala kubadilishwa kuwa pesa.',
  'Your personal best: {n}': 'Bora yako binafsi: {n}',
  'Your play key is stored on this device. On the web it is a throwaway demo key: clearing site data starts a new player.': 'Ufunguo wako wa kucheza umehifadhiwa kwenye kifaa hiki. Kwenye wavuti ni ufunguo wa majaribio tu: ukifuta data ya tovuti utaanza mchezaji mpya.',
  '(yours)': '(yako)',
  'Your score': 'Alama zako',
  'Your shelves are empty. Buy something at Soko to begin.':
      'Rafu zako ni tupu. Nunua kitu sokoni ili kuanza.',
  'You voted {v}. The result is read when the day closes.':
      'Umepiga kura {v}. Matokeo yatasomwa siku ikifungwa.',
  '{y} yes · {no} no · {n} members': '{y} ndiyo · {no} hapana · wanachama {n}',
  'What if? Fast-forward': 'Vipi kama? Songa mbele',
  'A preview of the market. It does not change your game.':
      'Onyesho la soko. Halibadilishi mchezo wako.',
  '{n} days': 'Siku {n}',
  'No shock': 'Hakuna mshtuko',
  'Drought': 'Ukame',
  'Glut': 'Mazao mengi',
  'Run preview': 'Endesha onyesho',
  'Could not run the preview.': 'Onyesho halikuweza kuendeshwa.',
  'That is more than your own credit limit ({l}). A chama can lend the rest, but you are not in one. Join one in the Chama tab.': 'Hiyo ni zaidi ya kikomo chako cha deni ({l}). Chama kinaweza kukopesha kilichobaki, lakini hujajiunga na chama. Jiunge na kimoja kwenye kichupo cha Chama.',
  "That is more than your own credit limit ({l}). Your chama's common pot holds {c}, not enough to cover {n}. Ask for less, or invite members: a chama of about 4 members holds enough.": 'Hiyo ni zaidi ya kikomo chako cha deni ({l}). Mfuko wa pamoja wa chama chako una {c}, hautoshi kulipia {n}. Omba kidogo zaidi, au alika wanachama: chama cha wanachama 4 hivi kina fedha za kutosha.',
  'A chama lends only from its common pot ({c}, {m} members). Fewer than about 4 members usually hold too little to cover a big request, so the vote never opens.': 'Chama hukopesha kutoka kwenye mfuko wa pamoja tu ({c}, wanachama {m}). Wanachama chini ya 4 hivi kwa kawaida hawana fedha za kutosha kwa ombi kubwa, kwa hiyo kura haifunguliwi.',
  'OK': 'Sawa',
  'Dawn': 'Alfajiri',
  'Midday': 'Adhuhuri',
  'Dusk': 'Jioni',
  'yes': 'ndiyo',
  'no': 'hapana',
  'Mgeni': 'Mgeni',
  'Mfanyabiashara': 'Mfanyabiashara',
  'Mzoefu': 'Mzoefu',
};
