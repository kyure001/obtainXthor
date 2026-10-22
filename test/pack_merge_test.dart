import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/services/pack_subscriptions.dart';

void main() {
  group('planPackMerge', () {
    test('adds new apps and marks them as seen', () {
      final plan = planPackMerge(
        entries: [('a.id', 'https://github.com/x/a'), ('b.id', 'https://github.com/x/b')],
        existingIds: {},
        existingUrls: {},
        seen: {},
      );
      expect(plan.indicesToAdd, [0, 1]);
      expect(plan.newSeen, {'a.id', 'b.id'});
    });

    test('skips an app that is already tracked (same ID or same URL)', () {
      final plan = planPackMerge(
        entries: [
          ('a.id', 'https://github.com/x/a'),
          ('autre.id', 'https://github.com/X/B/'),
        ],
        existingIds: {'a.id'},
        existingUrls: {'https://www.github.com/x/b'},
        seen: {},
      );
      expect(plan.indicesToAdd, isEmpty);
      expect(plan.newSeen, {'a.id', 'autre.id'});
    });

    test('an app removed by the user does not come back', () {
      final plan = planPackMerge(
        entries: [('a.id', 'https://github.com/x/a')],
        existingIds: {},
        existingUrls: {},
        seen: {'a.id'},
      );
      expect(plan.indicesToAdd, isEmpty);
    });

    test('placeholder ID replaced after install: no duplicate', () {
      // The pack declares thorpack.x while the app is now tracked under its real
      // package name: the URL alone is enough to recognize it on first sync.
      final plan = planPackMerge(
        entries: [('thorpack.x', 'https://github.com/owner/x')],
        existingIds: {'com.vrai.package'},
        existingUrls: {'https://github.com/owner/x'},
        seen: {},
      );
      expect(plan.indicesToAdd, isEmpty);
    });

    test('duplicate entries in one pack: the first one wins', () {
      final plan = planPackMerge(
        entries: [('a.id', 'https://github.com/x/a'), ('a.id', 'https://github.com/y/a')],
        existingIds: {},
        existingUrls: {},
        seen: {},
      );
      expect(plan.indicesToAdd, [0]);
    });
  });

  test('normalizePackUrl', () {
    expect(normalizePackUrl('HTTPS://www.GitHub.com/A/B.git/'), 'github.com/a/b');
  });

  group('familyForPackApp', () {
    test('Recomp pack games go to the recomp family', () {
      expect(
        familyForPackApp(fromRecompPack: true, categories: ['Nintendo 64'], name: 'GoldenEye Recomp'),
        familyRecomp,
      );
    });
    test('an Emulator entry of the Recomp pack goes to emulators', () {
      expect(
        familyForPackApp(fromRecompPack: true, categories: ['Emulator'], name: 'Eden DS (Dual Screen)'),
        familyEmulators,
      );
    });
    test('the entry tracking the Recomp pack is a utility', () {
      expect(
        familyForPackApp(fromRecompPack: true, categories: ['Pack'], name: 'Obtainium Recomp Pack'),
        familyUtilities,
      );
    });
    test('a Utilities entry of the Recomp pack goes to utilities', () {
      expect(
        familyForPackApp(fromRecompPack: true, categories: ['Utilities'], name: 'SecondDeck'),
        familyUtilities,
      );
    });
    test('RJNY / Joey emulators (by category or known name)', () {
      expect(familyForPackApp(fromRecompPack: false, categories: ['Emulator'], name: 'PPSSPP'), familyEmulators);
      expect(familyForPackApp(fromRecompPack: false, categories: ['PC Emulation'], name: 'Winlator'), familyEmulators);
      expect(familyForPackApp(fromRecompPack: false, categories: ['Dual Screen'], name: 'Cemu'), familyEmulators);
      expect(familyForPackApp(fromRecompPack: false, categories: [], name: 'RPCSX'), familyEmulators);
    });
    test('frontends, streaming and tools go to utilities', () {
      expect(familyForPackApp(fromRecompPack: false, categories: ['Frontend'], name: 'Pegasus'), familyUtilities);
      expect(familyForPackApp(fromRecompPack: false, categories: ['Streaming'], name: 'Moonlight'), familyUtilities);
      expect(familyForPackApp(fromRecompPack: false, categories: [], name: 'Syncthing-Fork'), familyUtilities);
    });
  });

  test('isRecompPackUrl', () {
    expect(isRecompPackUrl('https://github.com/kyure001/obtainium_recomp_pack/releases/latest/download/thor-pack.json'), isTrue);
    expect(isRecompPackUrl('https://raw.githubusercontent.com/RJNY/Obtainium-Emulation-Pack/main/x.json'), isFalse);
  });
}
