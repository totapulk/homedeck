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
    this.isReachable = true,
    this.raw,
    this.problem,
  });

  factory Vacuum.fromJson(Map<String, dynamic> json) => Vacuum(
    name: json['name'] as String,
    activity: VacuumActivity.parse(json['activity'] as String?),
    batteryPercent: json['batteryPercent'] as int?,
    isSimulated: json['isSimulated'] as bool? ?? false,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    isReachable: json['isReachable'] as bool? ?? true,
    raw: json['raw'] as String?,
    problem: json['problem'] as String?,
  );

  final String name;
  final VacuumActivity activity;
  final int? batteryPercent;

  /// Whether the backend is talking to a real machine. The card says so when it is not.
  final bool isSimulated;

  final DateTime updatedAt;

  /// False when the sidecar could not be reached at all. Distinct from a robot that answered
  /// and had nothing to say, which looks identical without this.
  final bool isReachable;

  /// The vendor's own state name, e.g. `CHARGING_COMPLETED`. Shown as the fine print, because
  /// it says more than five activities ever could.
  final String? raw;

  /// What went wrong, in the sidecar's words.
  final String? problem;

  @override
  bool operator ==(Object other) =>
      other is Vacuum &&
      other.name == name &&
      other.activity == activity &&
      other.batteryPercent == batteryPercent &&
      other.isSimulated == isSimulated &&
      other.updatedAt == updatedAt &&
      other.isReachable == isReachable &&
      other.raw == raw &&
      other.problem == problem;

  @override
  int get hashCode => Object.hash(
    name,
    activity,
    batteryPercent,
    isSimulated,
    updatedAt,
    isReachable,
    raw,
    problem,
  );
}
