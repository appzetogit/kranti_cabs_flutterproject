import 'dart:developer' as developer;

/// One announcement's wording and trigger, as configured in the admin panel.
class RideVoiceAnnouncement {
  final bool enabled;

  /// Welcome: minutes after the trip starts. Arrival: the remaining-time
  /// threshold. Which one it means is the caller's business — the shape is the
  /// same, so both are modelled once.
  final double triggerMinutes;

  /// Language code -> template. Free-form on purpose: a language added in the
  /// panel arrives here without an app release.
  final Map<String, String> messages;

  const RideVoiceAnnouncement({
    required this.enabled,
    required this.triggerMinutes,
    required this.messages,
  });

  static const disabled = RideVoiceAnnouncement(
    enabled: false,
    triggerMinutes: 0,
    messages: {},
  );

  factory RideVoiceAnnouncement.fromJson(
    Map<String, dynamic> json, {
    required String triggerKey,
    required double defaultTrigger,
  }) {
    final rawMessages = json['messages'];
    final messages = <String, String>{};
    if (rawMessages is Map) {
      rawMessages.forEach((key, value) {
        final code = key.toString().trim().toLowerCase();
        final text = value?.toString().trim() ?? '';
        if (code.isNotEmpty && text.isNotEmpty) messages[code] = text;
      });
    }

    return RideVoiceAnnouncement(
      enabled: _asBool(json['enabled'], true),
      triggerMinutes: _asDouble(json[triggerKey], defaultTrigger),
      messages: messages,
    );
  }

  Map<String, dynamic> toJson(String triggerKey) => {
        'enabled': enabled,
        triggerKey: triggerMinutes,
        'messages': messages,
      };

  /// The template for [languageCode], falling back to [fallbackLanguage] and
  /// then to whatever is configured, so a rider who picked a language nobody
  /// has translated yet still hears the announcement instead of silence.
  String? templateFor(String languageCode, String fallbackLanguage) {
    final direct = messages[languageCode.toLowerCase()];
    if (direct != null && direct.isNotEmpty) return direct;

    final fallback = messages[fallbackLanguage.toLowerCase()];
    if (fallback != null && fallback.isNotEmpty) return fallback;

    return messages.isNotEmpty ? messages.values.first : null;
  }

  /// The language actually spoken for [languageCode] — needed so the TTS voice
  /// matches the text when a fallback kicked in. Speaking Hindi text with an
  /// English voice is worse than not speaking at all.
  String resolvedLanguageFor(String languageCode, String fallbackLanguage) {
    final wanted = languageCode.toLowerCase();
    if ((messages[wanted] ?? '').isNotEmpty) return wanted;

    final fallback = fallbackLanguage.toLowerCase();
    if ((messages[fallback] ?? '').isNotEmpty) return fallback;

    return messages.keys.isNotEmpty ? messages.keys.first : fallback;
  }
}

/// How loud, fast and high the phone reads the announcement.
class RideVoiceSpeech {
  final double rate;
  final double pitch;
  final double volume;

  const RideVoiceSpeech({
    this.rate = 0.5,
    this.pitch = 1.0,
    this.volume = 1.0,
  });

  factory RideVoiceSpeech.fromJson(Map<String, dynamic> json) {
    return RideVoiceSpeech(
      rate: _asDouble(json['rate'], 0.5).clamp(0.1, 1.0),
      pitch: _asDouble(json['pitch'], 1.0).clamp(0.5, 2.0),
      volume: _asDouble(json['volume'], 1.0).clamp(0.0, 1.0),
    );
  }

  Map<String, dynamic> toJson() => {'rate': rate, 'pitch': pitch, 'volume': volume};
}

/// The whole voice-announcement configuration, as served by
/// `GET /users/settings/ride-voice`.
class RideVoiceConfig {
  final bool enabled;
  final String fallbackLanguage;
  final RideVoiceAnnouncement welcome;

