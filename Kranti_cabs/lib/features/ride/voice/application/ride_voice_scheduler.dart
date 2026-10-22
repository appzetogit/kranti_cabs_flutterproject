import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/models/ride_model.dart';
import '../data/ride_voice_config.dart';
import '../data/ride_voice_log.dart';
import '../data/ride_voice_progress_store.dart';
import '../services/ride_eta_service.dart';
import '../services/ride_tts_service.dart';

/// Decides when the rider hears something, and makes sure they hear it once.
///
/// Deliberately not a `Timer(Duration(minutes: 5), ...)`. Android suspends
/// processes, kills them under memory pressure and throttles timers under
/// battery optimisation, so a fired-and-forget timer is the one thing that
/// cannot be trusted here. Instead this re-derives everything on every tick
/// from two durable facts — the ride's own `startedAt` timestamp, and a
/// per-ride record of what has already been spoken — so a trip that was
/// backgrounded, locked or relaunched reaches exactly the same conclusion it
/// would have reached had the app stayed open.
class RideVoiceScheduler with WidgetsBindingObserver {
  final RideVoiceProgressStore progressStore;

  /// Reads the current rider language. A function rather than a stored value so
  /// a language changed mid-trip applies to the next announcement.
  final String Function() readLanguage;

  /// The rider's own on/off switch.
  final bool Function() readEnabled;

  /// Loads the admin config. Called at most once per active trip.
  final Future<RideVoiceConfig> Function() loadConfig;

  /// Re-reads the ride when the tracking screen is not feeding updates, so a
  /// rider who navigated away still gets their announcements.
  final Future<RideModel?> Function(String rideId) refreshRide;

  /// Finds the rider's in-progress trip with no ride id to hand. Used to
  /// re-arm after a cold start: an app killed mid-trip reopens on Home, where
  /// nothing would otherwise tell the scheduler a trip is running.
  final Future<RideModel?> Function() loadActiveRide;

  RideVoiceScheduler({
    required this.progressStore,
    required this.readLanguage,
    required this.readEnabled,
    required this.loadConfig,
    required this.refreshRide,
    required this.loadActiveRide,
  }) {
    WidgetsBinding.instance.addObserver(this);
  }

  /// How often the state machine re-checks. Short enough that the arrival
  /// threshold is not overshot on a fast road, long enough to be invisible on
  /// battery next to the tracking screen's own 3s poll.
  static const Duration _tickInterval = Duration(seconds: 30);

  /// If the tracking screen has not pushed an update in this long, fetch the
  /// ride here instead.
  static const Duration _staleRideAfter = Duration(seconds: 75);

  /// The welcome needs a real ETA to be worth speaking. If none can be had, it
  /// retries on later ticks and then gives up rather than announce a number it
  /// does not have.
  static const int _maxEtaRetries = 10;

  Timer? _ticker;
  String? _rideId;
  RideModel? _ride;
  DateTime? _rideSeenAt;
  RideVoiceConfig? _config;
  Future<void>? _configLoad;
  bool _evaluating = false;
  int _etaRetries = 0;

  /// Feeds the scheduler the trip as the app currently understands it.
  ///
  /// Safe to call on every ride update — it is cheap, idempotent, and starts or
  /// stops itself as the trip's status changes.
  void onRideUpdate(RideModel? ride) {
    if (ride == null) return;

    if (ride.isCompleted || ride.isCancelled) {
      _finish(ride.rideId, reason: ride.isCancelled ? 'cancelled' : 'completed');
      return;
    }

    if (!_hasStarted(ride)) {
      // Accepted or driver-arrived, but the trip is not running yet. Nothing to
      // schedule: the clock starts at RIDE_STARTED, not before.
      return;
    }

    if (_rideId != ride.rideId) {
      // A new trip always begins from a clean slate, so the second ride of the
      // day announces itself exactly like the first.
      _resetFor(ride.rideId);
    }

    _ride = ride;
    _rideSeenAt = DateTime.now();
    _ensureTicking();
    unawaited(_evaluate());
  }

  /// Picks up a trip that was already running — after a cold start, or when
  /// the app returns to the foreground with no trip currently armed.
  ///
  /// Because every decision is re-derived from `startedAt` and the stored
  /// progress, a trip resumed here reaches the same conclusion it would have
  /// reached had the app never been killed: a welcome already spoken stays
  /// spoken, and one that came due while the process was gone is spoken now.
  Future<void> resumeActiveRide() async {
    if (_rideId != null) return;
    if (!readEnabled()) return;

    try {
      final ride = await loadActiveRide();
      if (ride == null) return;
      rideVoiceLog('Picked up a trip already in progress');
      onRideUpdate(ride);
    } catch (error) {
      rideVoiceLog('Could not look for a trip in progress ($error)');
    }
  }

