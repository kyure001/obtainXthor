// ObtainX Thor: subscriptions to Obtainium import packs published online.
//
// A pack is a JSON file in Obtainium's export format ({"apps": [...],
// "settings": {...}}). A sync downloads every enabled pack and only adds the
// apps it has never seen before for that pack:
// - an app that is already tracked (same ID or same source URL) is left
//   untouched, so the user's settings are preserved;
// - an app the user removes does not come back on the next sync;
// - every pack app is filed into one of three families (emulators,
//   utilities, recomp projects), without overriding manual changes.
//
// User-facing strings stay in French on purpose: the app's UI language.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

const String packSubscriptionsPrefKey = 'thorPackSubscriptions';
const String packLastSyncPrefKey = 'thorPackLastSync';

const String packGroupingInitPrefKey = 'thorPackGroupingInit';

/// The three families shown in the app list. Each pack app gets exactly one
/// category, otherwise ObtainX would show it in several groups.
const String familyEmulators = 'Émulateurs';
const String familyUtilities = 'Utilitaires';
const String familyRecomp = 'Projets recomp';
const Map<String, int> familyColors = {
  familyEmulators: 0xFF3D7BD9,
  familyUtilities: 0xFF5E8C61,
  familyRecomp: 0xFFE8833A,
};

const Set<String> _emulatorCategories = {
  'emulator', 'emulators', 'émulateur', 'émulateurs', 'pc emulation',
  'dual screen', 'émulation pc',
};

const Set<String> _utilityCategories = {
  'pack', 'utilities', 'utility', 'utilitaires', 'outil thor',
};

/// Well-known emulators that some packs leave uncategorized.
const Set<String> _knownEmulatorNames = {
  'rpcsx', 'armsx1', 'armsx2', 'armsx3', 'eden', 'nethersx2', 'nethersx2-turnip',
  'aps3e', 'azahar', 'cemu', 'citra', 'citron neo', 'dolphin emulator',
  'duckstation', 'flycast', 'melonds', 'watermelonds', 'ppsspp', 'play!',
  'retroarch (aarch64)', 'vita3k', 'winlator', 'gopher64', 'xemu android',
};

/// Family of an app coming from a pack.
String familyForPackApp({
  required bool fromRecompPack,
  required List<String> categories,
  required String name,
}) {
  final lowerCats = categories.map((c) => c.toLowerCase().trim()).toSet();
  // A pack can flag an entry as an emulator (e.g. Eden DS in the Recomp
  // pack): this wins over the pack's default family.
  if (lowerCats.any(_emulatorCategories.contains)) return familyEmulators;
  if (fromRecompPack) {
    // The pack tracks itself ("Pack") and can flag tools ("Utilities"):
    // those are utilities, everything else is a game.
    return lowerCats.any(_utilityCategories.contains)
        ? familyUtilities
        : familyRecomp;
  }
  if (lowerCats.any(_emulatorCategories.contains) ||
      _knownEmulatorNames.contains(name.toLowerCase().trim())) {
    return familyEmulators;
  }
  return familyUtilities;
}

bool isRecompPackUrl(String url) =>
    normalizePackUrl(url).contains('obtainium_recomp_pack');

/// Minimum delay between two automatic syncs.
const Duration packAutoSyncInterval = Duration(hours: 20);

/// Built-in packs. They can be disabled but not removed.
const List<Map<String, String>> builtinPacks = [
  {
    'name': 'Recomp Pack (ports decomp/recomp)',
    'url':
        'https://github.com/kyure001/obtainium_recomp_pack/releases/latest/download/thor-pack.json',
  },
  {
    'name': 'Obtainium Emulation Pack (RJNY)',
    'url':
        'https://raw.githubusercontent.com/RJNY/Obtainium-Emulation-Pack/main/obtainium-emulation-pack-latest.json',
  },
  {
    'name': "Joey's Retro Handhelds",
    'url':
        'https://github.com/JoeysRetroHandhelds/joeys-obtainium/releases/latest/download/joeys-obtainium.json',
  },
];

