import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remote_file_explorer/core/api/agent_client.dart'
    show AgentApiException;
import 'package:remote_file_explorer/core/models/audit_entry.dart';
import 'package:remote_file_explorer/core/models/host.dart';
import 'package:remote_file_explorer/features/settings/audit_log_screen.dart';

import 'l10n_helpers.dart';
import 'shad_test_wrap.dart';

const _host = Host(id: 'h1', label: 'Test PC', address: '100.64.0.1');

Widget _app(Override override) => ProviderScope(
  overrides: [override],
  child: wrapShad(
    const MaterialApp(
      localizationsDelegates: l10nDelegates,
      home: AuditLogScreen(host: _host),
    ),
  ),
);

void main() {
  testWidgets('renders a readable label per recorded action', (tester) async {
    await tester.pumpWidget(
      _app(
        auditProvider('h1').overrideWith(
          (ref) async => [
            AuditEntry(
              id: 2,
              at: DateTime(2026, 7, 28, 21, 30),
              action: 'login_failed',
              actor: 'nobody',
              detail: 'from 127.0.0.1',
            ),
            AuditEntry(
              id: 1,
              at: DateTime(2026, 7, 28, 21, 0),
              action: 'pair',
              actor: 'Pixel 8',
              target: 'dev-abc',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Failed sign-in'), findsOneWidget);
    expect(find.text('Device paired'), findsOneWidget);
    // Actor, target and detail collapse into one subtitle line.
    expect(find.text('nobody · from 127.0.0.1'), findsOneWidget);
    expect(find.text('Pixel 8 · dev-abc'), findsOneWidget);
  });

  // An action the agent gains later must still render — the label falls back
  // to the raw action name instead of showing an empty row.
  testWidgets('falls back to the raw action for unknown events', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        auditProvider('h1').overrideWith(
          (ref) async => [
            AuditEntry(id: 1, at: DateTime(2026, 7, 28), action: 'future_event'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('future_event'), findsOneWidget);
  });

  // A code-paired phone gets 403 from the admin-only endpoint. That's the
  // expected outcome for it, so it must read as an explanation, not an error
  // with a retry button that can never succeed.
  testWidgets('explains the admin-only rule instead of erroring on 403', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        auditProvider('h1').overrideWith(
          (ref) async => throw AgentApiException(403, 'FORBIDDEN', 'nope'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining("Only the PC owner's account"), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('shows the empty state when nothing has been recorded', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(auditProvider('h1').overrideWith((ref) async => const [])),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing recorded yet'), findsOneWidget);
  });
}
