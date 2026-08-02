import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:flutter/material.dart';

import 'config_director_scope.dart';
import 'theme.dart';

/// Edits the context ConfigDirector evaluates targeting rules against.
///
/// Saving calls [ConfigDirectorClient.updateContext], which re-evaluates every
/// config; the values on the Flags screen update on their own once it returns.
class ContextScreen extends StatefulWidget {
  const ContextScreen({super.key});

  @override
  State<ContextScreen> createState() => _ContextScreenState();
}

class _ContextScreenState extends State<ContextScreen> {
  final _userId = TextEditingController();
  final _userName = TextEditingController();
  final _userRole = TextEditingController();

  /// Set while an update is in flight, so the buttons cannot be double-tapped.
  bool _updating = false;

  @override
  void dispose() {
    _userId.dispose();
    _userName.dispose();
    _userRole.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final role = _userRole.text.trim();
    await _update(
      ConfigDirectorContext(
        id: _emptyToNull(_userId.text),
        name: _emptyToNull(_userName.text),
        traits: role.isEmpty ? null : {'role': role},
      ),
      'Context saved',
    );
  }

  Future<void> _clear() async {
    _userId.clear();
    _userName.clear();
    _userRole.clear();
    await _update(const ConfigDirectorContext(), 'Context cleared');
  }

  Future<void> _update(
    ConfigDirectorContext userContext,
    String message,
  ) async {
    FocusScope.of(context).unfocus();
    setState(() => _updating = true);
    try {
      await ConfigDirectorScope.of(context).updateContext(userContext);
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  static String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      children: [
        Text('Context', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Configure the context sent to ConfigDirector when evaluating '
          'feature flags.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _userId,
          decoration: const InputDecoration(
            labelText: 'User ID',
            hintText: 'e.g. user-123',
          ),
          autocorrect: false,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _userName,
          decoration: const InputDecoration(
            labelText: 'User Name',
            hintText: 'e.g. Jane Smith',
          ),
          autocorrect: false,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _userRole,
          decoration: const InputDecoration(
            labelText: 'User Role',
            hintText: 'e.g. admin, viewer, editor',
            helperText: 'Sent as the "role" trait',
          ),
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            FilledButton(
              onPressed: _updating ? null : _save,
              child: const Text('Save'),
            ),
            const SizedBox(width: 14),
            OutlinedButton(
              onPressed: _updating ? null : _clear,
              child: const Text('Clear'),
            ),
            if (_updating) ...[
              const SizedBox(width: 16),
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        const SizedBox(height: 32),
        const _ActiveContext(),
      ],
    );
  }
}

/// The context the client is currently evaluating configs against.
///
/// It is read from the client rather than from the fields above, because a new
/// context only takes effect once the client has re-connected with it.
class _ActiveContext extends StatelessWidget {
  const _ActiveContext();

  @override
  Widget build(BuildContext context) {
    final client = ConfigDirectorScope.of(context);
    final theme = Theme.of(context);

    return StreamBuilder<ContextUpdatedEvent>(
      stream: client.onContextUpdated,
      builder: (context, snapshot) {
        final active = client.context;
        final traits = active?.traits;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Active context', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                active == null
                    ? 'None — configs are evaluated without a context.'
                    : 'id: ${active.id ?? '—'}\n'
                          'name: ${active.name ?? '—'}\n'
                          'traits: ${traits == null || traits.isEmpty ? '—' : traits}',
                style: AppTheme.monospace(
                  theme.textTheme.bodySmall!,
                ).copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        );
      },
    );
  }
}