  /// Called when a trip ends for any reason — including from outside the ride
  /// update stream, e.g. the rider cancelling from the home screen.
  void stopFor(String rideId, {String reason = 'ended'}) => _finish(rideId, reason: reason);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    if (_rideId == null) {
      // Nothing armed — the process may have been killed and rebuilt while a
      // trip was still running.
      unawaited(resumeActiveRide());
      return;
    }

    // Coming back from background is exactly the case a plain timer gets wrong:
    // the threshold may well have passed while the process was suspended.
    rideVoiceLog('App resumed during a trip, re-checking announcements');
    unawaited(_evaluate());
  }

  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  // ---------------------------------------------------------------- internals

  bool _hasStarted(RideModel ride) {
    if (ride.startedAt != null) return true;
    final status = ride.status.toLowerCase();
    final live = ride.liveStatus.toLowerCase();
    return status == 'started' ||
        status == 'ongoing' ||
        live == 'started' ||
        live == 'ongoing';
  }

  void _resetFor(String rideId) {
    rideVoiceLog('Ride started, voice scheduler armed');
    _ticker?.cancel();
    _ticker = null;
    _rideId = rideId;
    _ride = null;
    _config = null;
    _configLoad = null;
    _etaRetries = 0;
  }

  void _finish(String rideId, {required String reason}) {
    if (_rideId != rideId) return;
    rideVoiceLog('Ride $reason, voice scheduler stopped');

    _ticker?.cancel();
    _ticker = null;
    _rideId = null;
    _ride = null;
    _rideSeenAt = null;
    _config = null;
    _configLoad = null;
    _etaRetries = 0;

    // A trip that ends mid-sentence should not keep talking about arriving
    // somewhere the rider has already left.
    unawaited(RideTtsService.instance.stop());
    progressStore.clear(rideId);
  }

  void _ensureTicking() {
    if (_ticker != null) return;
    _ticker = Timer.periodic(_tickInterval, (_) => unawaited(_evaluate()));
  }

  Future<void> _evaluate() async {
    // Overlapping evaluations would double-speak: two ticks could both read
    // "not played yet" while the first is still waiting on the ETA call.
    if (_evaluating) return;
    final rideId = _rideId;
    if (rideId == null) return;

    _evaluating = true;
    try {
      await _evaluateInner(rideId);
    } catch (error) {
      // Nothing in here may surface to the trip. Announcements are an
      // enhancement; tracking, navigation and payment carry on regardless.
      rideVoiceLog('Announcement check failed, ride unaffected ($error)');
    } finally {
      _evaluating = false;
    }
  }

  Future<void> _evaluateInner(String rideId) async {
    if (!readEnabled()) return;

    var ride = _ride;
    final seenAt = _rideSeenAt;
    if (ride == null || seenAt == null || DateTime.now().difference(seenAt) > _staleRideAfter) {
      final refreshed = await refreshRide(rideId);
      if (refreshed == null) return;
      if (refreshed.isCompleted || refreshed.isCancelled) {
        _finish(rideId, reason: refreshed.isCancelled ? 'cancelled' : 'completed');
        return;
      }
      ride = refreshed;
      _ride = refreshed;
      _rideSeenAt = DateTime.now();
    }

    if (_rideId != rideId) return; // finished while we were awaiting

    final config = await _configFor();
    if (config == null || !config.hasAnythingToSay) return;

    var progress = progressStore.read(rideId);
    final elapsed = _elapsedMinutes(ride);
    final welcomeDue = config.welcome.enabled &&
        !progress.welcomePlayed &&
        elapsed >= config.welcome.triggerMinutes;
    final comfortDue = config.comfort.enabled &&
        !progress.comfortPlayed &&
        elapsed >= config.comfort.triggerMinutes;
    final arrivalPending = config.arrival.enabled && !progress.arrivalPlayed;

    if (!welcomeDue && !comfortDue && !arrivalPending) {
      if (progress.welcomePlayed && progress.comfortPlayed && progress.arrivalPlayed) {
        // Everything this trip had to say has been said. Stop ticking rather
        // than keep a timer and an ETA lookup alive for the rest of the trip.
        rideVoiceLog('All announcements played, scheduler idle');
        _ticker?.cancel();
        _ticker = null;
      }
      return;
    }

    final remaining = await RideEtaService.remainingMinutes(ride);
    if (_rideId != rideId) return;

    if (remaining == null && comfortDue && !welcomeDue) {
      // The comfort line carries no {minutes}, so a missing ETA is no reason to
      // hold it back — unlike the welcome, which would be meaningless without
      // one.
      final spoken = await _announce(
        rideId: rideId,
        announcement: config.comfort,
        config: config,
        minutes: 0,
        label: 'Comfort',
      );
      if (spoken) {
        progress = progress.copyWith(comfortPlayed: true);
        progressStore.write(rideId, progress);
      }
      return;
    }

    if (remaining == null) {
      _etaRetries++;
      rideVoiceLog('ETA unavailable (attempt $_etaRetries), nothing announced this tick');
      if (_etaRetries >= _maxEtaRetries && welcomeDue) {
        // Long past due and still no estimate — skip the welcome outright
        // rather than greet someone twenty minutes into their trip.
        rideVoiceLog('Giving up on the welcome announcement, no ETA available');
        progress = progress.copyWith(welcomePlayed: true);
        progressStore.write(rideId, progress);
      }
      return;
    }

    _etaRetries = 0;
    final minutes = remaining.round().clamp(1, 999);
    rideVoiceLog('Current ETA: $minutes minutes');

    if (welcomeDue) {
      final spoken = await _announce(
        rideId: rideId,
        announcement: config.welcome,
        config: config,
        minutes: minutes,
        label: 'Welcome',
      );
      if (spoken) {
        progress = progress.copyWith(welcomePlayed: true);
        progressStore.write(rideId, progress);
      }
      if (_rideId != rideId) return;
    }

    if (comfortDue) {
      final spoken = await _announce(
        rideId: rideId,
        announcement: config.comfort,
        config: config,
        minutes: minutes,
        label: 'Comfort',
      );
      if (spoken) {
        progress = progress.copyWith(comfortPlayed: true);
        progressStore.write(rideId, progress);
      }
      if (_rideId != rideId) return;
    }

    if (arrivalPending && remaining <= config.arrival.triggerMinutes) {
      rideVoiceLog('Arrival threshold reached');
      final spoken = await _announce(
        rideId: rideId,
        announcement: config.arrival,
        config: config,
        // Reads the configured threshold, not the raw estimate: "arriving in 10
        // minutes" is the approved wording, and "arriving in 9 minutes" from a
        // fractionally-late tick is a worse sentence, not a more honest one.
        minutes: config.arrival.triggerMinutes.round(),
        label: 'Arrival',
      );
      if (spoken) {
        progress = progress.copyWith(arrivalPlayed: true);
        progressStore.write(rideId, progress);
      }
    }
  }

  double _elapsedMinutes(RideModel ride) {
    final startedAt = ride.startedAt;
    if (startedAt == null) return 0;
    return DateTime.now().difference(startedAt).inSeconds / 60;
  }

  Future<bool> _announce({
    required String rideId,
    required RideVoiceAnnouncement announcement,
    required RideVoiceConfig config,
    required int minutes,
    required String label,
  }) async {
    final language = readLanguage();
    final template = announcement.templateFor(language, config.fallbackLanguage);
    if (template == null || template.trim().isEmpty) {
      rideVoiceLog('$label announcement has no text for "$language", skipped');
      // Marked as handled by the caller so it is not retried every 30s for a
      // language nobody has written yet.
      return true;
    }

    final spokenLanguage = announcement.resolvedLanguageFor(language, config.fallbackLanguage);
    rideVoiceLog('User language: $language, speaking: $spokenLanguage');
    rideVoiceLog('Generating $label message');

    final text = renderVoiceTemplate(template, {'minutes': '$minutes'});

    final ok = await RideTtsService.instance.speak(
      text: text,
      languageCode: spokenLanguage,
      speech: config.speech,
    );

    if (_rideId != rideId) return false; // trip ended while it was being read

    rideVoiceLog(ok ? '$label announcement played' : '$label announcement could not be spoken');

    // A TTS failure still counts as handled. Retrying a broken engine every 30
    // seconds for the rest of the trip helps nobody and drains the battery.
    return true;
  }

  Future<RideVoiceConfig?> _configFor() async {
    final cached = _config;
    if (cached != null) return cached;

    final inFlight = _configLoad;
    if (inFlight != null) {
      await inFlight;
      return _config;
    }

    final future = loadConfig().then((config) {
      _config = config;
    }).catchError((Object error) {
      rideVoiceLog('Voice config could not be loaded ($error)');
      _config = RideVoiceConfig.silent;
    });

    _configLoad = future;
    await future;
    return _config;
  }
}
