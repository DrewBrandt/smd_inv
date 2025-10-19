import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:go_router/go_router.dart';
import 'package:smd_inv/pages/boards.dart';
import 'package:smd_inv/pages/boards_editor.dart';
import 'package:smd_inv/pages/inventory.dart';

import 'data/firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await clearFirestoreCache();
  runApp(SmdInvApp());
}

Future clearFirestoreCache() async {
  try {
    await FirebaseFirestore.instance.clearPersistence();
  } catch (_) {}
}

class SmdInvApp extends StatelessWidget {
  const SmdInvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'SMD Inventory',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey, brightness: Brightness.light),
        visualDensity: VisualDensity.compact,
      ),
      
      routerConfig: _router,
    );
  }
}

// ---- Routing ----

enum AppRoute { inventory, boards, admin }

final _router = GoRouter(
  initialLocation: '/inventory',
  routes: [
    GoRoute(path: '/', name: 'root', redirect: (c, s) => '/inventory'),
    GoRoute(path: '/inventory', name: AppRoute.inventory.name, pageBuilder: (c, s) => _page(c, const FullList(), s)),
    GoRoute(path: '/boards', name: AppRoute.boards.name, pageBuilder: (c, s) => _page(c, const BoardsPage(), s)),
    GoRoute(path: '/admin', name: AppRoute.admin.name, pageBuilder: (c, s) => _page(c, const AdminPage(), s)),
    // add to your GoRouter
    GoRoute(path: '/boards/new', name: 'boardNew', pageBuilder: (c, s) => _page(c, BoardEditorPage(), s)),
    GoRoute(
      path: '/boards/:id',
      name: 'boardEdit',
      pageBuilder: (c, s) => _page(c, BoardEditorPage(boardId: s.pathParameters['id']!), s),
    ),
  ],
);

CustomTransitionPage _page(BuildContext context, Widget child, GoRouterState s) {
  return CustomTransitionPage(
    key: s.pageKey,
    child: Scaffold(
      appBar: const PreferredSize(preferredSize: Size.fromHeight(128), child: TopBar()),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.95),
          child: child,
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
      color: scheme.surfaceContainerHighest,
      elevation: 6,

      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.95),
          child: Row(
            children: [
              // Title (left)
              InkWell(
                onTap: () => context.goNamed(AppRoute.inventory.name),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  child: Row(
                    children: [
                      Icon(Icons.widgets_outlined, color: scheme.primary, size: 60),
                      const SizedBox(width: 14),
                      Text(
                        'SMD Inventory',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          color: scheme.onSurface,
                          fontFamily: 'Corbel',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // Tabs (right)
              const _NavTabs(),
              const Spacer(),
              const Text('God I\'m so bored.', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTabs extends StatelessWidget {
  const _NavTabs();

  @override
  Widget build(BuildContext context) {
    // final loc = GoRouterState.of(context).uri.toString();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        _NavTab(label: 'Inventory', route: AppRoute.inventory, match: '/inventory'),
        _NavTab(label: 'Boards', route: AppRoute.boards, match: '/boards'),
        _NavTab(label: 'Admin', route: AppRoute.admin, match: '/admin'),
      ],
    );
  }
}

class _NavTab extends StatelessWidget {
  final String label;
  final AppRoute route;
  final String match;

  const _NavTab({required this.label, required this.route, required this.match});

  bool _isActive(BuildContext context) {
    final uri = GoRouterState.of(context).uri.toString();
    return uri.startsWith(match);
  }

  @override
  Widget build(BuildContext context) {
    final active = _isActive(context);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 20),
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.goNamed(route.name),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: active ? scheme.primary.withAlpha(20) : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
              color: active ? scheme.primaryContainer.withAlpha(180) : Colors.transparent,
            ),
            child: Stack(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? scheme.onPrimaryContainer : scheme.onSurface,
                  ),
                ),
                // underline indicator
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      height: 3,
                      width: active ? 70 : 0,
                      decoration: BoxDecoration(
                        color: active ? scheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget tile(IconData icon, String title, String subtitle, VoidCallback onTap) {
      return Card(
        color: scheme.surfaceContainer,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.all(8),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, size: 28, color: scheme.primary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
        children: [
          SizedBox(height: 24),
          tile(Icons.fact_check_outlined, 'Audit Inventory', 'Count & reconcile stock variances', () {}),
          tile(Icons.history_outlined, 'History & Undo', 'Review changes and revert if needed', () {}),
          tile(Icons.settings_outlined, 'Settings', 'Fields, units, locations, low-stock rules', () {}),
        ],
    );
  }
}
