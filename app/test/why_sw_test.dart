import 'package:flutter_test/flutter_test.dart';
import 'package:soko_kuu/l10n.dart';

void main() {
  // Real strings from econ/src/pricing.rs, econ/src/events.rs and the demo ledger.
  final why = <String, String>{
    'Price rise limited to 20% today; it may climb further tomorrow.':
        'Kupanda kwa bei kumezuiwa kwa 20% leo; huenda ikapanda zaidi kesho.',
    'Price fall limited to 20% today; it may drop further tomorrow.':
        'Kushuka kwa bei kumezuiwa kwa 20% leo; huenda ikashuka zaidi kesho.',
    'tomato is scarce at this stall, so the price is 12% above normal.': 'Nyanya: ni adimu kwenye duka hili, kwa hiyo bei iko 12% juu ya kawaida.',
    'maize is plentiful at this stall, so the price is 8% below normal.': 'Mahindi: ni nyingi kwenye duka hili, kwa hiyo bei iko 8% chini ya kawaida.',
    'onion stock is near normal, so the price sits near its usual level.': 'Vitunguu: akiba iko karibu na kawaida, kwa hiyo bei iko karibu na kiwango chake cha kawaida.',
    'Ukame (drought) cuts kale supply.':
        'Ukame unapunguza upatikanaji wa Sukuma wiki.',
    'Fuel costs add about 6% to fish.':
        'Gharama za mafuta zinaongeza takriban 6% kwa Samaki.',
    'The cut road delays deliveries.':
        'Barabara iliyokatika inachelewesha mizigo.',
    'Festival crowds push demand up.': 'Umati wa sikukuu unaongeza mahitaji.',
    'Harvest season: maize is arriving in bulk.':
        'Msimu wa mavuno: Mahindi kwa wingi sokoni.',
    'A glut of tomato pushes its price down.': 'Wingi wa Nyanya unashusha bei.',
    'Drought moved the mid price +15%.':
        'Ukame umebadilisha bei ya kati kwa +15%.',
    'Fuel costs moved the mid price -4%.':
        'Gharama za mafuta umebadilisha bei ya kati kwa -4%.',
    'Only 9 units left at njeri, so the ask is firm.':
        'Vimebaki vipimo 9 tu kwa Njeri, kwa hiyo bei ya kuuza ni imara.',
    'baraka has 37 units, enough to hold the ask steady.':
        'Baraka ana vipimo 37, vya kutosha kuweka bei ya kuuza thabiti.',
    'Trader spread is 6% each way: you buy at ask, sell at bid.': 'Tofauti ya mfanyabiashara ni 6% kila upande: unanunua kwa bei ya kuuza, unauza kwa bei ya kununua.',
    'tomato spoils: 10% of unsold stock is lost each night.':
        'Nyanya huharibika: 10% ya mzigo usiouzwa hupotea kila usiku.',
  };
  test('each why template has a Swahili translation; English is untouched', () {
    for (final e in why.entries) {
      expect(whyText(e.key, 'sw'), e.value, reason: e.key);
      expect(whyText(e.key, 'en'), e.key);
    }
  });
  test('unknown why sentence stays English', () {
    expect(whyText('Something new happened.', 'sw'), 'Something new happened.');
  });

  final news = <String, String>{
    'Ukame: the rains have failed. Farm produce will cost about 20% more and arrive slowly.': 'Ukame: mvua zimekosekana. Mazao ya shambani yatagharimu takriban 20% zaidi na yatafika polepole.',
    'Fuel prices are up. Transport costs lift every price a little, charcoal and fish most.': 'Bei ya mafuta imepanda. Gharama za usafiri zinapandisha kila bei kidogo, makaa na samaki zaidi.',
    'The main road is cut by floods. Deliveries are late and stalls run low.': 'Barabara kuu imekatika kwa mafuriko. Mizigo imechelewa na maduka yanaishiwa.',
    'Festival this week: buyers are everywhere and prices run about 10% higher.':
        'Sikukuu wiki hii: wanunuzi kila mahali na bei ziko takriban 10% juu.',
    'Harvest is in. Farm produce is arriving fast and prices ease by about 15%.': 'Mavuno yamefika. Mazao ya shambani yanaingia haraka na bei zinashuka takriban 15%.',
    'A glut of onion floods the market. Sellers are cutting prices.':
        'Wingi wa Vitunguu umejaa sokoni. Wauzaji wanashusha bei.',
  };
  test('econ news texts translate in sw, stay as sent in en', () {
    for (final e in news.entries) {
      expect(newsText('x', e.key, 'sw'), e.value, reason: e.key);
      expect(newsText('x', e.key, 'en'), e.key);
    }
  });
}
