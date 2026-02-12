import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:smd_inv/pages/boards.dart';
import 'package:smd_inv/pages/boards_editor.dart';
import 'package:smd_inv/pages/admin.dart';
import 'package:smd_inv/pages/inventory.dart';
import 'package:smd_inv/services/auth_service.dart';
import 'package:smd_inv/theme/app_theme.dart';

import 'data/firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(SmdInvApp());
}

class SmdInvApp extends StatelessWidget {
  const SmdInvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeController.mode,
      builder: (context, mode, child) {
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'SMD Inventory',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          routerConfig: _router,
        );
      },
    );
  }
}

// ---- Routing ----

enum AppRoute { inventory, boards, admin }

final _router = GoRouter(
  initialLocation: '/inventory',
  routes: [
    GoRoute(path: '/', name: 'root', redirect: (c, s) => '/inventory'),
    GoRoute(
      path: '/inventory',
      name: AppRoute.inventory.name,
      pageBuilder: (c, s) => _page(c, const FullList(), s),
    ),
    GoRoute(
      path: '/boards',
      name: AppRoute.boards.name,
      pageBuilder: (c, s) => _page(c, const BoardsPage(), s),
    ),
    GoRoute(
      path: '/admin',
      name: AppRoute.admin.name,
      pageBuilder: (c, s) => _page(c, const AdminPage(), s),
    ),
    // add to your GoRouter
    GoRoute(
      path: '/boards/new',
      name: 'boardNew',
      pageBuilder: (c, s) => _page(c, BoardEditorPage(), s),
    ),
    GoRoute(
      path: '/boards/:id',
      name: 'boardEdit',
      pageBuilder:
          (c, s) =>
              _page(c, BoardEditorPage(boardId: s.pathParameters['id']!), s),
    ),
  ],
);

CustomTransitionPage _page(
  BuildContext context,
  Widget child,
  GoRouterState s,
) {
  return CustomTransitionPage(
    key: s.pageKey,
    child: Scaffold(
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(88),
        child: TopBar(),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1600),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: child,
          ),
        ),
      ),
    ),
    transitionsBuilder: (context, animation, secondary, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

// ---- Top bar with title-left, tabs-right ----

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.surfaceContainerHighest.withValues(alpha: 0.98),
              scheme.surfaceContainer.withValues(alpha: 0.98),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1600),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => context.goNamed(AppRoute.inventory.name),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.memory_outlined,
                            color: scheme.primary,
                            size: 28,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'SMD Inventory',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onSurface,
                                ),
                              ),
                              Text(
                                'Inventory + BOM Build Tracking',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  const _NavTabs(),
                  const Spacer(),
                  _AuthActions(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges(),
      initialData: AuthService.currentUser,
      builder: (context, snap) {
        final user = snap.data;
        final canEdit = AuthService.canEdit(user);

        return Row(
          children: [
            IconButton(
              tooltip: 'Toggle Theme',
              onPressed: AppThemeController.toggle,
              icon: Icon(
                AppThemeController.mode.value == ThemeMode.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
              ),
            ),
            if (user == null)
              FilledButton.icon(
                onPressed: () => _signIn(context),
                icon: const Icon(Icons.login),
                label: const Text('Sign In'),
              )
            else ...[
              Tooltip(
                message:
                    canEdit
                        ? 'Editor access enabled'
                        : AuthService.editorPolicySummary(),
                child: Chip(
                  avatar: Icon(
                    canEdit ? Icons.verified_user : Icons.visibility_outlined,
                    size: 16,
                  ),
                  label: Text(canEdit ? 'Editor' : 'Viewer'),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  user.email ?? '(no email)',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _signOut(context),
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('Sign Out'),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _signIn(BuildContext context) async {
    try {
      final cred = await AuthService.signInWithGoogle();
      final email = cred.user?.email ?? '(no email)';
      final canEdit = AuthService.canEdit(cred.user);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            canEdit
                ? 'Signed in: $email (editor)'
                : 'Signed in: $email (view-only)',
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign-in failed: ${e.message ?? e.code}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
    }
  }

  Future<void> _signOut(BuildContext context) async {
    await AuthService.signOut();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Signed out')));
  }
}

class _NavTabs extends StatelessWidget {
  const _NavTabs();

  static const _tabs =
      <({String label, IconData icon, AppRoute route, String match})>[
        (
          label: 'Inventory',
          icon: Icons.inventory_2_outlined,
          route: AppRoute.inventory,
          match: '/inventory',
        ),
        (
          label: 'Boards',
          icon: Icons.dashboard_customize_outlined,
          route: AppRoute.boards,
          match: '/boards',
        ),
        (
          label: 'Admin',
          icon: Icons.settings_outlined,
          route: AppRoute.admin,
          match: '/admin',
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children:
          _tabs
              .map(
                (tab) => _NavTab(
                  label: tab.label,
                  icon: tab.icon,
                  route: tab.route,
                  match: tab.match,
                ),
              )
              .toList(),
    );
  }
}

class _NavTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final AppRoute route;
  final String match;

  const _NavTab({
    required this.label,
    required this.icon,
    required this.route,
    required this.match,
  });

  bool _isActive(BuildContext context) {
    final uri = GoRouterState.of(context).uri.toString();
    return uri.startsWith(match);
  }

  @override
  Widget build(BuildContext context) {
    final active = _isActive(context);
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.goNamed(route.name),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color:
              active
                  ? scheme.primaryContainer.withValues(alpha: 0.9)
                  : Colors.transparent,
          border: Border.all(
            color:
                active
                    ? scheme.primary.withValues(alpha: 0.6)
                    : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color:
                  active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
