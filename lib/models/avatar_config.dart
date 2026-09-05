import 'dart:convert';

import 'package:flutter/foundation.dart';

enum AvatarGender { male, female }

class AvatarOption {
  const AvatarOption(this.id, this.label);

  final String id;
  final String label;
}

class AvatarCatalog {
  AvatarCatalog._();

  static const List<int> skinTones = [
    0xFFFFE0BD,
    0xFFF1C27D,
    0xFFE0AC69,
    0xFFC68642,
    0xFF8D5524,
  ];

  static const List<int> palette = [
    0xFFEF5350,
    0xFFFF8A65,
    0xFFFFCA28,
    0xFF66BB6A,
    0xFF26A69A,
    0xFF42A5F5,
    0xFF5C6BC0,
    0xFFAB47BC,
    0xFFEC407A,
    0xFF8D6E63,
    0xFF78909C,
    0xFF263238,
    0xFFFFFFFF,
  ];

  static const List<AvatarOption> hair = [
    AvatarOption('bald', 'Bald'),
    AvatarOption('short', 'Short'),
    AvatarOption('medium', 'Medium'),
    AvatarOption('long', 'Long'),
    AvatarOption('curly', 'Curly'),
    AvatarOption('bun', 'Bun'),
  ];

  static const List<AvatarOption> expressions = [
    AvatarOption('happy', 'Happy'),
    AvatarOption('neutral', 'Neutral'),
    AvatarOption('wink', 'Wink'),
    AvatarOption('cool', 'Cool'),
    AvatarOption('surprised', 'Surprised'),
  ];

  static const List<AvatarOption> hats = [
    AvatarOption('none', 'None'),
    AvatarOption('cap', 'Cap'),
    AvatarOption('beanie', 'Beanie'),
    AvatarOption('sunhat', 'Sun Hat'),
    AvatarOption('headband', 'Headband'),
    AvatarOption('cowboy', 'Cowboy'),
  ];

  static const List<AvatarOption> tops = [
    AvatarOption('tshirt', 'T-Shirt'),
    AvatarOption('tank', 'Tank Top'),
    AvatarOption('hoodie', 'Hoodie'),
    AvatarOption('jacket', 'Jacket'),
    AvatarOption('dress', 'Dress'),
  ];

  static const List<AvatarOption> bottoms = [
    AvatarOption('jeans', 'Jeans'),
    AvatarOption('shorts', 'Shorts'),
    AvatarOption('skirt', 'Skirt'),
    AvatarOption('cargo', 'Cargo'),
  ];

  static const List<AvatarOption> socks = [
    AvatarOption('none', 'None'),
    AvatarOption('ankle', 'Ankle'),
    AvatarOption('high', 'Knee-High'),
    AvatarOption('striped', 'Striped'),
  ];

  static const List<AvatarOption> shoes = [
    AvatarOption('sneakers', 'Sneakers'),
    AvatarOption('boots', 'Boots'),
    AvatarOption('sandals', 'Sandals'),
    AvatarOption('flats', 'Flats'),
  ];

  static const List<AvatarOption> accessories = [
    AvatarOption('glasses', 'Glasses'),
    AvatarOption('sunglasses', 'Sunglasses'),
    AvatarOption('earrings', 'Earrings'),
    AvatarOption('backpack', 'Backpack'),
    AvatarOption('scarf', 'Scarf'),
    AvatarOption('watch', 'Watch'),
  ];
}

@immutable
class AvatarConfig {
  const AvatarConfig({
    this.gender = AvatarGender.male,
    this.skinTone = 0xFFF1C27D,
    this.hairStyle = 'short',
    this.hairColor = 0xFF263238,
    this.expression = 'happy',
    this.hat = 'none',
    this.hatColor = 0xFF42A5F5,
    this.top = 'tshirt',
    this.topColor = 0xFF42A5F5,
    this.bottom = 'jeans',
    this.bottomColor = 0xFF5C6BC0,
    this.socks = 'ankle',
    this.socksColor = 0xFFFFFFFF,
    this.shoes = 'sneakers',
    this.shoesColor = 0xFF263238,
    this.accessories = const {},
  });

