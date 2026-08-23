import 'package:flutter/material.dart';

import '../api/light_feed.dart';
import '../controller/controller_input.dart';
import '../state/fishing_store.dart';
import '../state/light_store.dart';
import '../state/vacuum_store.dart';
import 'fishing_card.dart';
import 'lights_page.dart';
import 'vacuum_card.dart';

/// The shell every module lives in.
///
/// The rail sits on the right rather than along the bottom. A bottom bar would cost this panel
/// the one dimension it cannot spare — on a phone mounted vertically on a wall, height is what
/// the lights need and the edge is where the thumb already is.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  static const List<_Module> _modules = [
    _Module(icon: Icons.lightbulb_outline, selected: Icons.lightbulb, label: 'Valot'),
    _Module(icon: Icons.cleaning_services_outlined, selected: Icons.cleaning_services, label: 'Imuri'),
    _Module(icon: Icons.set_meal_outlined, selected: Icons.set_meal, label: 'Kala'),
  ];

  void _refresh() {
    switch (_tab) {
      case 0:
        LightScope.of(context).load();
      case 1:
        VacuumScope.of(context).load();
      case 2:
        FishingScope.of(context).load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = LightScope.of(context);
    final scheme = Theme.of(context).colorScheme;

    // No app bar. A panel that only ever shows this one app does not need to be told its own
    // name, and the row it would take is a row of lamps. Status and refresh move into the rail,
    // which was going to be there anyway.
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: switch (_tab) {
                0 => const LightsPage(),
                1 => const _Single(child: VacuumCard()),
                _ => const _Single(child: FishingCard()),
              },
            ),
            // A hairline rather than a shadow: the rail is a different surface, not a floating
            // one, and a dark panel shows edges better than it shows elevation.
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: scheme.onSurface.withValues(alpha: 0.08),
            ),
            // Wide targets and large icons: this is reached standing up, at arm's length,
            // usually with the hand that is holding something else.
            NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: (index) => setState(() => _tab = index),
              labelType: NavigationRailLabelType.all,
              groupAlignment: 0,
              minWidth: 92,
              backgroundColor: const Color(0xFF16161C),
              indicatorColor: scheme.primary.withValues(alpha: 0.18),
              indicatorShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              leading: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 10),
                child: Column(
                  children: [
                    _KnobBadge(status: store.knob),
                    const SizedBox(height: 10),
                    _RealtimeBadge(status: store.realtime),
                    const SizedBox(height: 12),
                    // Separates what the panel is doing from what it can show.
                    SizedBox(
                      width: 34,
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: scheme.onSurface.withValues(alpha: 0.10),
                      ),
                    ),
                  ],
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: IconButton(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      iconSize: 22,
                      tooltip: 'Päivitä',
                      style: IconButton.styleFrom(
                        foregroundColor: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              selectedIconTheme: IconThemeData(size: 30, color: scheme.primary),
              unselectedIconTheme: IconThemeData(size: 28, color: scheme.onSurfaceVariant),
              selectedLabelTextStyle: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
              unselectedLabelTextStyle: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
              destinations: [
                for (final module in _modules)
                  NavigationRailDestination(
                    icon: Icon(module.icon),
                    selectedIcon: Icon(module.selected),
                    label: Text(module.label),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Module {
  const _Module({required this.icon, required this.selected, required this.label});

  final IconData icon;
  final IconData selected;
  final String label;
}

/// A module that is one card. Scrollable anyway, so pull-to-refresh works the same everywhere.
class _Single extends StatelessWidget {
  const _Single({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 12, 12, 24),
    children: [child],
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
        ControllerStatus.connected => 'Nuppi on yhdistetty',
        ControllerStatus.searching => 'Etsitään nuppia',
        ControllerStatus.disconnected => 'Nuppia ei löytynyt',
      },
      child: Icon(
        Icons.tune,
        size: 20,
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
///
/// A dot rather than a word: the rail has no room for "Yhdistetään", and this is glanced at
/// rather than read — the tooltip is there for the one time it matters.
class _RealtimeBadge extends StatelessWidget {
  const _RealtimeBadge({required this.status});

  final RealtimeStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colour = switch (status) {
      RealtimeStatus.live => scheme.primary,
      RealtimeStatus.connecting => scheme.onSurfaceVariant,
      RealtimeStatus.offline => scheme.error,
    };

    return Tooltip(
      message: switch (status) {
        RealtimeStatus.live => 'Muutokset näkyvät tässä heti, tehtiinpä ne missä tahansa',
        RealtimeStatus.connecting => 'Yhdistetään palvelimeen uudelleen',
        RealtimeStatus.offline => 'Näytetään viimeisin tiedossa oleva tila',
      },
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
      ),
    );
  }
}
