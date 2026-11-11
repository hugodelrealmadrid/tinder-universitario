import '../notifications/notifications.dart';
import '../stories/story_shelf.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/brand_header.dart';
import '../../theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../auth/auth_service.dart';
import '../profile/profile_screen.dart';
import '../discovery/discovery_screen.dart';
import '../preferences/preferences_screen.dart';
import '../matches/matches_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.service, required this.uid});
  final AuthService service;
  final String uid;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selected = 0;
  bool _preferences = false;
  final _history = <int>[];

  void _select(int destination) {
    if (destination == _selected && !_preferences) return;
    setState(() {
      if (destination != _selected) _history.add(_selected);
      _selected = destination;
      _preferences = false;
    });
  }

  void _back() => setState(() {
    if (_preferences) {
      _preferences = false;
    } else if (_history.isNotEmpty) {
      _selected = _history.removeLast();
    }
  });
  void _openPreferences() => setState(() => _preferences = true);
  static const _labels = ['Inicio', 'Descubrir', 'Matches', 'Perfil'];
  static const _icons = [
    Icons.home_outlined,
    Icons.explore_outlined,
    Icons.favorite_outline,
    Icons.person_outline,
  ];
  static const _selectedIcons = [
    Icons.home_rounded,
    Icons.explore_rounded,
    Icons.favorite_rounded,
    Icons.person_rounded,
  ];
  Widget _content() => _preferences
      ? PreferencesScreen(uid: widget.uid, onBack: _back)
      : switch (_selected) {
          1 => DiscoveryScreen(
            uid: widget.uid,
            onPreferences: _openPreferences,
            onProfile: () => _select(3),
          ),
          2 => MatchesScreen(uid: widget.uid),
          3 => ProfileScreen(
            uid: widget.uid,
            logout: LogoutButton(service: widget.service),
          ),
          _ => Scaffold(
            appBar: AppBar(
              title: const BrandHeader('LIGO'),
              actions: const [NotificationBell()],
            ),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 850),
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      if (const bool.fromEnvironment('LIGO_STORIES'))
                        const StoryShelf(),
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF981445),
                              Color(0xFF502690),
                              Color(0xFF241231),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                AppMark(size: 58),
                                SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    'Tu comunidad universitaria',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),
                            const Text(
                              'Personas reales.\nConexiones que cuentan.',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Tu próxima conexión puede estar más cerca de lo que imaginas.',
                              style: TextStyle(
                                color: Color(0xFFF5DCE6),
                                fontSize: 16,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 28),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppColors.wine,
                              ),
                              onPressed: () => _select(1),
                              icon: const Icon(Icons.explore_outlined),
                              label: const Text('Descubrir personas'),
                            ),
                          ],
                        ),
                      ),
                      const SectionHeading(
                        'A tu manera',
                        icon: Icons.auto_awesome_outlined,
                        subtitle: 'Un perfil auténtico es el mejor comienzo.',
                      ),
                      Card(
                        child: ListTile(
                          leading: const Icon(
                            Icons.person_outline,
                            color: AppColors.coral,
                          ),
                          title: const Text('Completar mi perfil'),
                          subtitle: const Text(
                            'Comparte tu historia y tus mejores fotos',
                          ),
                          trailing: const Icon(Icons.arrow_forward_rounded),
                          onTap: () => _select(3),
                        ),
                      ),
                      Card(
                        child: ListTile(
                          leading: const Icon(
                            Icons.tune_rounded,
                            color: AppColors.coral,
                          ),
                          title: const Text('Preferencias de descubrimiento'),
                          subtitle: const Text(
                            'Edad, carrera y personas compatibles contigo',
                          ),
                          trailing: const Icon(Icons.arrow_forward_rounded),
                          onTap: _openPreferences,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Center(child: Text('Tu mundo. Nuevas conexiones.')),
                      const SizedBox(height: 16),
                      Center(child: LogoutButton(service: widget.service)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        };
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_preferences && _history.isEmpty,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _back();
    },
    child: LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 1000;
        return Scaffold(
          body: Row(
            children: [
              if (wide) ...[
                NavigationRail(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  minWidth: 110,
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: AppMark(size: 54),
                  ),
                  labelType: NavigationRailLabelType.all,
                  selectedIndex: _selected,
                  onDestinationSelected: _select,
                  destinations: [
                    for (var i = 0; i < _labels.length; i++)
                      NavigationRailDestination(
                        icon: i == 2
                            ? UnreadChatIcon(_icons[i])
                            : Icon(_icons[i]),
                        selectedIcon: i == 2
                            ? UnreadChatIcon(_selectedIcons[i])
                            : Icon(_selectedIcons[i]),
                        label: Text(_labels[i]),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
              ],
              Expanded(child: _content()),
            ],
          ),
          bottomNavigationBar: _preferences || wide
              ? null
              : DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: NavigationBar(
                    height: 68,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    indicatorColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    elevation: 0,
                    labelBehavior:
                        NavigationDestinationLabelBehavior.alwaysShow,
                    selectedIndex: _selected,
                    onDestinationSelected: _select,
                    destinations: [
                      for (var i = 0; i < _labels.length; i++)
                        NavigationDestination(
                          icon: i == 2
                              ? UnreadChatIcon(_icons[i])
                              : Icon(_icons[i]),
                          selectedIcon: i == 2
                              ? UnreadChatIcon(_selectedIcons[i])
                              : Icon(_selectedIcons[i]),
                          label: _labels[i],
                        ),
                    ],
                  ),
                ),
        );
      },
    ),
  );
}

class LogoutButton extends StatefulWidget {
  const LogoutButton({super.key, required this.service});
  final AuthService service;
  @override
  State<LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<LogoutButton> {
  bool _busy = false;
  String? _error;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      OutlinedButton(
        onPressed: _busy
            ? null
            : () async {
                setState(() {
                  _busy = true;
                  _error = null;
                });
                try {
                  await widget.service.logout();
                } catch (error) {
                  if (mounted) setState(() => _error = firebaseError(error));
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
        child: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Cerrar sesión'),
      ),
    ],
  );
}
