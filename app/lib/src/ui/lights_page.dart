import 'package:flutter/material.dart';

import '../models/light.dart';
import '../models/light_group.dart';
import '../models/light_selection.dart';
import '../state/light_store.dart';
import 'light_tile.dart';

/// The lights module: what the knob is pointed at, and every lamp grouped by room.
class LightsPage extends StatelessWidget {
  const LightsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = LightScope.of(context);

    return Column(
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Two to a row on anything but the narrowest screen: on a phone in portrait
                  // that halves the scrolling, which is the whole point of the change.
                  final columns = constraints.maxWidth >= 300 ? 2 : 1;

                  // Density follows the width a tile actually ends up with, not the number of
                  // columns. Two columns on a tablet are still roomy enough for a switch.
                  final tileWidth = (constraints.maxWidth - 24 - (columns - 1) * 8) / columns;

                  return ListView(
                    // Short content still has to be draggable, or pull-to-refresh only works
                    // once there are enough lights to scroll.
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    children: _lightsSection(
                      store,
                      columns: columns,
                      dense: tileWidth < 200,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The lights in whatever state they are in, as list items rather than a widget of their own,
/// so that everything above them scrolls away with them.
List<Widget> _lightsSection(
  LightStore store, {
  required int columns,
  required bool dense,
}) => switch (store.state) {
  LightsLoading() => const [_Notice(child: CircularProgressIndicator())],
  LightsUnavailable(:final message) => [
    _Unavailable(message: message, onRetry: store.load),
  ],
  LightsReady(:final lights) when lights.isEmpty => const [_Notice(child: _Empty())],
  LightsReady(:final lights) => _rooms(store, lights, columns, dense),
};

List<Widget> _rooms(LightStore store, List<Light> lights, int columns, bool dense) {
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
      for (final row in _chunk(groupLights(roomLights), columns)) ...[
        _TileRow(row: row, columns: columns, dense: dense, store: store),
        const SizedBox(height: 8),
      ],
    ],
  ];
}

List<List<T>> _chunk<T>(List<T> items, int size) => [
  for (var start = 0; start < items.length; start += size)
    items.sublist(start, (start + size).clamp(0, items.length)),
];

/// One row of tiles. IntrinsicHeight so a two-bulb name wrapping onto a second line does not
/// leave its neighbour standing on nothing.
class _TileRow extends StatelessWidget {
  const _TileRow({
    required this.row,
    required this.columns,
    required this.dense,
    required this.store,
  });

  final List<LightGroup> row;
  final int columns;
  final bool dense;
  final LightStore store;

  @override
  Widget build(BuildContext context) {
    if (columns == 1) {
      return LightTile(
        group: row.first,
        isSelected: store.isGroupSelected(row.first),
        dense: dense,
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < columns; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            Expanded(
              child: index < row.length
                  ? LightTile(
                      group: row[index],
                      isSelected: store.isGroupSelected(row[index]),
                      dense: dense,
                    )
                  // An odd number of lamps leaves a hole; a hole keeps the last tile the same
                  // width as the rest, which is better than one wide card at the end.
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }
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
                    text: 'Nuppi ohjaa  ',
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
            TextButton(onPressed: onWiden, child: const Text('Kaikki valot')),
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
                            ? '${lights.length} valoa · kaikki pois'
                            : '${lights.length} valoa · $on päällä',
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
          FilledButton.tonal(onPressed: onRetry, child: const Text('Yritä uudelleen')),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Text(
    'Verkosta ei ole vielä löytynyt valoja.',
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.bodyMedium,
  );
}