class PackSubscription {
  PackSubscription({
    required this.name,
    required this.url,
    this.enabled = true,
    this.builtin = false,
    Set<String>? seen,
    Set<String>? categorized,
    this.lastSync,
    this.lastResult,
    this.lastError = false,
  }) : seen = seen ?? <String>{},
       categorized = categorized ?? <String>{};

  String name;
  String url;
  bool enabled;
  bool builtin;

  /// Keys (ID declared in the pack) already seen for this pack.
  Set<String> seen;

  /// Keys of apps already filed into their family (done once, so a
  /// category changed by hand is never overridden).
  Set<String> categorized;
  DateTime? lastSync;
  String? lastResult;
  bool lastError;

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'enabled': enabled,
    'builtin': builtin,
    'seen': seen.toList(),
    'categorized': categorized.toList(),
    'lastSync': lastSync?.toIso8601String(),
    'lastResult': lastResult,
    'lastError': lastError,
  };

  factory PackSubscription.fromJson(Map<String, dynamic> j) => PackSubscription(
    name: (j['name'] ?? '').toString(),
    url: (j['url'] ?? '').toString(),
    enabled: j['enabled'] != false,
    builtin: j['builtin'] == true,
    seen: ((j['seen'] as List<dynamic>?) ?? const [])
        .map((e) => e.toString())
        .toSet(),
    categorized: ((j['categorized'] as List<dynamic>?) ?? const [])
        .map((e) => e.toString())
        .toSet(),
    lastSync: j['lastSync'] == null
        ? null
        : DateTime.tryParse(j['lastSync'].toString()),
    lastResult: j['lastResult']?.toString(),
    lastError: j['lastError'] == true,
  );
}

/// Normalizes a source URL so two apps can be compared.
String normalizePackUrl(String url) {
  var u = url.trim().toLowerCase();
  u = u.replaceFirst(RegExp(r'^https?://(www\.)?'), '');
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  if (u.endsWith('.git')) u = u.substring(0, u.length - 4);
  return u;
}

/// Result of the pure merge computation (testable without Flutter).
class PackMergePlan {
  PackMergePlan(this.indicesToAdd, this.newSeen);
  final List<int> indicesToAdd;
  final Set<String> newSeen;
}

/// [entries]: (declared id, url) of every app in the pack, in order.
PackMergePlan planPackMerge({
  required List<(String id, String url)> entries,
  required Set<String> existingIds,
  required Set<String> existingUrls,
  required Set<String> seen,
}) {
  final Set<String> newSeen = {...seen};
  final Set<String> takenIds = {...existingIds};
  final Set<String> takenUrls = existingUrls.map(normalizePackUrl).toSet();
  final List<int> toAdd = [];
  for (var i = 0; i < entries.length; i++) {
    final (id, url) = entries[i];
    final String key = id.isNotEmpty ? id : normalizePackUrl(url);
    if (seen.contains(key)) continue;
    newSeen.add(key);
    final String nUrl = normalizePackUrl(url);
    if (takenIds.contains(id) || takenUrls.contains(nUrl)) continue;
    toAdd.add(i);
    takenIds.add(id);
    takenUrls.add(nUrl);
  }
  return PackMergePlan(toAdd, newSeen);
}

List<PackSubscription> loadPackSubscriptions(SettingsProvider sp) {
  final List<PackSubscription> subs = [];
  final String? raw = sp.prefs?.getString(packSubscriptionsPrefKey);
  if (raw != null && raw.isNotEmpty) {
    try {
      for (final e in jsonDecode(raw) as List<dynamic>) {
        subs.add(PackSubscription.fromJson(e as Map<String, dynamic>));
      }
    } catch (_) {}
  }
  for (final b in builtinPacks) {
    final existing = subs.where(
      (s) => normalizePackUrl(s.url) == normalizePackUrl(b['url']!),
    );
    if (existing.isEmpty) {
      subs.add(PackSubscription(name: b['name']!, url: b['url']!, builtin: true));
    } else {
      existing.first.builtin = true;
    }
  }
  return subs;
}

