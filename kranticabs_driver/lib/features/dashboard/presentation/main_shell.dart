import 'package:flutter/material.dart';
import '../../earnings/presentation/earnings_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../ride/presentation/ride_history_screen.dart';
import 'home_screen.dart';

/// Top-level 4-tab shell (Home / Earnings / Trips / Profile) matching the
/// modern design system, keeping screens alive via IndexedStack.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _tabs = [
    HomeScreen(),
    EarningsScreen(),
    RideHistoryScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    const scaffoldBg = Color(0xFF0D1217);
    const navBg = Color(0xFF0D1217);
    const inactiveColor = Color(0xFF8E98A8);
    const goldColor = Color(0xFFFFB800);
    const goldPillBg = Color(0xFF2E2412);

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: navBg,
          border: Border(top: BorderSide(color: Color(0xFF1B232D), width: 1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 10,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  isSelected: _index == 0,
                  activeColor: goldColor,
                  activeBgColor: goldPillBg,
                  inactiveColor: inactiveColor,
                  onTap: () => setState(() => _index = 0),
                ),
                _NavItem(
                  icon: Icons.account_balance_wallet_outlined,
                  selectedIcon: Icons.account_balance_wallet_rounded,
                  label: 'Earnings',
                  isSelected: _index == 1,
                  activeColor: goldColor,
                  activeBgColor: goldPillBg,
                  inactiveColor: inactiveColor,
                  onTap: () => setState(() => _index = 1),
                ),
                _NavItem(
                  icon: Icons.directions_car_outlined,
                  selectedIcon: Icons.directions_car_rounded,
                  label: 'Trips',
                  isSelected: _index == 2,
                  activeColor: goldColor,
                  activeBgColor: goldPillBg,
                  inactiveColor: inactiveColor,
                  onTap: () => setState(() => _index = 2),
                ),
                _NavItem(
                  icon: Icons.person_outline_rounded,
                  selectedIcon: Icons.person_rounded,
                  label: 'Profile',
                  isSelected: _index == 3,
                  activeColor: goldColor,
                  activeBgColor: goldPillBg,
                  inactiveColor: inactiveColor,
                  onTap: () => setState(() => _index = 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final bool isSelected;
  final Color activeColor;
  final Color activeBgColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.activeColor,
    required this.activeBgColor,
    required this.inactiveColor,
    required this.onTap,
    this.selectedIcon,
  });

  @override
  Widget build(BuildContext context) {
    final activeIcon = isSelected ? (selectedIcon ?? icon) : icon;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? activeBgColor : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                activeIcon,
                size: 22,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
