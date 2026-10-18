import 'package:flutter_test/flutter_test.dart';
import 'package:obtainium/services/pack_subscriptions.dart';

void main() {
  group('planPackMerge', () {
    test('ajoute les applis nouvelles et les marque comme vues', () {
      final plan = planPackMerge(
        entries: [('a.id', 'https://github.com/x/a'), ('b.id', 'https://github.com/x/b')],
        existingIds: {},
        existingUrls: {},
        seen: {},
      );
      expect(plan.indicesToAdd, [0, 1]);
      expect(plan.newSeen, {'a.id', 'b.id'});
    });

    test("n'ajoute pas une appli déjà suivie (même ID ou même URL)", () {
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

    test('une appli supprimée par l\'utilisateur ne revient pas', () {
      final plan = planPackMerge(
        entries: [('a.id', 'https://github.com/x/a')],
        existingIds: {},
        existingUrls: {},
        seen: {'a.id'},
      );
      expect(plan.indicesToAdd, isEmpty);
    });

    test('ID provisoire corrigé après installation : pas de doublon', () {
      // Le pack déclare thorpack.x, l'appli est désormais suivie sous son vrai
      // package : l'URL suffit à la reconnaître lors de la première synchro.
      final plan = planPackMerge(
        entries: [('thorpack.x', 'https://github.com/owner/x')],
        existingIds: {'com.vrai.package'},
        existingUrls: {'https://github.com/owner/x'},
        seen: {},
      );
      expect(plan.indicesToAdd, isEmpty);
    });

    test('doublon entre deux entrées du même pack : la première gagne', () {
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
    test('tout le pack Recomp va dans Projets recomp', () {
      expect(
        familyForPackApp(fromRecompPack: true, categories: ['Nintendo 64'], name: 'GoldenEye Recomp'),
        familyRecomp,
      );
    });
    test('une entrée Emulator du pack Recomp va chez les émulateurs', () {
      expect(
        familyForPackApp(fromRecompPack: true, categories: ['Emulator'], name: 'Eden DS (Dual Screen)'),
        familyEmulators,
      );
    });
    test("l'entrée qui suit le pack Recomp est un utilitaire", () {
      expect(
        familyForPackApp(fromRecompPack: true, categories: ['Pack'], name: 'Obtainium Recomp Pack'),
        familyUtilities,
      );
    });
    test('émulateurs RJNY / Joey (catégorie ou nom connu)', () {
      expect(familyForPackApp(fromRecompPack: false, categories: ['Emulator'], name: 'PPSSPP'), familyEmulators);
      expect(familyForPackApp(fromRecompPack: false, categories: ['PC Emulation'], name: 'Winlator'), familyEmulators);
      expect(familyForPackApp(fromRecompPack: false, categories: ['Dual Screen'], name: 'Cemu'), familyEmulators);
      expect(familyForPackApp(fromRecompPack: false, categories: [], name: 'RPCSX'), familyEmulators);
    });
    test('frontends, streaming et outils vont dans Utilitaires', () {
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
