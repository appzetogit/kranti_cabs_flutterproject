import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxiuser/shared/widgets/sheet_drag_area.dart';

/// The ride screen's vehicle sheet: a DraggableScrollableSheet (0.62 start,
/// 0.38-0.88) whose parent rebuilds on every extent change, a handle and
/// route header above an Expanded list that owns the sheet's scroll
/// controller, and a fixed Book bar below.
///
/// Only the list used to move the sheet; dragging the handle or header did
/// nothing. They are wrapped in [SheetDragArea] now, as on the screen.
class _Sheet extends StatefulWidget {
  const _Sheet({required this.onExtent, required this.onEditTap});
  final ValueChanged<double> onExtent;
  final VoidCallback onEditTap;
  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  final controller = DraggableScrollableController();
  double extent = 0.62;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        const Positioned.fill(child: ColoredBox(color: Colors.grey)),
        NotificationListener<DraggableScrollableNotification>(
          onNotification: (n) {
            if ((n.extent - extent).abs() > 0.02) setState(() => extent = n.extent);
            widget.onExtent(n.extent);
            return false;
          },
          child: DraggableScrollableSheet(
            controller: controller,
            initialChildSize: 0.62,
            minChildSize: 0.38,
            maxChildSize: 0.88,
            builder: (context, scrollController) => ColoredBox(
              color: Colors.black,
              child: Column(children: [
                SheetDragArea(
                  controller: controller,
                  minExtent: 0.38,
                  maxExtent: 0.88,
                  restExtent: 0.62,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(key: Key('handle'), height: 22, width: double.infinity),
                    SizedBox(
                      key: const Key('header'),
                      height: 170,
                      width: double.infinity,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: TextButton(onPressed: widget.onEditTap, child: const Text('Edit')),
                      ),
                    ),
                  ]),
                ),
                Expanded(
                  child: ListView.separated(
                    key: const Key('list'),
                    controller: scrollController,
                    itemCount: 5,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => SizedBox(height: 90, child: Text('vehicle $i')),
                  ),
                ),
                const SizedBox(height: 150, width: double.infinity),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

void main() {
  late double extent;
  late int edits;

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    extent = 0.62;
    edits = 0;
    await tester.pumpWidget(MaterialApp(home: _Sheet(onExtent: (e) => extent = e, onEditTap: () => edits++)));
  }

  testWidgets('dragging the handle up opens the sheet', (tester) async {
    await open(tester);
    await tester.timedDrag(find.byKey(const Key('handle')), const Offset(0, -150), const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(extent, greaterThan(0.7));
  });

  testWidgets('dragging the route header down lowers the sheet', (tester) async {
    await open(tester);
    await tester.timedDrag(find.byKey(const Key('header')), const Offset(0, 100), const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(extent, lessThan(0.6));
    expect(extent, greaterThanOrEqualTo(0.38));
  });

  testWidgets('a flick up on the handle opens it fully', (tester) async {
    await open(tester);
    await tester.fling(find.byKey(const Key('handle')), const Offset(0, -60), 2000);
    await tester.pumpAndSettle();
    expect(extent, closeTo(0.88, 0.01));
  });

  testWidgets('a flick down from fully open returns it to its resting height', (tester) async {
    await open(tester);
    await tester.fling(find.byKey(const Key('handle')), const Offset(0, -60), 2000);
    await tester.pumpAndSettle();
    await tester.fling(find.byKey(const Key('handle')), const Offset(0, 60), 2000);
    await tester.pumpAndSettle();
    expect(extent, closeTo(0.62, 0.01));
  });

  testWidgets('the vehicle list still slides the sheet', (tester) async {
    await open(tester);
    await tester.drag(find.byKey(const Key('list')), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(extent, greaterThan(0.8));
  });

  testWidgets('taps in the header still work', (tester) async {
    await open(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(edits, 1);
    expect(extent, closeTo(0.62, 0.001));
  });
}