  /// The cabin-comfort ("the air conditioning is on") line. Time-based from the
  /// trip start, exactly like [welcome] — the app cannot know whether the AC is
  /// really running, so this is worded as an offer to adjust it.
  final RideVoiceAnnouncement comfort;
  final RideVoiceAnnouncement arrival;
  final RideVoiceSpeech speech;

  const RideVoiceConfig({
    required this.enabled,
    required this.fallbackLanguage,
    required this.welcome,
    required this.comfort,
    required this.arrival,
    required this.speech,
  });

  /// Used when there is no config and none was ever cached. Silent rather than
  /// guessing at wording: the templates are approved copy that belongs on the
  /// server, not baked into the app.
  static const silent = RideVoiceConfig(
    enabled: false,
    fallbackLanguage: 'en',
    welcome: RideVoiceAnnouncement.disabled,
    comfort: RideVoiceAnnouncement.disabled,
    arrival: RideVoiceAnnouncement.disabled,
    speech: RideVoiceSpeech(),
  );

  factory RideVoiceConfig.fromJson(Map<String, dynamic> json) {
    // The backend answers `{ settings: {...} }` for every settings category,
    // but the cached copy is stored unwrapped — accept either.
    final root = json['settings'] is Map
        ? Map<String, dynamic>.from(json['settings'] as Map)
        : json;

    Map<String, dynamic> section(String key) =>
        root[key] is Map ? Map<String, dynamic>.from(root[key] as Map) : <String, dynamic>{};

    return RideVoiceConfig(
      enabled: _asBool(root['enabled'], false),
      fallbackLanguage:
          (root['fallback_language']?.toString().trim().toLowerCase().isNotEmpty ?? false)
              ? root['fallback_language'].toString().trim().toLowerCase()
              : 'en',
      welcome: RideVoiceAnnouncement.fromJson(
        section('welcome'),
        triggerKey: 'delay_minutes',
        defaultTrigger: 5,
      ),
      comfort: RideVoiceAnnouncement.fromJson(
        section('comfort'),
        triggerKey: 'delay_minutes',
        defaultTrigger: 10,
      ),
      arrival: RideVoiceAnnouncement.fromJson(
        section('arrival'),
        triggerKey: 'trigger_remaining_minutes',
        defaultTrigger: 10,
      ),
      speech: RideVoiceSpeech.fromJson(section('speech')),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'fallback_language': fallbackLanguage,
        'welcome': welcome.toJson('delay_minutes'),
        'comfort': comfort.toJson('delay_minutes'),
        'arrival': arrival.toJson('trigger_remaining_minutes'),
        'speech': speech.toJson(),
      };

  bool get hasAnythingToSay =>
      enabled &&
      ((welcome.enabled && welcome.messages.isNotEmpty) ||
          (comfort.enabled && comfort.messages.isNotEmpty) ||
          (arrival.enabled && arrival.messages.isNotEmpty));
}

/// Fills `{placeholders}` in an admin-authored template.
///
/// Unknown placeholders are left untouched rather than blanked, so a variable
/// added in the panel before the app understands it reads as an obvious
/// mistake in testing instead of silently swallowing a word.
String renderVoiceTemplate(String template, Map<String, String> variables) {
  var output = template;
  variables.forEach((key, value) {
    output = output.replaceAll('{$key}', value);
  });

  final leftover = RegExp(r'\{[a-zA-Z_]+\}').firstMatch(output);
  if (leftover != null) {
    developer.log(
      '[RideVoice] Template still has an unresolved variable: ${leftover.group(0)}',
      name: 'RideVoice',
    );
  }

  return output;
}

bool _asBool(dynamic value, bool fallback) {
  if (value == null) return fallback;
  if (value is bool) return value;
  final text = value.toString().trim().toLowerCase();
  if (text.isEmpty) return fallback;
  return !['0', 'false', 'no', 'off'].contains(text);
}

double _asDouble(dynamic value, double fallback) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? fallback;
}
