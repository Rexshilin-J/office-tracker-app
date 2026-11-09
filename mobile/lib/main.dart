import 'package:flutter/material.dart';

import 'core/session.dart';
import 'features/admin/admin_home.dart';
import 'features/auth/login_screen.dart';
import 'features/employee/employee_home.dart';

void main() {
  runApp(const OfficeTrackerApp());
}

class OfficeTrackerApp extends StatefulWidget {
  const OfficeTrackerApp({super.key});

  @override
  State<OfficeTrackerApp> createState() => _OfficeTrackerAppState();
}

class _OfficeTrackerAppState extends State<OfficeTrackerApp> {
  final Session session = Session();

  @override
  void initState() {
    super.initState();
    session.restore();
  }

  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OfficeTracker',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          if (session.restoring) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (!session.loggedIn) return LoginScreen(session: session);
          // Employees get the simple app; Super Admin, HR and Manager get the
          // management app whose tabs depend on what they are allowed to do.
          return session.isEmployee
              ? EmployeeHome(session: session)
              : AdminHome(session: session);
        },
      ),
    );
  }
}

ThemeData _buildTheme() {
  const seed = Color(0xFF4F46E5);
  final scheme = ColorScheme.fromSeed(seedColor: seed);
  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: Colors.grey.shade300),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF3F4FF),
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFFF3F4FF),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      height: 68,
      indicatorColor: scheme.primary.withValues(alpha: 0.14),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: Colors.grey.shade300),
      showCheckmark: false,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    ),
  );
}
