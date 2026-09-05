import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

const stopDurationOptions = [
  Duration(minutes: 30),
  Duration(hours: 1),
  Duration(hours: 1, minutes: 30),
  Duration(hours: 2),
  Duration(hours: 3),
  Duration(hours: 4),
];

class TripSummary {
  const TripSummary({
    required this.title,
    required this.place,
    required this.dates,
    required this.gradient,
    required this.icon,
    required this.upcoming,
    required this.stops,
    required this.days,
    required this.budget,
  });

  final String title;
  final String place;
  final String dates;
  final List<Color> gradient;
  final IconData icon;
  final bool upcoming;

  final int stops;

  final int days;

  final String budget;
}

final upcomingTrips = [
  const TripSummary(
    title: 'Penang Adventure',
    place: 'Penang, Malaysia',
    dates: 'Aug 14 – Aug 16',
    gradient: AppColors.horizon,
    icon: Icons.location_city_rounded,
    upcoming: true,
    stops: 3,
    days: 3,
    budget: 'RM 1,500',
  ),
];

@immutable
class TripStop {
  const TripStop({
    required this.id,
    required this.name,
    required this.day,
    required this.time,
    required this.icon,
    required this.gradient,
    this.duration = const Duration(hours: 1),
  });

  final int id;
  final String name;
  final int day;
  final TimeOfDay time;
  final IconData icon;
  final List<Color> gradient;

  final Duration duration;

  TripStop copyWith({
    String? name,
    int? day,
    TimeOfDay? time,
    IconData? icon,
    List<Color>? gradient,
    Duration? duration,
  }) {
    return TripStop(
      id: id,
      name: name ?? this.name,
      day: day ?? this.day,
      time: time ?? this.time,
      icon: icon ?? this.icon,
      gradient: gradient ?? this.gradient,
      duration: duration ?? this.duration,
    );
  }
}

class StopCategory {
  const StopCategory(this.label, this.icon, this.gradient);
  final String label;
  final IconData icon;
  final List<Color> gradient;
}

const stopCategories = [
  StopCategory('Sightseeing', Icons.location_city_rounded, AppColors.horizon),
  StopCategory('Shopping', Icons.shopping_bag_rounded, AppColors.dusk),
  StopCategory('Food', Icons.restaurant_rounded, AppColors.sunset),
  StopCategory('Nature', Icons.terrain_rounded, AppColors.lagoon),
  StopCategory('Beach', Icons.beach_access_rounded, AppColors.sunset),
  StopCategory('Culture', Icons.holiday_village_rounded, AppColors.horizon),
];

final pastTrips = [
  const TripSummary(
    title: 'Langkawi Getaway',
    place: 'Langkawi, Malaysia',
    dates: 'Mar 2 – Mar 5',
    gradient: AppColors.lagoon,
    icon: Icons.beach_access_rounded,
    upcoming: false,
    stops: 5,
    days: 4,
    budget: 'RM 2,100',
  ),
  const TripSummary(
    title: 'KL Weekend',
    place: 'Kuala Lumpur, Malaysia',
    dates: 'Jan 18 – Jan 19',
    gradient: AppColors.dusk,
    icon: Icons.location_city_rounded,
    upcoming: false,
    stops: 3,
    days: 2,
    budget: 'RM 680',
  ),
];