  final AvatarGender gender;
  final int skinTone;
  final String hairStyle;
  final int hairColor;
  final String expression;
  final String hat;
  final int hatColor;
  final String top;
  final int topColor;
  final String bottom;
  final int bottomColor;
  final String socks;
  final int socksColor;
  final String shoes;
  final int shoesColor;
  final Set<String> accessories;

  factory AvatarConfig.defaultFor(AvatarGender gender) => AvatarConfig(
    gender: gender,
    hairStyle: gender == AvatarGender.female ? 'long' : 'short',
    top: gender == AvatarGender.female ? 'dress' : 'tshirt',
    topColor: gender == AvatarGender.female ? 0xFFEC407A : 0xFF42A5F5,
  );

  AvatarConfig copyWith({
    AvatarGender? gender,
    int? skinTone,
    String? hairStyle,
    int? hairColor,
    String? expression,
    String? hat,
    int? hatColor,
    String? top,
    int? topColor,
    String? bottom,
    int? bottomColor,
    String? socks,
    int? socksColor,
    String? shoes,
    int? shoesColor,
    Set<String>? accessories,
  }) {
    return AvatarConfig(
      gender: gender ?? this.gender,
      skinTone: skinTone ?? this.skinTone,
      hairStyle: hairStyle ?? this.hairStyle,
      hairColor: hairColor ?? this.hairColor,
      expression: expression ?? this.expression,
      hat: hat ?? this.hat,
      hatColor: hatColor ?? this.hatColor,
      top: top ?? this.top,
      topColor: topColor ?? this.topColor,
      bottom: bottom ?? this.bottom,
      bottomColor: bottomColor ?? this.bottomColor,
      socks: socks ?? this.socks,
      socksColor: socksColor ?? this.socksColor,
      shoes: shoes ?? this.shoes,
      shoesColor: shoesColor ?? this.shoesColor,
      accessories: accessories ?? this.accessories,
    );
  }

  Map<String, dynamic> toJson() => {
    'g': gender.name,
    'sk': skinTone,
    'hs': hairStyle,
    'hc': hairColor,
    'ex': expression,
    'ht': hat,
    'htc': hatColor,
    'tp': top,
    'tpc': topColor,
    'bt': bottom,
    'btc': bottomColor,
    'sc': socks,
    'scc': socksColor,
    'sh': shoes,
    'shc': shoesColor,
    'ac': accessories.toList(),
  };

  factory AvatarConfig.fromJson(Map<String, dynamic> json) => AvatarConfig(
    gender: AvatarGender.values.firstWhere(
      (g) => g.name == json['g'],
      orElse: () => AvatarGender.male,
    ),
    skinTone: json['sk'] as int? ?? 0xFFF1C27D,
    hairStyle: json['hs'] as String? ?? 'short',
    hairColor: json['hc'] as int? ?? 0xFF263238,
    expression: json['ex'] as String? ?? 'happy',
    hat: json['ht'] as String? ?? 'none',
    hatColor: json['htc'] as int? ?? 0xFF42A5F5,
    top: json['tp'] as String? ?? 'tshirt',
    topColor: json['tpc'] as int? ?? 0xFF42A5F5,
    bottom: json['bt'] as String? ?? 'jeans',
    bottomColor: json['btc'] as int? ?? 0xFF5C6BC0,
    socks: json['sc'] as String? ?? 'ankle',
    socksColor: json['scc'] as int? ?? 0xFFFFFFFF,
    shoes: json['sh'] as String? ?? 'sneakers',
    shoesColor: json['shc'] as int? ?? 0xFF263238,
    accessories: {...?(json['ac'] as List?)?.cast<String>()},
  );

  static const _prefix = 'avatar-design:v1:';

  String encode() =>
      '$_prefix${base64Url.encode(utf8.encode(jsonEncode(toJson())))}';

  static AvatarConfig? tryDecode(String? value) {
    if (value == null || !value.startsWith(_prefix)) return null;
    try {
      final raw = utf8.decode(
        base64Url.decode(value.substring(_prefix.length)),
      );
      return AvatarConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
