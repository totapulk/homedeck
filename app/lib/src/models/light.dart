import 'package:flutter/foundation.dart';

@immutable
class Light {
  const Light({
    required this.id,
    required this.name,
    required this.room,
    required this.fixture,
    required this.isOn,
    required this.brightness,
    required this.colorTempK,
    required this.isReachable,
    required this.updatedAt,
  });

  factory Light.fromJson(Map<String, dynamic> json) => Light(
    id: json['id'] as String,
    name: json['name'] as String,
    room: json['room'] as String,
    fixture: json['fixture'] as String?,
    isOn: json['isOn'] as bool,
    brightness: json['brightness'] as int,
    colorTempK: json['colorTempK'] as int?,
    isReachable: json['isReachable'] as bool,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  final String id;
  final String name;
  final String room;

  /// The physical lamp this bulb is part of, when several share one. Null means it is a lamp
  /// in its own right.
  final String? fixture;

  final bool isOn;
  final int brightness;
  final int? colorTempK;
  final bool isReachable;
  final DateTime updatedAt;

  Light copyWith({
    bool? isOn,
    int? brightness,
    int? colorTempK,
    bool? isReachable,
    DateTime? updatedAt,
  }) => Light(
    id: id,
    name: name,
    room: room,
    fixture: fixture,
    isOn: isOn ?? this.isOn,
    brightness: brightness ?? this.brightness,
    colorTempK: colorTempK ?? this.colorTempK,
    isReachable: isReachable ?? this.isReachable,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Light &&
          other.id == id &&
          other.name == name &&
          other.room == room &&
          other.fixture == fixture &&
          other.isOn == isOn &&
          other.brightness == brightness &&
          other.colorTempK == colorTempK &&
          other.isReachable == isReachable &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    room,
    fixture,
    isOn,
    brightness,
    colorTempK,
    isReachable,
    updatedAt,
  );
}
