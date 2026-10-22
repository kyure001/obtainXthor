// ObtainX Thor: "Packs" settings section. Texts come from lib/l10n/thor_strings.dart
// and follow the app language.

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:obtainium/l10n/thor_strings.dart';
import 'package:obtainium/providers/apps_provider.dart';
import 'package:obtainium/providers/logs_provider.dart';
import 'package:obtainium/providers/settings_provider.dart';
import 'package:obtainium/services/pack_subscriptions.dart';
import 'package:obtainium/theme/m3e_expressive_list.dart';
import 'package:obtainium/widgets/app_toast.dart';
import 'package:provider/provider.dart';

class PacksSettingsSection extends StatefulWidget {
  const PacksSettingsSection({super.key});

  @override
  State<PacksSettingsSection> createState() => _PacksSettingsSectionState();
}

class _PacksSettingsSectionState extends State<PacksSettingsSection> {
  List<PackSubscription> _subs = [];
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _subs = loadPackSubscriptions(context.read<SettingsProvider>());
    });
  }

  Future<void> _save() async {
    await savePackSubscriptions(context.read<SettingsProvider>(), _subs);
    _reload();
  }

  /// Language of the fork's texts: the app language, English if unsupported.
  String get _lang => thorLanguage(context.locale);

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      final report = await syncPacks(
        context.read<AppsProvider>(),
        context.read<SettingsProvider>(),
        logs: LogsProvider(),
      );
      if (!mounted) return;
      showAppToast(
        report == null
            ? thorT('packs.alreadyRunning', _lang)
            : report.describe(_lang),
        context: context,
        type: report != null && report.failedPacks > 0
            ? ToastType.error
            : ToastType.info,
        duration: const Duration(seconds: 5),
      );
    } catch (e) {
      if (mounted) {
        showAppToast(
          thorT('packs.failed', _lang, {'error': e}),
          context: context,
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
        _reload();
      }
    }
  }

  Future<void> _addPack() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final String lang = _lang;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(thorT('packs.add', lang)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: thorT('packs.dialog.name', lang),
              ),
            ),
            TextField(
              controller: urlCtrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: thorT('packs.dialog.url', lang),
                hintText: 'https://…/pack.json',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(thorT('packs.dialog.cancel', lang)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(thorT('packs.dialog.add', lang)),
          ),
        ],
      ),
    );
    final String url = urlCtrl.text.trim();
    if (ok != true || !url.startsWith('http')) return;
    if (_subs.any((s) => normalizePackUrl(s.url) == normalizePackUrl(url))) {
      if (mounted) {
        showAppToast(thorT('packs.alreadyListed', _lang), context: context);
      }
      return;
    }
    _subs.add(
      PackSubscription(
        name: nameCtrl.text.trim().isEmpty
            ? Uri.parse(url).pathSegments.last
            : nameCtrl.text.trim(),
        url: url,
      ),
    );
    await _save();
  }

  String _subtitle(PackSubscription s) {
    final parts = <String>[Uri.tryParse(s.url)?.host ?? s.url];
    if (s.lastSync != null) {
      parts.add(
        '${thorDate(s.lastSync!.toLocal(), _lang)} — ${s.displayResult(_lang) ?? ''}',
      );
    } else {
      parts.add(thorT('packs.neverSynced', _lang));
    }
    return parts.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return M3eExpressiveSettingsCard(
      colorScheme: cs,
      items: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(thorT('packs.intro', _lang)),
        ),
        for (final s in _subs)
          SwitchListTile(
            title: Text(s.displayName(_lang)),
            subtitle: Text(
              _subtitle(s),
              style: s.lastError ? TextStyle(color: cs.error) : null,
            ),
            isThreeLine: true,
            value: s.enabled,
            onChanged: (v) async {
              s.enabled = v;
              await _save();
            },
            secondary: s.builtin
                ? const Icon(Icons.inventory_2_rounded)
                : IconButton(
                    tooltip: thorT('packs.remove', _lang),
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      _subs.remove(s);
                      await _save();
                    },
                  ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _syncing ? null : _syncNow,
                icon: _syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
                label: Text(thorT('packs.syncNow', _lang)),
              ),
              OutlinedButton.icon(
                onPressed: _addPack,
                icon: const Icon(Icons.add_rounded),
                label: Text(thorT('packs.add', _lang)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
