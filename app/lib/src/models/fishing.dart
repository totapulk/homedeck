/// One species and how likely it is to bite today, 0–100.
class FishingSpecies {
  const FishingSpecies({
    required this.id,
    required this.name,
    required this.emoji,
    required this.index,
  });

  factory FishingSpecies.fromJson(Map<String, dynamic> json) => FishingSpecies(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    emoji: json['emoji'] as String? ?? '',
    index: (json['index'] as num?)?.round() ?? 0,
  );

  final String id;
  final String name;
  final String emoji;
  final int index;
}

class FishingWeather {
  const FishingWeather({
    required this.windMs,
    required this.pressureHpa,
    required this.pressureTrend,
    required this.cloud,
    required this.waterTempC,
    required this.waterSource,
    this.airTempC,
  });

  factory FishingWeather.fromJson(Map<String, dynamic> json) => FishingWeather(
    airTempC: (json['airTempC'] as num?)?.toDouble(),
    windMs: (json['windMs'] as num?)?.round() ?? 0,
    pressureHpa: (json['pressureHpa'] as num?)?.round() ?? 0,
    pressureTrend: json['pressureTrend'] as String? ?? '',
    cloud: json['cloud'] as String? ?? '',
    waterTempC: (json['waterTempC'] as num?)?.round() ?? 0,
    waterSource: json['waterSource'] as String? ?? '',
  );

  final double? airTempC;
  final int windMs;
  final int pressureHpa;
  final String pressureTrend;
  final String cloud;
  final int waterTempC;

  /// "syke" for a real reading, "estimate" when no station was near enough to ask.
  final String waterSource;

  bool get waterIsMeasured => waterSource == 'syke';
}

class Fishing {
  const Fishing({
    required this.lakeName,
    required this.species,
    required this.isAvailable,
    required this.updatedAt,
    this.best,
    this.comment,
    this.weather,
  });

  factory Fishing.fromJson(Map<String, dynamic> json) {
    final best = json['best'] as Map<String, dynamic>?;
    final weather = json['weather'] as Map<String, dynamic>?;

    return Fishing(
      lakeName: json['lakeName'] as String? ?? 'Lake',
      best: best == null ? null : FishingSpecies.fromJson(best),
      species: [
        for (final entry in (json['species'] as List<dynamic>? ?? const []))
          FishingSpecies.fromJson(entry as Map<String, dynamic>),
      ],
      comment: json['comment'] as String?,
      weather: weather == null ? null : FishingWeather.fromJson(weather),
      isAvailable: json['isAvailable'] as bool? ?? false,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  final String lakeName;
  final FishingSpecies? best;
  final List<FishingSpecies> species;
  final String? comment;
  final FishingWeather? weather;
  final bool isAvailable;
  final DateTime updatedAt;
}
