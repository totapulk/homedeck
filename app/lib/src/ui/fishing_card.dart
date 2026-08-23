import 'package:flutter/material.dart';

import '../models/fishing.dart';
import '../state/fishing_store.dart';

/// Today's bite forecast, from Kala Ukko.
///
/// The only panel here that controls nothing, so it is built to be read across a room rather
/// than operated: one number, large, and the conditions it was computed from underneath it.
class FishingCard extends StatelessWidget {
  const FishingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = FishingScope.of(context);
    final fishing = store.fishing;

    if (fishing == null || !fishing.isAvailable) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            store.error ??
                'Ei ennustetta — tarkista KalaUkko-osio tiedostosta appsettings.local.json.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final best = fishing.best;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (best != null) _Headline(lake: fishing.lakeName, best: best),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (fishing.comment case final comment?) ...[
                  _Quote(comment: comment),
                  const SizedBox(height: 16),
                ],
                if (fishing.weather case final weather?) _Conditions(weather: weather),
                if (fishing.species.length > 1) ...[
                  const SizedBox(height: 16),
                  Text(
                    'MUUT LAJIT',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Others(species: fishing.species.skip(1).toList()),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The lake, the fish and the number, on a wash of colour that tracks the number itself.
class _Headline extends StatelessWidget {
  const _Headline({required this.lake, required this.best});

  final String lake;
  final FishingSpecies best;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strength = (best.index / 100).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.30 * strength),
            scheme.primary.withValues(alpha: 0.06 * strength),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  lake.toUpperCase(),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSurface,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(best.emoji, style: const TextStyle(fontSize: 30)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${best.index}',
                style: TextStyle(
                  fontSize: 54,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        best.name,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'paras veto tänään',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: strength,
              minHeight: 7,
              backgroundColor: scheme.onSurface.withValues(alpha: 0.10),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ukko's own words, marked as a quotation because they are somebody else's voice and the only
/// part of this card that is not a measurement.
class _Quote extends StatelessWidget {
  const _Quote({required this.comment});

  final String comment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: scheme.primary.withValues(alpha: 0.55), width: 3),
        ),
      ),
      child: Text(
        comment,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontStyle: FontStyle.italic,
          height: 1.35,
        ),
      ),
    );
  }
}

class _Conditions extends StatelessWidget {
  const _Conditions({required this.weather});

  final FishingWeather weather;

  static const Map<String, String> _trends = {
    'nopeasti_laskeva': 'laskee nopeasti',
    'hitaasti_laskeva': 'laskee hitaasti',
    'tasainen': 'tasainen',
    'hitaasti_nouseva': 'nousee hitaasti',
    'nopeasti_nouseva': 'nousee nopeasti',
    'pumppaava': 'pumppaa',
  };

  static const Map<String, String> _clouds = {
    'selkea': 'Selkeä',
    'puolipilvinen': 'Puolipilvinen',
    'pilvinen': 'Pilvinen',
  };

  @override
  Widget build(BuildContext context) {
    final air = weather.airTempC;
    final trend = _trends[weather.pressureTrend];

    return Wrap(
      spacing: 18,
      runSpacing: 10,
      children: [
        if (air != null) _Fact(icon: Icons.thermostat, label: '${air.round()} °C'),
        // Says when the water temperature is a guess rather than a reading, because the index
        // leans on it heavily and the nearest station can be fifty kilometres away.
        _Fact(
          icon: Icons.water_drop_outlined,
          label: '${weather.waterTempC} °C vesi'
              '${weather.waterIsMeasured ? '' : ' (arvio)'}',
        ),
        _Fact(icon: Icons.air, label: '${weather.windMs} m/s'),
        _Fact(
          icon: Icons.speed,
          label: trend == null
              ? '${weather.pressureHpa} hPa'
              : '${weather.pressureHpa} hPa · $trend',
        ),
        if (_clouds[weather.cloud] case final cloud?)
          _Fact(icon: Icons.cloud_outlined, label: cloud),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface),
        ),
      ],
    );
  }
}

class _Others extends StatelessWidget {
  const _Others({required this.species});

  final List<FishingSpecies> species;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        for (final entry in species)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Text(entry.emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 78,
                  child: Text(
                    entry.name,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (entry.index / 100).clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: scheme.primary.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 24,
                  child: Text(
                    '${entry.index}',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
