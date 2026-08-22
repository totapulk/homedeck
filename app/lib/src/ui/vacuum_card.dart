import 'package:flutter/material.dart';

import '../models/vacuum.dart';
import '../state/vacuum_store.dart';

/// The robot vacuum, and the button knob 1 presses.
class VacuumCard extends StatelessWidget {
  const VacuumCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = VacuumScope.of(context);
    final vacuum = store.vacuum;

    if (vacuum == null) {
      return _Shell(
        child: Text(
          store.error ?? 'Looking for the robot…',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final out = vacuum.activity.isOut;

    return _Shell(
      child: Row(
        children: [
          _Robot(active: out),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        vacuum.name,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (vacuum.isSimulated) ...[
                      const SizedBox(width: 8),
                      const _SimulatedChip(),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _status(vacuum, store.error),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: store.error != null ? scheme.error : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          out
              ? OutlinedButton(
                  onPressed: store.busy ? null : store.dock,
                  child: const Text('Send home'),
                )
              : FilledButton.tonal(
                  onPressed: store.busy ? null : store.start,
                  child: const Text('Clean'),
                ),
        ],
      ),
    );
  }

  static String _status(Vacuum vacuum, String? error) {
    if (error != null) return error;

    final activity = switch (vacuum.activity) {
      VacuumActivity.docked => 'Docked',
      VacuumActivity.cleaning => 'Cleaning',
      VacuumActivity.returning => 'Heading back',
      VacuumActivity.error => 'Needs attention',
      VacuumActivity.unknown => 'Unknown',
    };

    final battery = vacuum.batteryPercent;
    return battery == null ? activity : '$activity · $battery%';
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: SizedBox(height: 48, child: Center(child: child)),
    ),
  );
}

/// Says there is no robot on the other end. The flag comes from the backend, so the label
/// cannot drift out of step with what is actually there.
class _SimulatedChip extends StatelessWidget {
  const _SimulatedChip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Simulated',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _Robot extends StatelessWidget {
  const _Robot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      ),
      child: Icon(
        Icons.cleaning_services,
        size: 22,
        color: active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
      ),
    );
  }
}
