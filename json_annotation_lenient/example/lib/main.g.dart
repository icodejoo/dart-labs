// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'main.dart';

// **************************************************************************
// _LenientAwareGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => User(
  id: const LenientIntConverter().fromJson(json['id']),
  score: const LenientDoubleConverter().fromJson(json['score']),
  active: const LenientBoolConverter().fromJson(json['active']),
  name: const LenientStringConverter().fromJson(json['name']),
);

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
  'id': instance.id,
  'score': instance.score,
  'active': instance.active,
  'name': instance.name,
};
