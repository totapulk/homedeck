import 'package:flutter/material.dart';

import '../models/vacuum.dart';
import '../state/vacuum_store.dart';

/// The robot vacuum, and the button knob 1 presses.
///
/// Shows its own plumbing on purpose. The robot is reached through a separate process on the
/// far side of a vendor cloud, and when nothing happens the useful question is which of those
/// links is down — not something anyone should have to work out by reading logs over ssh.
class VacuumCard extends StatelessWidget {
  const VacuumCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = VacuumScope.of(context);
    final vacuum = store.vacuum;

    if (vacuum == null) {
      return _Shell(
        child: Text(
          store.error ?? 'Etsitään imuria…',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final out = vacuum.activity.isOut;

    return _Shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Robot(active: out),
              const SizedBox(width: 14),
              Expanded(child: _Title(vacuum: vacuum, error: store.error)),
            ],
          ),
          const SizedBox(height: 16),
          out
              ? OutlinedButton.icon(
                  onPressed: store.busy ? null : store.dock,
                  icon: const Icon(Icons.home_outlined, size: 18),
                  label: const Text('Telakoi'),
                )
              : FilledButton.tonalIcon(
                  // Nothing to send a command to; the button would only fail politely.
                  onPressed: store.busy || !vacuum.isReachable ? null : store.start,
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: const Text('Imuroi'),
                ),
          if (!vacuum.isReachable) ...[
            const SizedBox(height: 16),
            const _Problem(
              title: 'Sidecar ei vastaa',
              detail: 'Imuria ohjataan erillisellä prosessilla, joka ei nyt vastaa. '
                  'Tarkista Pi:ltä: systemctl status homedeck-dreame',
            ),
          ] else if (vacuum.problem case final problem?) ...[
            const SizedBox(height: 16),
            _Problem(title: 'Imuri ei vastannut', detail: problem),
          ],
          const SizedBox(height: 16),
          _Details(vacuum: vacuum),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.vacuum, required this.error});

  final Vacuum vacuum;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
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
          _status(vacuum, error),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: error != null || !vacuum.isReachable
                ? scheme.error
                : scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  static String _status(Vacuum vacuum, String? error) {
    if (error != null) return error;
    if (!vacuum.isReachable) return 'Ei yhteyttä';

    final activity = switch (vacuum.activity) {
      VacuumActivity.docked => 'Telakassa',
      VacuumActivity.cleaning => 'Imuroi',
      VacuumActivity.returning => 'Palaa telakkaan',
      VacuumActivity.error => 'Vaatii huomiota',
      VacuumActivity.unknown => 'Ei tietoa',
    };

    final battery = vacuum.batteryPercent;
    return battery == null ? activity : '$activity · $battery %';
  }
}

/// The plumbing, small and always present, so a glance answers "is it me or is it broken".
class _Details extends StatelessWidget {
  const _Details({required this.vacuum});

  final Vacuum vacuum;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Divider(height: 1, color: scheme.onSurface.withValues(alpha: 0.08)),
        const SizedBox(height: 12),
        _Row(
          label: 'Yhteys',
          value: vacuum.isReachable ? 'Sidecar vastaa' : 'Ei vastausta',
          alert: !vacuum.isReachable,
        ),
        if (vacuum.raw case final raw?) _Row(label: 'Laitteen tila', value: raw),
        _Row(label: 'Päivitetty', value: _clock(vacuum.updatedAt)),
      ],
    );
  }

  static String _clock(DateTime at) {
    final local = at.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.alert = false});

  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: alert ? scheme.error : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(padding: const EdgeInsets.all(16), child: child),
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
        'Simuloitu',
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
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      ),
      child: Icon(
        Icons.cleaning_services,
        size: 24,
        color: active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
      ),
    );
  }
}
