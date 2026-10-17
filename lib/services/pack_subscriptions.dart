// ObtainX Thor : abonnement à des packs d'import Obtainium publiés en ligne.
//
// Un pack est un fichier JSON au format d'export Obtainium ({"apps": [...],
// "settings": {...}}). Une synchronisation télécharge chaque pack activé et
// ajoute uniquement les applis qu'elle n'a encore jamais vues pour ce pack :
// - une appli déjà suivie (même ID ou même URL de source) n'est pas modifiée,
//   les réglages de l'utilisateur restent intacts ;
// - une appli que l'utilisateur supprime ne revient pas à la synchro suivante ;
// - les catégories du pack absentes chez l'utilisateur sont ajoutées, sans
//   toucher aux couleurs existantes.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/providers/source_provider.dart';

const String packSubscriptionsPrefKey = 'thorPackSubscriptions';
const String packLastSyncPrefKey = 'thorPackLastSync';

/// Délai minimal entre deux synchronisations automatiques.
const Duration packAutoSyncInterval = Duration(hours: 20);

/// Packs proposés d'office. Ils peuvent être désactivés, pas supprimés.
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
    this.lastSync,
    this.lastResult,
    this.lastError = false,
  }) : seen = seen ?? <String>{};

  String name;
  String url;
  bool enabled;
  bool builtin;

  /// Clés (ID déclaré dans le pack) déjà rencontrées pour ce pack.
  Set<String> seen;
  DateTime? lastSync;
  String? lastResult;
  bool lastError;

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'enabled': enabled,
    'builtin': builtin,
    'seen': seen.toList(),
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
    lastSync: j['lastSync'] == null
        ? null
        : DateTime.tryParse(j['lastSync'].toString()),
    lastResult: j['lastResult']?.toString(),
    lastError: j['lastError'] == true,
  );
}

/// Normalise une URL de source pour comparer deux applis.
String normalizePackUrl(String url) {
  var u = url.trim().toLowerCase();
  u = u.replaceFirst(RegExp(r'^https?://(www\.)?'), '');
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  if (u.endsWith('.git')) u = u.substring(0, u.length - 4);
  return u;
}

/// Résultat du calcul pur d'une synchro (testable sans Flutter).
class PackMergePlan {
  PackMergePlan(this.indicesToAdd, this.newSeen);
  final List<int> indicesToAdd;
  final Set<String> newSeen;
}

/// [entries] : (id déclaré, url) de chaque appli du pack, dans l'ordre.
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

/// Résumé d'une synchro, pour l'affichage.
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

/// Synchronise tous les packs activés. Avec [onlyIfDue], ne fait rien si la
/// dernière synchro date de moins de [packAutoSyncInterval].
Future<PackSyncReport?> syncPacks(
  AppsProvider appsProvider,
  SettingsProvider sp, {
  bool onlyIfDue = false,
  LogsProvider? logs,
}) async {
  if (_syncRunning) return null;
  if (onlyIfDue) {
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

        final List<App> toSave = [];
        for (final i in plan.indicesToAdd) {
          final App a = packApps[i];
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

        // Catégories du pack manquantes chez l'utilisateur.
        if (decoded is Map && decoded['settings'] is Map) {
          dynamic cats = decoded['settings']['categories'];
          if (cats is String) cats = jsonDecode(cats);
          if (cats is Map) {
            final Map<String, int> current = sp.categories;
            bool changed = false;
            cats.forEach((k, v) {
              final int? color = v is int ? v : int.tryParse(v.toString());
              if (!current.containsKey(k) && color != null) {
                current[k.toString()] = color;
                changed = true;
              }
            });
            if (changed) {
              sp.setCategories(current, appsProvider: appsProvider);
            }
          }
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
