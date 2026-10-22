import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bus_ui.dart';
import 'tabs/bus_live_trip_tab.dart';
import 'tabs/bus_manifest_tab.dart';
import 'tabs/bus_profile_tab.dart';
import 'tabs/bus_schedules_tab.dart';

/// The bus-driver operate home: Manifest / Live Trip / Schedules / Profile.
class BusMainShell extends ConsumerStatefulWidget {
  const BusMainShell({super.key});

  @override
  ConsumerState<BusMainShell> createState() => _BusMainShellState();
}

class _BusMainShellState extends ConsumerState<BusMainShell> {
  int _index = 0;

  static const _tabs = [
    BusManifestTab(),
    BusLiveTripTab(),
    BusSchedulesTab(),
    BusProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BusColors.bg,
      body: SafeArea(bottom: false, child: IndexedStack(index: _index, children: _tabs)),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: BusColors.card,
          border: Border(top: BorderSide(color: BusColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            currentIndex: _index,
            onTap: (i) => setState(() => _index = i),
            backgroundColor: Colors.transparent,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: BusColors.teal,
            unselectedItemColor: BusColors.textMuted,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
            unselectedLabelStyle: const TextStyle(fontSize: 11),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.event_seat_rounded), label: 'Manifest'),
              BottomNavigationBarItem(icon: Icon(Icons.my_location_rounded), label: 'Live Trip'),
              BottomNavigationBarItem(icon: Icon(Icons.schedule_rounded), label: 'Schedules'),
              BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
            ],
          ),
        ),
      ),
    );
  }
}
