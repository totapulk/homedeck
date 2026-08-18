import 'package:flutter/material.dart';

import '../api/light_feed.dart';
import '../models/light.dart';
import '../state/light_store.dart';
import 'light_tile.dart';

class LightsPage extends StatelessWidget {
  const LightsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = LightScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('HomeDeck'),
        actions: [
          _RealtimeBadge(status: store.realtime),
          IconButton(
            onPressed: store.load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: switch (store.state) {
        LightsLoading() => const Center(child: CircularProgressIndicator()),
        LightsUnavailable(:final message) => _Unavailable(
          message: message,
          onRetry: store.load,
        ),
        LightsReady(:final lights) when lights.isEmpty => const _Empty(),
        LightsReady(:final lights) => RefreshIndicator(
          onRefresh: store.load,
          child: _RoomList(lights: lights, selectedId: store.selected?.id),
        ),
      },
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

class _RoomList extends StatelessWidget {
  const _RoomList({required this.lights, this.selectedId});

  final List<Light> lights;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final rooms = <String, List<Light>>{};
    for (final light in lights) {
      (rooms[light.room] ??= <Light>[]).add(light);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final MapEntry(key: room, value: roomLights) in rooms.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Text(
              room.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 1.2,
              ),
            ),
          ),
          for (final light in roomLights) ...[
            LightTile(light: light, isSelected: light.id == selectedId),
            const SizedBox(height: 8),
          ],
        ],
      ],
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

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      'No lights found on the network yet.',
      style: Theme.of(context).textTheme.bodyMedium,
    ),
  );
}
