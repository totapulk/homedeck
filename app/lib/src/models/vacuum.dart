import 'package:flutter/foundation.dart';

/// What the robot is doing.
enum VacuumActivity {
  unknown,
  docked,
  cleaning,
  returning,
  error;

  /// Falls back to [unknown] so an older app stays usable against a newer backend.
  static VacuumActivity parse(String? value) => VacuumActivity.values.firstWhere(
    (activity) => activity.name.toLowerCase() == value?.toLowerCase(),
    orElse: () => VacuumActivity.unknown,
  );

  bool get isOut => this == cleaning || this == returning;
}

@immutable
class Vacuum {
  const Vacuum({
    required this.name,
    required this.activity,
    required this.batteryPercent,
    required this.isSimulated,
    required this.updatedAt,
  });

  factory Vacuum.fromJson(Map<String, dynamic> json) => Vacuum(
    name: json['name'] as String,
    activity: VacuumActivity.parse(json['activity'] as String?),
    batteryPercent: json['batteryPercent'] as int?,
    isSimulated: json['isSimulated'] as bool? ?? false,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  final String name;
  final VacuumActivity activity;
  final int? batteryPercent;

  /// Whether the backend is talking to a real machine. The card says so when it is not.
  final bool isSimulated;

  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      other is Vacuum &&
      other.name == name &&
      other.activity == activity &&
      other.batteryPercent == batteryPercent &&
      other.isSimulated == isSimulated &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      Object.hash(name, activity, batteryPercent, isSimulated, updatedAt);
}