Future<void> savePackSubscriptions(
  SettingsProvider sp,
  List<PackSubscription> subs,
) async {
  await sp.prefs?.setString(
    packSubscriptionsPrefKey,
    jsonEncode(subs.map((s) => s.toJson()).toList()),
  );
}

DateTime? lastPackSync(SettingsProvider sp) {
  final String? raw = sp.prefs?.getString(packLastSyncPrefKey);
  return raw == null ? null : DateTime.tryParse(raw);
}

/// Summary of a sync, for display.
class PackSyncReport {
  int added = 0;
  int failedPacks = 0;
  final List<String> addedNames = [];
  @override
  String toString() => added == 0
      ? 'Aucune nouvelle appli'
      : '$added nouvelle(s) appli(s) : ${addedNames.join(', ')}';
}

bool _syncRunning = false;

/// Syncs every enabled pack. With [onlyIfDue], does nothing if the last sync
/// is more recent than [packAutoSyncInterval].
Future<PackSyncReport?> syncPacks(
  AppsProvider appsProvider,
  SettingsProvider sp, {
  bool onlyIfDue = false,
  LogsProvider? logs,
}) async {
  if (_syncRunning) return null;
  // The first sync after families were introduced runs right away, so
  // existing apps get filed without waiting 20 hours.
  if (onlyIfDue && sp.prefs?.getBool(packGroupingInitPrefKey) == true) {
    final DateTime? last = lastPackSync(sp);
    if (last != null && DateTime.now().difference(last) < packAutoSyncInterval) {
      return null;
    }
  }
  _syncRunning = true;
  final PackSyncReport report = PackSyncReport();
  try {
    await appsProvider.waitForAppsToLoad();
    final List<PackSubscription> subs = loadPackSubscriptions(sp);
    final Set<String> packCategoryNames = {};
    for (final sub in subs.where((s) => s.enabled)) {
      try {
        final http.Response res = await http
            .get(Uri.parse(sub.url), headers: {'User-Agent': 'ObtainX-Thor'})
            .timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) {
          throw Exception('HTTP ${res.statusCode}');
        }
        final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final List<dynamic> rawApps =
            (decoded is List ? decoded : decoded['apps']) as List<dynamic>;
        final List<App> packApps = [];
        for (final a in rawApps) {
          try {
            packApps.add(App.fromJson(a as Map<String, dynamic>));
          } catch (_) {}
        }

        final existing = appsProvider.getAppValues().map((e) => e.app).toList();
        final plan = planPackMerge(
          entries: packApps.map((a) => (a.id, a.url)).toList(),
          existingIds: existing.map((a) => a.id).toSet(),
          existingUrls: existing.map((a) => a.url).toSet(),
          seen: sub.seen,
        );

        final bool fromRecomp = isRecompPackUrl(sub.url);
        String keyOf(App a) => a.id.isNotEmpty ? a.id : normalizePackUrl(a.url);
        List<String> familyOf(App a) => [
          familyForPackApp(
            fromRecompPack: fromRecomp,
            categories: a.categories,
            name: a.finalName,
          ),
        ];

        final List<App> toSave = [];
        for (final i in plan.indicesToAdd) {
          final App a = packApps[i].copyWith(categories: familyOf(packApps[i]));
          final installed = await getInstalledInfo(a.id, printErr: false);
          toSave.add(
            a.copyWith(
              installedVersion: a.usesVersionCodeAsOsVersion
                  ? installed?.versionCode.toString()
                  : installed?.versionName,
            ),
          );
        }
        if (toSave.isNotEmpty) {
          await appsProvider.saveApps(toSave, onlyIfExists: false);
          report.added += toSave.length;
          report.addedNames.addAll(toSave.map((a) => a.finalName));
        }

        // Pack apps already tracked but not filed yet: file them once into
        // their family (migration from earlier versions).
        final Map<String, App> byId = {for (final a in existing) a.id: a};
        final Map<String, App> byUrl = {
          for (final a in existing) normalizePackUrl(a.url): a,
        };
        final List<App> recategorized = [];
        final Set<String> addedKeys = {
          for (final i in plan.indicesToAdd) keyOf(packApps[i]),
        };
        for (final p in packApps) {
          final String k = keyOf(p);
          if (sub.categorized.contains(k)) continue;
          sub.categorized.add(k);
          if (addedKeys.contains(k)) continue;
          final App? mine = byId[p.id] ?? byUrl[normalizePackUrl(p.url)];
          if (mine == null) continue;
          // Already filed (by another pack or by hand): leave it alone.
          if (mine.categories.any(familyColors.containsKey)) continue;
          final fam = familyOf(p);
          if (mine.categories.length != 1 || mine.categories.first != fam.first) {
            recategorized.add(mine.copyWith(categories: fam));
          }
        }
        if (recategorized.isNotEmpty) {
          await appsProvider.saveApps(recategorized);
        }

        // Pack category names: removed at the end of the sync once unused
        // (pack apps are filed into the three families instead).
        if (decoded is Map && decoded['settings'] is Map) {
          dynamic cats = decoded['settings']['categories'];
          if (cats is String) cats = jsonDecode(cats);
          if (cats is Map) packCategoryNames.addAll(cats.keys.map((k) => '$k'));
        }
        for (final a in packApps) {
          packCategoryNames.addAll(a.categories);
        }

        sub
          ..seen = plan.newSeen
          ..lastSync = DateTime.now()
          ..lastError = false
          ..lastResult = toSave.isEmpty
              ? 'À jour'
              : '${toSave.length} appli(s) ajoutée(s)';
      } catch (e) {
        report.failedPacks++;
        sub
          ..lastSync = DateTime.now()
          ..lastError = true
          ..lastResult = 'Échec : $e';
        unawaited(logs?.add('Pack ${sub.name}: $e', level: LogLevel.warning));
      }
    }
    await savePackSubscriptions(sp, subs);
    _applyFamilies(appsProvider, sp, packCategoryNames);
    await sp.prefs?.setString(
      packLastSyncPrefKey,
      DateTime.now().toIso8601String(),
    );
    unawaited(logs?.add('Synchro des packs : $report'));
    return report;
  } finally {
    _syncRunning = false;
  }
}


