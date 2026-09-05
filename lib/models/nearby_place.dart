import 'package:flutter/material.dart';

class NearbyPlace {
  const NearbyPlace({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.primaryType,
    required this.types,
    required this.photoUrl,
    required this.businessStatus,
    required this.editorialSummary,
    required this.priceLevel,
    required this.priceRangeLabel,
    required this.regularOpeningHours,
    required this.regularOpeningHoursPeriods,
    required this.currentOpeningHours,
    required this.currentOpeningHoursPeriods,
    required this.openNow,
    this.distanceKm,
  });

  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  final String? primaryType;

  final List<String> types;

  final String? photoUrl;

  final String? businessStatus;

  final String? editorialSummary;

  final String? priceLevel;

  final String? priceRangeLabel;

  final List<String>? regularOpeningHours;

  final List<OpeningHoursPeriod>? regularOpeningHoursPeriods;

  final List<String>? currentOpeningHours;

  final List<OpeningHoursPeriod>? currentOpeningHoursPeriods;

  final bool? openNow;

  final double? distanceKm;

  String get distanceLabel =>
      distanceKm == null ? '—' : '${distanceKm!.toStringAsFixed(1)} km';

  IconData get icon => _iconForPrimaryType(primaryType);

  List<String>? get openingHours => currentOpeningHours ?? regularOpeningHours;

  String? get priceLevelLabel {
    switch (priceLevel) {
      case 'PRICE_LEVEL_FREE':
        return 'Free';
      case 'PRICE_LEVEL_INEXPENSIVE':
        return '\$';
      case 'PRICE_LEVEL_MODERATE':
        return '\$\$';
      case 'PRICE_LEVEL_EXPENSIVE':
        return '\$\$\$';
      case 'PRICE_LEVEL_VERY_EXPENSIVE':
        return '\$\$\$\$';
      default:
        return null;
    }
  }

  NearbyPlace withDistanceKm(double km) => NearbyPlace(
    id: id,
    name: name,
    address: address,
    latitude: latitude,
    longitude: longitude,
    primaryType: primaryType,
    types: types,
    photoUrl: photoUrl,
    businessStatus: businessStatus,
    editorialSummary: editorialSummary,
    priceLevel: priceLevel,
    priceRangeLabel: priceRangeLabel,
    regularOpeningHours: regularOpeningHours,
    regularOpeningHoursPeriods: regularOpeningHoursPeriods,
    currentOpeningHours: currentOpeningHours,
    currentOpeningHoursPeriods: currentOpeningHoursPeriods,
    openNow: openNow,
    distanceKm: km,
  );

