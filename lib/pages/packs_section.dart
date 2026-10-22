// ObtainX Thor: "Packs" settings section (UI strings are in French, the app's UI language).

import 'package:flutter/material.dart';
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
            ? 'Une synchronisation est déjà en cours'
            : report.failedPacks > 0
            ? '$report — ${report.failedPacks} pack(s) en échec'
            : report.toString(),
        context: context,
        type: report != null && report.failedPacks > 0
            ? ToastType.error
            : ToastType.info,
        duration: const Duration(seconds: 5),
      );
    } catch (e) {
      if (mounted) {
        showAppToast('Échec : $e', context: context, type: ToastType.error);
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
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajouter un pack'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nom'),
            ),
            TextField(
              controller: urlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'URL du fichier JSON',
                hintText: 'https://…/pack.json',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    final String url = urlCtrl.text.trim();
    if (ok != true || !url.startsWith('http')) return;
    if (_subs.any((s) => normalizePackUrl(s.url) == normalizePackUrl(url))) {
      if (mounted) showAppToast('Ce pack est déjà dans la liste', context: context);
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
      final d = s.lastSync!.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      parts.add(
        '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)} — ${s.lastResult ?? ''}',
      );
    } else {
      parts.add('Jamais synchronisé');
    }
    return parts.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return M3eExpressiveSettingsCard(
      colorScheme: cs,
      items: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Les packs abonnés sont synchronisés automatiquement une fois par '
            'jour : seules les applis nouvelles sont ajoutées, celles que tu '
            'supprimes ne reviennent pas.',
          ),
        ),
        for (final s in _subs)
          SwitchListTile(
            title: Text(s.name),
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
                    tooltip: 'Retirer',
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
                label: const Text('Synchroniser maintenant'),
              ),
              OutlinedButton.icon(
                onPressed: _addPack,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Ajouter un pack'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