/// Adds the three families, removes pack categories no app uses anymore, and
/// turns on grouping by category once.
void _applyFamilies(
  AppsProvider appsProvider,
  SettingsProvider sp,
  Set<String> packCategoryNames,
) {
  final Map<String, int> cats = sp.categories;
  bool changed = false;
  familyColors.forEach((k, v) {
    if (!cats.containsKey(k)) {
      cats[k] = v;
      changed = true;
    }
  });
  final Set<String> used = {
    for (final a in appsProvider.getAppValues()) ...a.app.categories,
  };
  for (final name in packCategoryNames) {
    if (familyColors.containsKey(name)) continue;
    if (cats.containsKey(name) && !used.contains(name)) {
      cats.remove(name);
      changed = true;
    }
  }
  if (changed) sp.setCategories(cats, appsProvider: appsProvider);
  // The app itself goes into utilities if it has no category.
  final self = appsProvider.apps[obtainiumId]?.app;
  if (self != null && self.categories.isEmpty) {
    unawaited(appsProvider.saveApps([self.copyWith(categories: [familyUtilities])]));
  }
  if (sp.prefs?.getBool(packGroupingInitPrefKey) != true) {
    sp.prefs?.setBool(packGroupingInitPrefKey, true);
    if (sp.appsListGroupBy == AppsListGroupBy.none) {
      sp.appsListGroupBy = AppsListGroupBy.category;
    }
  }
}
