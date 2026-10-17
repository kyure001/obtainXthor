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
}
