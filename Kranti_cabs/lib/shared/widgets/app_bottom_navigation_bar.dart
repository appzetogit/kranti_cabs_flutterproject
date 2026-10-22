import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppBottomNavigationBar extends StatelessWidget {
  final int currentIndex;

  const AppBottomNavigationBar({
    super.key,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    const navBgColor = Color(0xFF11191D);
    const activeColor = Color(0xFFF5B400);
    const inactiveColor = Color(0xFF94A3B8);

    return Container(
      color: navBgColor,
      child: SafeArea(
        top: false,
        child: Container(
          height: 68,
          decoration: const BoxDecoration(
            color: navBgColor,
            border: Border(top: BorderSide(color: Color(0xFF2E2E2E), width: 1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // 1. Home
              _BottomNavItem(
                icon: currentIndex == 0 ? Icons.home_rounded : Icons.home_outlined,
                label: 'Home',
                isActive: currentIndex == 0,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () {
                  if (currentIndex != 0) context.go('/home');
                },
              ),

              // 2. All Services
              _BottomNavItem(
                icon: Icons.grid_view_rounded,
                label: 'All Services',
                isActive: currentIndex == 1,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () {
                  if (currentIndex != 1) context.go('/home/all-services');
                },
              ),

              // 3. Center ZICAB Floating Emblem Image Button
              GestureDetector(
                onTap: () => context.push('/search'),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: activeColor,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x40F5B400),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Image.asset(
                        'assets/logo.webp',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => const Center(
                          child: Text(
                            'Kranti',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0A0A0A),
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 4. History
              _BottomNavItem(
                icon: currentIndex == 2 ? Icons.access_time_rounded : Icons.access_time_outlined,
                label: 'History',
                isActive: currentIndex == 2,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () {
                  if (currentIndex != 2) context.go('/rides');
                },
              ),

              // 5. Profile
              _BottomNavItem(
                icon: currentIndex == 3 ? Icons.person_rounded : Icons.person_outline_rounded,
                label: 'Profile',
                isActive: currentIndex == 3,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () {
                  if (currentIndex != 3) context.go('/profile');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? activeColor : inactiveColor;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
            if (isActive) ...[
              const SizedBox(height: 2),
              Container(
                width: 18,
                height: 2,
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ] else ...[
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }
}
