/// The host's audit trail: account, device, and share-link events recorded by
/// the agent (`GET /v1/audit`). Reached from per-host settings.
///
/// Admin-only on the agent side — a device paired with a one-time code gets
/// 403, since the trail covers every device on that host. That's surfaced as
/// a plain explanation rather than a generic error, because it's the expected
/// outcome for a code-paired phone, not a fault.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/agent_client.dart' show AgentApiException;
import '../../core/api/providers.dart' show clientProvider;
import '../../core/l10n_ext.dart';
import '../../core/models/audit_entry.dart';
import '../../core/models/host.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/format.dart';
import '../../core/ui/screen_header.dart';
import '../../core/ui/state_views.dart';

final auditProvider = FutureProvider.autoDispose
    .family<List<AuditEntry>, String>((ref, hostId) async {
      final client = await ref.watch(clientProvider(hostId).future);
      return client.audit();
    });

class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key, required this.host});

  final Host host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(auditProvider(host.id));

    return Scaffold(
      appBar: AppBar(
        title: ScreenHeader(
          context.l10n.activityLogTitle,
          subtitle: host.label,
        ),
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (e, _) =>
                e is AgentApiException && e.statusCode == 403
                    ? _AdminOnlyNotice(message: context.l10n.activityLogAdminOnly)
                    : ErrorRetryCard(
                      message: humanizeError(e),
                      onRetry: () => ref.invalidate(auditProvider(host.id)),
                    ),
        data:
            (entries) =>
                entries.isEmpty
                    ? _AdminOnlyNotice(message: context.l10n.activityLogEmpty)
                    : RefreshIndicator(
                      onRefresh:
                          () async => ref.invalidate(auditProvider(host.id)),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          Spacing.md,
                          Spacing.sm,
                          Spacing.md,
                          Spacing.xl,
                        ),
                        itemCount: entries.length,
                        itemBuilder:
                            (context, i) => _AuditRow(entry: entries[i]),
                      ),
                    ),
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, tint) = _visualsFor(entry.action, scheme);
    final subtitle = [
      if (entry.actor.isNotEmpty) entry.actor,
      if (entry.target.isNotEmpty) entry.target,
      if (entry.detail.isNotEmpty) entry.detail,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: tint),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label(context, entry.action),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            formatDate(entry.at),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// Icon + tint per action. Anything the agent adds later falls through to a
  /// neutral default rather than rendering blank.
  (IconData, Color) _visualsFor(String action, ColorScheme scheme) =>
      switch (action) {
        'pair' => (LucideIcons.smartphone, Brand.online),
        'register' => (LucideIcons.userPlus, Brand.online),
        'login' => (LucideIcons.logIn, scheme.primary),
        'login_failed' => (LucideIcons.shieldAlert, scheme.error),
        'device_revoked' => (LucideIcons.ban, scheme.error),
        'device_removed' => (LucideIcons.trash2, scheme.error),
        'device_updated' => (LucideIcons.settings2, Brand.amber),
        'share_created' => (LucideIcons.link, Brand.accent),
        'share_revoked' => (LucideIcons.link2Off, Brand.amber),
        'agent_restart' => (LucideIcons.refreshCw, scheme.primary),
        _ => (LucideIcons.circleDot, scheme.onSurfaceVariant),
      };

  String _label(BuildContext context, String action) => switch (action) {
    'pair' => context.l10n.auditPair,
    'register' => context.l10n.auditRegister,
    'login' => context.l10n.auditLogin,
    'login_failed' => context.l10n.auditLoginFailed,
    'device_revoked' => context.l10n.auditDeviceRevoked,
    'device_removed' => context.l10n.auditDeviceRemoved,
    'device_updated' => context.l10n.auditDeviceUpdated,
    'share_created' => context.l10n.auditShareCreated,
    'share_revoked' => context.l10n.auditShareRevoked,
    'agent_restart' => context.l10n.auditAgentRestart,
    _ => action,
  };
}

class _AdminOnlyNotice extends StatelessWidget {
  const _AdminOnlyNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.scrollText,
              size: 56,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
