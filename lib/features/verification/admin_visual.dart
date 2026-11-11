import '../notifications/notifications.dart';
import 'package:flutter/material.dart';
import 'admin_theme.dart';
export 'admin_overview.dart';
import '../../widgets/app_ui.dart';
import 'backend_client.dart';
import 'admin_workspace.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({
    super.key,
    required this.root,
    required this.selected,
    required this.onSelected,
    required this.child,
    required this.logout,
    required this.onDating,
    required this.catalogsAllowed,
  });
  final bool root, catalogsAllowed;
  final String selected;
  final ValueChanged<String> onSelected;
  final Widget child, logout;
  final VoidCallback onDating;
  Map<String, (String, IconData)> get pages => {
    if (catalogsAllowed)
      'dashboard': ('Resumen', Icons.space_dashboard_outlined),
    if (catalogsAllowed) 'users': ('Usuarios', Icons.people_outline),
    if (catalogsAllowed && root)
      'roles': ('Roles y permisos', Icons.admin_panel_settings_outlined),
    'requests': ('Verificaciones', Icons.verified_user_outlined),
    'reports': ('Reportes', Icons.flag_outlined),
    if (root) 'audit': ('Auditoría', Icons.receipt_long_outlined),
    if (catalogsAllowed &&
        root &&
        const bool.fromEnvironment('LIGO_MULTIUNIVERSITY'))
      'universities': ('Universidades', Icons.account_balance_outlined),
    if (catalogsAllowed) 'careers': ('Carreras', Icons.school_outlined),
    if (catalogsAllowed) 'interests': ('Intereses', Icons.favorite_border),
    'settings': ('Configuración', Icons.settings_outlined),
  };
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  bool _collapsed = false;
  final _menuScroll = ScrollController();
  @override
  void dispose() {
    _menuScroll.dispose();
    super.dispose();
  }

  static const _groups = {
    'COMUNIDAD': ['dashboard', 'users', 'roles'],
    'MODERACIÓN': ['requests', 'reports', 'audit'],
    'CATÁLOGOS': ['universities', 'careers', 'interests'],
  };
  Widget _item(
    BuildContext context,
    String key, {
    required bool compact,
    required bool drawer,
  }) {
    final page = widget.pages[key]!;
    final active = widget.selected == key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Tooltip(
        message: page.$1,
        excludeFromSemantics: true,
        child: Semantics(
          selected: active,
          button: true,
          label: compact ? page.$1 : null,
          child: Material(
            color: active ? const Color(0xFF382051) : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            child: InkWell(
              key: ValueKey('admin-nav-$key'),
              borderRadius: BorderRadius.circular(11),
              onTap: () {
                if (drawer) Navigator.pop(context);
                widget.onSelected(key);
              },
              child: SizedBox(
                height: 44,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
                  child: Row(
                    mainAxisAlignment: compact
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: [
                      Icon(
                        page.$2,
                        size: 21,
                        color: active ? Colors.white : const Color(0xFFBABAC8),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            page.$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: active
                                  ? Colors.white
                                  : const Color(0xFFE3E3EA),
                              fontSize: 13,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (active)
                          const Icon(
                            Icons.chevron_right,
                            size: 15,
                            color: Colors.white70,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sidebar(BuildContext context, {bool drawer = false}) {
    return LayoutBuilder(
      builder: (context, bounds) {
        final compact = !drawer && (_collapsed || bounds.maxWidth < 190);
        return ColoredBox(
          color: AdminTheme.sidebar,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  key: const ValueKey('admin-fixed-header'),
                  height: 72,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 10 : 16,
                    ),
                    child: compact
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const AppMark(size: 24),
                              IconButton(
                                tooltip: 'Expandir menú',
                                onPressed: () =>
                                    setState(() => _collapsed = false),
                                constraints: const BoxConstraints.tightFor(
                                  width: 44,
                                  height: 32,
                                ),
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                  Icons.menu_open_rounded,
                                  size: 19,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (!compact)
                                const Expanded(
                                  child: LigoLogo(size: 25, dark: true),
                                ),
                              if (drawer)
                                IconButton(
                                  tooltip: 'Cerrar menú',
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close, size: 20),
                                  color: Colors.white70,
                                )
                              else
                                IconButton(
                                  tooltip: compact
                                      ? 'Expandir menú'
                                      : 'Contraer menú',
                                  onPressed: () =>
                                      setState(() => _collapsed = !_collapsed),
                                  icon: Icon(
                                    compact
                                        ? Icons.menu_open_rounded
                                        : Icons.chevron_left,
                                    size: 22,
                                  ),
                                  color: Colors.white70,
                                ),
                            ],
                          ),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF32323D)),
                Expanded(
                  child: Scrollbar(
                    controller: _menuScroll,
                    thumbVisibility: true,
                    child: ListView(
                      key: const ValueKey('admin-menu-scroll'),
                      controller: _menuScroll,
                      padding: EdgeInsets.fromLTRB(
                        compact ? 10 : 12,
                        8,
                        compact ? 10 : 12,
                        8,
                      ),
                      children: [
                        for (final group in _groups.entries)
                          if (group.value.any(widget.pages.containsKey)) ...[
                            if (!compact)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  12,
                                  0,
                                  8,
                                ),
                                child: Text(
                                  group.key,
                                  style: const TextStyle(
                                    color: Color(0xFF9D9DAC),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              )
                            else if (group.key != 'COMUNIDAD')
                              const Divider(
                                height: 16,
                                color: Color(0xFF32323D),
                              ),
                            for (final key in group.value)
                              if (widget.pages.containsKey(key))
                                _item(
                                  context,
                                  key,
                                  compact: compact,
                                  drawer: drawer,
                                ),
                          ],
                      ],
                    ),
                  ),
                ),
                Container(
                  key: const ValueKey('admin-fixed-footer'),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFF32323D))),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    compact ? 10 : 12,
                    8,
                    compact ? 10 : 12,
                    12,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _item(
                        context,
                        'settings',
                        compact: compact,
                        drawer: drawer,
                      ),
                      const SizedBox(height: 3),
                      Tooltip(
                        message: 'Abrir aplicación',
                        child: Material(
                          color: const Color(0xFF2B2B36),
                          borderRadius: BorderRadius.circular(11),
                          child: InkWell(
                            key: const ValueKey('admin-open-app'),
                            borderRadius: BorderRadius.circular(11),
                            onTap: () {
                              if (drawer) Navigator.pop(context);
                              widget.onDating();
                            },
                            child: SizedBox(
                              height: 44,
                              child: Row(
                                mainAxisAlignment: compact
                                    ? MainAxisAlignment.center
                                    : MainAxisAlignment.start,
                                children: [
                                  if (!compact) const SizedBox(width: 12),
                                  const Icon(
                                    Icons.open_in_new,
                                    size: 19,
                                    color: Colors.white,
                                  ),
                                  if (!compact)
                                    const Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(left: 11),
                                        child: Text(
                                          'Abrir aplicación',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 1050;
      final colors = Theme.of(context).colorScheme;
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        drawer: wide
            ? null
            : Drawer(
                width: (box.maxWidth * .77).clamp(0, 276).toDouble(),
                child: Builder(builder: (ctx) => _sidebar(ctx, drawer: true)),
              ),
        body: SafeArea(
          child: Row(
            children: [
              if (wide)
                AnimatedContainer(
                  key: const ValueKey('admin-sidebar'),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  width: _collapsed ? 76 : 220,
                  child: _sidebar(context),
                ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      color: colors.surface,
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 24 : 8,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          if (!wide)
                            Builder(
                              builder: (ctx) => IconButton(
                                tooltip: 'Menú de administración',
                                icon: const Icon(Icons.menu),
                                onPressed: () => Scaffold.of(ctx).openDrawer(),
                              ),
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.pages[widget.selected]?.$1 ?? 'Cuenta',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                if (wide)
                                  Text(
                                    'Administración de la comunidad',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (!wide) const NotificationBell(),
                          PopupMenuButton<String>(
                            tooltip: 'Cambiar sección',
                            icon: const Icon(
                              Icons.unfold_more_rounded,
                              size: 21,
                            ),
                            initialValue: widget.selected,
                            onSelected: widget.onSelected,
                            itemBuilder: (_) => widget.pages.entries
                                .map(
                                  (e) => PopupMenuItem(
                                    value: e.key,
                                    child: Text(e.value.$1),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.shield_outlined,
                              color: colors.onPrimaryContainer,
                              size: 20,
                            ),
                          ),
                          if (wide) ...[
                            const SizedBox(width: 10),
                            Text(
                              widget.root ? 'Superadmin' : 'Admin',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class AdminUsersView extends StatelessWidget {
  const AdminUsersView({
    super.key,
    required this.client,
    required this.onInspect,
  });
  final VerificationClient client;
  final ValueChanged<String> onInspect;
  @override
  Widget build(BuildContext context) =>
      AdminPeopleView(client: client, onInspect: onInspect);
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.positive = false});
  final String label;
  final bool positive;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: positive ? const Color(0xFF163B35) : const Color(0xFF382445),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: positive ? const Color(0xFF8AE5C4) : const Color(0xFFF2C5FF),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
