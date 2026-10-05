import '../../widgets/app_ui.dart';
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
  void _openPreferences() => setState(() => _preferences = true);
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_preferences,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && _preferences) setState(() => _preferences = false);
    },
    child: Scaffold(
      body: _preferences
          ? PreferencesScreen(
              uid: widget.uid,
              onBack: () => setState(() => _preferences = false),
            )
          : switch (_selected) {
              1 => DiscoveryScreen(
                uid: widget.uid,
                onPreferences: _openPreferences,
                onProfile: () => setState(() => _selected = 3),
              ),
              2 => MatchesScreen(uid: widget.uid),
              3 => ProfileScreen(
                uid: widget.uid,
                logout: LogoutButton(service: widget.service),
              ),
              _ => Scaffold(
                appBar: AppBar(title: const Text('Tinder Universitario')),
                body: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const AppMark(size: 88),
                            const SizedBox(height: 24),
                            Text(
                              'Personas reales.\nConexiones que cuentan.',
                              style: Theme.of(context).textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Univalle · Cochabamba',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Completa y activa tu perfil, guarda tus preferencias y descubre personas compatibles.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: () => setState(() => _selected = 1),
                              child: const Text('Descubrir personas'),
                            ),
                            TextButton(
                              onPressed: _openPreferences,
                              child: const Text(
                                'Preferencias de descubrimiento',
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() => _selected = 3),
                              child: const Text('Completar mi perfil'),
                            ),
                            const SizedBox(height: 16),
                            LogoutButton(service: widget.service),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            },
      bottomNavigationBar: _preferences
          ? null
          : NavigationBar(
              selectedIndex: _selected,
              onDestinationSelected: (value) =>
                  setState(() => _selected = value),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Inicio',
                ),
                NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon: Icon(Icons.explore_rounded),
                  label: 'Descubrir',
                ),
                NavigationDestination(
                  icon: Icon(Icons.favorite_outline),
                  selectedIcon: Icon(Icons.favorite_rounded),
                  label: 'Matches',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'Perfil',
                ),
              ],
            ),
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
