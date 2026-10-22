/// Models for the bus-driver operate screens: passenger manifest, seat layout
/// and live-trip tracking. Mirror the backend serializers under
/// `/drivers/bus/*`.
library;

import 'bus_driver_models.dart' show BusSchedule;

int _toInt(dynamic v) => int.tryParse('${v ?? 0}') ?? 0;
double _toDouble(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;
String _toStr(dynamic v) => (v ?? '').toString();
List<String> _toStrList(dynamic v) =>
    (v is List) ? v.map((e) => e.toString()).toList() : const [];

/// One booking on the driver's manifest for a schedule/date.
class BusDriverBooking {
  final String id;
  final String bookingCode;
  final String status;
  final String bookingSource; // user | bus_driver | admin
  final String travelDate;
  final String scheduleId;
  final List<String> seatIds;
  final List<String> seatLabels;
  final double amount;
  final String currency;
  final String passengerName;
  final int passengerAge;
  final String passengerGender;
  final String passengerPhone;
  final String notes;

  const BusDriverBooking({
    required this.id,
    required this.bookingCode,
    required this.status,
    required this.bookingSource,
    required this.travelDate,
    required this.scheduleId,
    required this.seatIds,
    required this.seatLabels,
    required this.amount,
    required this.currency,
    required this.passengerName,
    required this.passengerAge,
    required this.passengerGender,
    required this.passengerPhone,
    required this.notes,
  });

  bool get isCounterBooking => bookingSource == 'bus_driver';

  factory BusDriverBooking.fromJson(Map<String, dynamic> j) {
    final p = j['passenger'] is Map ? Map<String, dynamic>.from(j['passenger']) : const {};
    return BusDriverBooking(
      id: _toStr(j['id'] ?? j['_id']),
      bookingCode: _toStr(j['bookingCode']),
      status: _toStr(j['status']),
      bookingSource: _toStr(j['bookingSource']),
      travelDate: _toStr(j['travelDate']),
      scheduleId: _toStr(j['scheduleId']),
      seatIds: _toStrList(j['seatIds']),
      seatLabels: _toStrList(j['seatLabels']),
      amount: _toDouble(j['amount']),
      currency: _toStr(j['currency']).isEmpty ? 'INR' : _toStr(j['currency']),
      passengerName: _toStr(p['name']),
      passengerAge: _toInt(p['age']),
      passengerGender: _toStr(p['gender']),
      passengerPhone: _toStr(p['phone']),
      notes: _toStr(j['notes']),
    );
  }
}

/// A single seat/aisle cell in the driver seat grid.
class BusDriverSeatCell {
  final String kind; // seat | aisle
  final String id;
  final String label;
  final String variant;
  final String status; // available | booked

  const BusDriverSeatCell({
    required this.kind,
    required this.id,
    required this.label,
    required this.variant,
    required this.status,
  });

  bool get isSeat => kind == 'seat';
  bool get isAvailable => status == 'available';
  bool get isSleeper => variant.toLowerCase() == 'sleeper';

  factory BusDriverSeatCell.fromJson(Map<String, dynamic> j) => BusDriverSeatCell(
        kind: _toStr(j['kind']).isEmpty ? 'aisle' : _toStr(j['kind']),
        id: _toStr(j['id']),
        label: _toStr(j['label']),
        variant: _toStr(j['variant']).isEmpty ? 'seat' : _toStr(j['variant']),
        status: _toStr(j['status']).isEmpty ? 'available' : _toStr(j['status']),
      );

  static List<List<BusDriverSeatCell>> deckFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map<List<BusDriverSeatCell>>((row) {
      if (row is! List) return const [];
      return row
          .whereType<Map>()
          .map((e) => BusDriverSeatCell.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }).toList();
  }
}

/// Seat layout for the driver on a schedule/date.
class BusDriverSeatLayout {
  final String scheduleId;
  final String travelDate;
  final int availableSeats;
  final List<List<BusDriverSeatCell>> lowerDeck;
  final List<List<BusDriverSeatCell>> upperDeck;

  const BusDriverSeatLayout({
    required this.scheduleId,
    required this.travelDate,
    required this.availableSeats,
    required this.lowerDeck,
    required this.upperDeck,
  });

  bool get hasUpperDeck => upperDeck.any((r) => r.any((c) => c.isSeat));

  Iterable<BusDriverSeatCell> get allSeats sync* {
    for (final r in lowerDeck) {
      yield* r.where((c) => c.isSeat);
    }
    for (final r in upperDeck) {
      yield* r.where((c) => c.isSeat);
    }
  }

  factory BusDriverSeatLayout.fromJson(Map<String, dynamic> j) {
    final bp = j['blueprint'] is Map ? Map<String, dynamic>.from(j['blueprint']) : const {};
    return BusDriverSeatLayout(
      scheduleId: _toStr(j['scheduleId']),
      travelDate: _toStr(j['travelDate']),
      availableSeats: _toInt(j['availableSeats']),
      lowerDeck: BusDriverSeatCell.deckFrom(bp['lowerDeck']),
      upperDeck: BusDriverSeatCell.deckFrom(bp['upperDeck']),
    );
  }
}

/// Live-trip tracking state from `/drivers/bus/live-trip`.
class BusLiveTrip {
  final String status; // idle | in_progress | paused | completed
  final String scheduleId;
  final String travelDate;
  final double? lat;
  final double? lng;
  final double speedKmph;
  final double totalDistanceKm;
  final DateTime? startedAt;
  final DateTime? lastUpdatedAt;
  final List<BusSchedule> schedules;

  const BusLiveTrip({
    required this.status,
    required this.scheduleId,
    required this.travelDate,
    required this.lat,
    required this.lng,
    required this.speedKmph,
    required this.totalDistanceKm,
    required this.startedAt,
    required this.lastUpdatedAt,
    required this.schedules,
  });

  bool get isRunning => status == 'in_progress';
  bool get isPaused => status == 'paused';
  bool get isIdle => status == 'idle' || status.isEmpty;
  bool get isCompleted => status == 'completed';

  factory BusLiveTrip.fromJson(Map<String, dynamic> j) {
    // The endpoint wraps tracking under `liveTracking` and lists `schedules`.
    final lt = j['liveTracking'] is Map ? Map<String, dynamic>.from(j['liveTracking']) : j;
    final loc = lt['currentLocation'] is Map ? Map<String, dynamic>.from(lt['currentLocation']) : const {};
    return BusLiveTrip(
      status: _toStr(lt['status']).isEmpty ? 'idle' : _toStr(lt['status']),
      scheduleId: _toStr(lt['scheduleId']),
      travelDate: _toStr(lt['travelDate']),
      lat: loc['lat'] != null ? _toDouble(loc['lat']) : null,
      lng: loc['lng'] != null ? _toDouble(loc['lng']) : null,
      speedKmph: _toDouble(loc['speedKmph']),
      totalDistanceKm: _toDouble(lt['totalDistanceKm']),
      startedAt: DateTime.tryParse(_toStr(lt['startedAt'])),
      lastUpdatedAt: DateTime.tryParse(_toStr(lt['lastUpdatedAt'])),
      schedules: BusSchedule.listFrom(j['schedules']),
    );
  }
}
