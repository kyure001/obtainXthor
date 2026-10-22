// ObtainX Thor: translations of every text added by this fork.
//
// One file for all languages. To add a language, copy the 'en' block, translate
// the values and use the language code as key (e.g. 'de', 'es'). Any language
// without a block falls back to English.
//
// Kept apart from assets/translations/*.json on purpose: those files belong to
// upstream ObtainX and change often, so editing them would cause merge
// conflicts every time the fork is updated.

import 'dart:ui' show Locale, PlatformDispatcher;

const String thorFallbackLanguage = 'en';

const Map<String, Map<String, String>> thorStrings = {
  'en': {
    // Group names in the app list (stored as category names).
    'family.emulators': 'Emulators',
    'family.utilities': 'Utilities',
    'family.recomp': 'Recomp projects',
    // Built-in packs.
    'pack.recomp': 'Recomp Pack (decomp/recomp ports)',
    'pack.rjny': 'Obtainium Emulation Pack (RJNY)',
    'pack.joey': "Joey's Retro Handhelds",
    // Settings → Packs.
    'packs.intro':
        'Subscribed packs are synced automatically once a day: only new apps '
        'are added, and apps you remove do not come back.',
    'packs.syncNow': 'Sync now',
    'packs.add': 'Add a pack',
    'packs.remove': 'Remove',
    'packs.neverSynced': 'Never synced',
    'packs.upToDate': 'Up to date',
    'packs.appsAdded': '{n} app(s) added',
    'packs.failed': 'Failed: {error}',
    'packs.alreadyRunning': 'A sync is already running',
    'packs.alreadyListed': 'This pack is already in the list',
    'packs.noNewApps': 'No new apps',
    'packs.newApps': '{n} new app(s): {names}',
    'packs.failedPacks': '{report} — {n} pack(s) failed',
    'packs.dialog.name': 'Name',
    'packs.dialog.url': 'JSON file URL',
    'packs.dialog.cancel': 'Cancel',
    'packs.dialog.add': 'Add',
    'packs.dateFormat': 'MM/dd HH:mm',
  },
  'fr': {
    'family.emulators': 'Émulateurs',
    'family.utilities': 'Utilitaires',
    'family.recomp': 'Projets recomp',
    'pack.recomp': 'Recomp Pack (ports decomp/recomp)',
    'pack.rjny': 'Obtainium Emulation Pack (RJNY)',
    'pack.joey': "Joey's Retro Handhelds",
    'packs.intro':
        'Les packs abonnés sont synchronisés automatiquement une fois par '
        'jour : seules les applis nouvelles sont ajoutées, celles que tu '
        'supprimes ne reviennent pas.',
    'packs.syncNow': 'Synchroniser maintenant',
    'packs.add': 'Ajouter un pack',
    'packs.remove': 'Retirer',
    'packs.neverSynced': 'Jamais synchronisé',
    'packs.upToDate': 'À jour',
    'packs.appsAdded': '{n} appli(s) ajoutée(s)',
    'packs.failed': 'Échec : {error}',
    'packs.alreadyRunning': 'Une synchronisation est déjà en cours',
    'packs.alreadyListed': 'Ce pack est déjà dans la liste',
    'packs.noNewApps': 'Aucune nouvelle appli',
    'packs.newApps': '{n} nouvelle(s) appli(s) : {names}',
    'packs.failedPacks': '{report} — {n} pack(s) en échec',
    'packs.dialog.name': 'Nom',
    'packs.dialog.url': 'URL du fichier JSON',
    'packs.dialog.cancel': 'Annuler',
    'packs.dialog.add': 'Ajouter',
    'packs.dateFormat': 'dd/MM HH:mm',
  },
};

/// Language used for the fork's texts: the language chosen in
/// Settings → Appearance → Language, otherwise the system language.
/// Only languages present in [thorStrings] are used; others fall back to English.
String thorLanguage([Locale? forcedLocale]) {
  final String code =
      (forcedLocale ?? PlatformDispatcher.instance.locale).languageCode;
  return thorStrings.containsKey(code) ? code : thorFallbackLanguage;
}

/// Translated text for [key] in [lang], with {placeholders} replaced by [args].
String thorT(String key, String lang, [Map<String, Object?> args = const {}]) {
  String text =
      thorStrings[lang]?[key] ?? thorStrings[thorFallbackLanguage]![key] ?? key;
  args.forEach((k, v) => text = text.replaceAll('{$k}', '$v'));
  return text;
}

/// Formats a date with the 'packs.dateFormat' pattern (dd, MM, HH, mm only).
String thorDate(DateTime d, String lang) {
  String two(int n) => n.toString().padLeft(2, '0');
  return thorT('packs.dateFormat', lang)
      .replaceAll('dd', two(d.day))
      .replaceAll('MM', two(d.month))
      .replaceAll('HH', two(d.hour))
      .replaceAll('mm', two(d.minute));
}

/// The three families of the app list, by stable ID.
const List<String> thorFamilyIds = ['emulators', 'utilities', 'recomp'];

/// Name of a family in a given language.
String thorFamilyName(String familyId, String lang) =>
    thorT('family.$familyId', lang);

/// Family ID whose name, in any language, equals [categoryName]; null otherwise.
String? thorFamilyIdOf(String categoryName) {
  for (final id in thorFamilyIds) {
    for (final lang in thorStrings.keys) {
      if (thorStrings[lang]!['family.$id'] == categoryName) return id;
    }
  }
  return null;
}