  factory NearbyPlace.fromJson(
    Map<String, dynamic> json, {
    required String apiKey,
    required int photoMaxWidthPx,
  }) {
    final displayName = json['displayName'] as Map<String, dynamic>?;
    final location = json['location'] as Map<String, dynamic>?;
    final photos = json['photos'] as List?;
    final firstPhotoName = (photos != null && photos.isNotEmpty)
        ? (photos.first as Map<String, dynamic>)['name'] as String?
        : null;
    final editorialSummary = json['editorialSummary'] as Map<String, dynamic>?;
    final regularHours = json['regularOpeningHours'] as Map<String, dynamic>?;
    final currentHours = json['currentOpeningHours'] as Map<String, dynamic>?;
    return NearbyPlace(
      id: json['id'] as String,
      name: (displayName?['text'] as String?) ?? 'Unnamed place',
      address: (json['formattedAddress'] as String?) ?? '',
      latitude: (location?['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (location?['longitude'] as num?)?.toDouble() ?? 0,
      primaryType: json['primaryType'] as String?,
      types: [
        for (final t in (json['types'] as List?) ?? const []) t as String,
      ],
      photoUrl: firstPhotoName == null
          ? null
          : 'https://places.googleapis.com/v1/$firstPhotoName/media'
                '?maxWidthPx=$photoMaxWidthPx&key=$apiKey',
      businessStatus: json['businessStatus'] as String?,
      editorialSummary: editorialSummary?['text'] as String?,
      priceLevel: json['priceLevel'] as String?,
      priceRangeLabel: _priceRangeLabel(
        json['priceRange'] as Map<String, dynamic>?,
      ),
      regularOpeningHours: _weekdayDescriptions(regularHours),
      regularOpeningHoursPeriods: _periods(regularHours),
      currentOpeningHours: _weekdayDescriptions(currentHours),
      currentOpeningHoursPeriods: _periods(currentHours),
      openNow: (currentHours?['openNow'] ?? regularHours?['openNow']) as bool?,
    );
  }
}

List<String>? _weekdayDescriptions(Map<String, dynamic>? hours) {
  final list = hours?['weekdayDescriptions'] as List?;
  if (list == null) return null;
  return [for (final d in list) d as String];
}

List<OpeningHoursPeriod>? _periods(Map<String, dynamic>? hours) {
  final list = hours?['periods'] as List?;
  if (list == null) return null;
  return [
    for (final p in list)
      OpeningHoursPeriod.fromJson(p as Map<String, dynamic>),
  ];
}

class OpeningHoursPeriod {
  const OpeningHoursPeriod({
    required this.openDay,
    required this.openHour,
    required this.openMinute,
    this.closeDay,
    this.closeHour,
    this.closeMinute,
  });

  final int openDay;
  final int openHour;
  final int openMinute;
  final int? closeDay;
  final int? closeHour;
  final int? closeMinute;

  factory OpeningHoursPeriod.fromJson(Map<String, dynamic> json) {
    final open = json['open'] as Map<String, dynamic>? ?? const {};
    final close = json['close'] as Map<String, dynamic>?;
    return OpeningHoursPeriod(
      openDay: (open['day'] as num?)?.toInt() ?? 0,
      openHour: (open['hour'] as num?)?.toInt() ?? 0,
      openMinute: (open['minute'] as num?)?.toInt() ?? 0,
      closeDay: (close?['day'] as num?)?.toInt(),
      closeHour: (close?['hour'] as num?)?.toInt(),
      closeMinute: (close?['minute'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'open': {'day': openDay, 'hour': openHour, 'minute': openMinute},
      if (closeDay != null || closeHour != null || closeMinute != null)
        'close': {'day': closeDay, 'hour': closeHour, 'minute': closeMinute},
    };
  }
}

String? _priceRangeLabel(Map<String, dynamic>? range) {
  if (range == null) return null;
  final start = range['startPrice'] as Map<String, dynamic>?;
  final end = range['endPrice'] as Map<String, dynamic>?;
  final currency =
      (start?['currencyCode'] as String?) ??
      (end?['currencyCode'] as String?) ??
      '';
  final startUnits = start?['units'] as String?;
  final endUnits = end?['units'] as String?;
  if (startUnits != null && endUnits != null) {
    return '$currency$startUnits – $currency$endUnits';
  }
  final single = startUnits ?? endUnits;
  return single == null ? null : '$currency$single';
}

IconData _iconForPrimaryType(String? type) {
  switch (type) {
    case 'restaurant':
    case 'cafe':
    case 'meal_takeaway':
    case 'bakery':
      return Icons.restaurant_rounded;
    case 'tourist_attraction':
    case 'point_of_interest':
      return Icons.attractions_rounded;
    case 'park':
    case 'national_park':
      return Icons.terrain_rounded;
    case 'shopping_mall':
    case 'store':
    case 'clothing_store':
      return Icons.shopping_bag_rounded;
    case 'museum':
    case 'art_museum':
    case 'history_museum':
    case 'art_gallery':
    case 'historical_place':
    case 'historical_landmark':
    case 'cultural_landmark':
    case 'monument':
    case 'performing_arts_theater':
      return Icons.museum_rounded;
    case 'hotel':
    case 'lodging':
      return Icons.hotel_rounded;
    case 'beach':
      return Icons.beach_access_rounded;
    case 'night_club':
    case 'bar':
      return Icons.nightlife_rounded;
    case 'place_of_worship':
    case 'hindu_temple':
    case 'mosque':
    case 'church':
      return Icons.holiday_village_rounded;
    default:
      return Icons.place_rounded;
  }
}
