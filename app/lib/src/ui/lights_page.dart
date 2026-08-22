import 'package:flutter/material.dart';

import '../api/light_feed.dart';
import '../controller/controller_input.dart';
import '../models/light.dart';
import '../models/light_group.dart';
import '../models/light_selection.dart';
import '../state/light_store.dart';
import 'light_tile.dart';
import 'vacuum_card.dart';

class LightsPage extends StatelessWidget {
  const LightsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = LightScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('HomeDeck'),
        actions: [
          _KnobBadge(status: store.knob),
          const SizedBox(width: 12),
          _RealtimeBadge(status: store.realtime),
          IconButton(
            onPressed: store.load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (store.state case LightsReady(:final lights) when lights.isNotEmpty)
            _SelectionBar(
              label: store.selectionLabel,
              narrowed: store.selection is! AllLights,
              onWiden: store.selectAll,
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: store.load,
              // Tapping past the cards widens the selection back to everything, which is both
              // the forgiving thing to do on a wall panel and the gesture people try first.
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: store.selectAll,
                child: ListView(
                  // Short content still has to be draggable, or pull-to-refresh only works
                  // once there are enough lights to scroll.
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    // Above the lights and inside the same scroll: the vacuum is another thing
                    // in the flat, not a banner about one.
                    const _SectionHeader(title: 'Cleaning'),
                    const VacuumCard(),
                    ..._lightsSection(store),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The lights in whatever state they are in, as list items rather than a widget of their own,
/// so that everything above them scrolls away with them.
List<Widget> _lightsSection(LightStore store) => switch (store.state) {
  LightsLoading() => const [_Notice(child: CircularProgressIndicator())],
  LightsUnavailable(:final message) => [
    _Unavailable(message: message, onRetry: store.load),
  ],
  LightsReady(:final lights) when lights.isEmpty => const [_Notice(child: _Empty())],
  LightsReady(:final lights) => _rooms(store, lights),
};

List<Widget> _rooms(LightStore store, List<Light> lights) {
  final rooms = <String, List<Light>>{};
  for (final light in lights) {
    (rooms[light.room] ??= <Light>[]).add(light);
  }

  return [
    for (final MapEntry(key: room, value: roomLights) in rooms.entries) ...[
      _RoomHeader(
        room: room,
        lights: roomLights,
        selected: store.selection == RoomSelection(room),
        onTap: () => store.selectRoom(room),
      ),
      for (final group in groupLights(roomLights)) ...[
        LightTile(group: group, isSelected: store.isGroupSelected(group)),
        const SizedBox(height: 8),
      ],
    ],
  ];
}

/// A heading for something that is not a room, styled like the room headings so the vacuum
/// reads as a peer of the lights rather than an announcement above them.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 24, 14, 10),
    child: Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Gives something that used to fill the body room to breathe inside a list instead.
class _Notice extends StatelessWidget {
  const _Notice({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Center(child: child),
  );
}

/// Whether the physical knob is attached. Silent when there is no radio to speak of.
class _KnobBadge extends StatelessWidget {
  const _KnobBadge({required this.status});

  final ControllerStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: switch (status) {
        ControllerStatus.connected => 'The knob is connected',
        ControllerStatus.searching => 'Looking for the knob',
        ControllerStatus.disconnected => 'No knob found',
      },
      child: Icon(
        Icons.tune,
        size: 18,
        color: switch (status) {
          ControllerStatus.connected => scheme.primary,
          ControllerStatus.searching => scheme.onSurfaceVariant,
          ControllerStatus.disconnected => scheme.onSurfaceVariant.withValues(alpha: 0.35),
        },
      ),
    );
  }
}

/// Whether what is on screen is being kept current, or is just the last thing we heard.
class _RealtimeBadge extends StatelessWidget {
  const _RealtimeBadge({required this.status});

  final RealtimeStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, colour) = switch (status) {
      RealtimeStatus.live => ('Live', scheme.primary),
      RealtimeStatus.connecting => ('Connecting', scheme.onSurfaceVariant),
      RealtimeStatus.offline => ('Offline', scheme.error),
    };

    return Tooltip(
      message: switch (status) {
        RealtimeStatus.live => 'Changes made anywhere show up here immediately',
        RealtimeStatus.connecting => 'Reconnecting to the backend',
        RealtimeStatus.offline => 'Showing the last state we were told about',
      },
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colour),
          ),
        ],
      ),
    );
  }
}

/// Names what the knob will move, and offers the way back out to everything.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.label,
    required this.narrowed,
    required this.onWiden,
  });

  final String label;
  final bool narrowed;
  final VoidCallback onWiden;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
      child: Row(
        children: [
          Icon(Icons.tune, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Knob controls  ',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  TextSpan(
                    text: label,
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (narrowed)
            TextButton(onPressed: onWiden, child: const Text('All lights')),
        ],
      ),
    );
  }
}

/// Selecting a room is a primary action on a wall panel, so it gets a target sized for a
/// thumb rather than a caption sized for a mouse.
class _RoomHeader extends StatelessWidget {
  const _RoomHeader({
    required this.room,
    required this.lights,
    required this.selected,
    required this.onTap,
  });

  static const double _minTouchTarget = 52;

  final String room;
  final List<Light> lights;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = lights.where((light) => light.isOn).length;

    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Material(
        color: selected ? scheme.primary.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: _minTouchTarget),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        room.toUpperCase(),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: selected ? scheme.primary : scheme.onSurface,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        on == 0
                            ? '${lights.length} lights · all off'
                            : '${lights.length} lights · $on on',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.tune,
                  size: 18,
                  color: selected
                      ? scheme.primary
                      : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 44, color: scheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Text(
    'No lights found on the network yet.',
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.bodyMedium,
  );
}
