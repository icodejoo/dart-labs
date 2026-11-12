import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';
import 'package:json_annotation_lenient/json_annotation_lenient.dart';

part 'main.g.dart';

/// A model whose fields tolerate loose JSON (strings for numbers, 0/1 for bools, missing keys).
@LenientConverter()
@JsonSerializable()
class User {
  /// Creates a user.
  User({
    required this.id,
    required this.score,
    required this.active,
    required this.name,
  });

  /// Builds a user from loose JSON.
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  /// Numeric id; accepts `"42"` or `42.0`.
  final int id;

  /// Score; accepts a numeric string.
  final double score;

  /// Active flag; accepts `1`, `"true"`, etc.
  final bool active;

  /// Name; a missing key falls back to an empty string.
  final String name;

  /// Serializes this user.
  Map<String, dynamic> toJson() => _$UserToJson(this);
}

void main() {
  final user = User.fromJson(
    jsonDecode('{"id": "42", "score": "9.5", "active": 1}')
        as Map<String, dynamic>,
  );
  print('${user.id} ${user.score} ${user.active} "${user.name}"');
  print(jsonEncode(user));
}
