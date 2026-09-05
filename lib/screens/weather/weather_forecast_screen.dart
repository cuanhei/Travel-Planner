import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../models/weather_forecast.dart';
import '../../services/locale_service.dart';
import '../../services/weather_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/weather_display.dart';

class WeatherForecastScreen extends StatefulWidget {
  const WeatherForecastScreen({super.key});

  @override
  State<WeatherForecastScreen> createState() => _WeatherForecastScreenState();
}

class _WeatherForecastScreenState extends State<WeatherForecastScreen> {
  final _weatherService = WeatherService();

  ResolvedWeatherWindow? _weather;
  bool _loading = true;
  String? _error;
  bool _outsideMalaysia = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _outsideMalaysia = false;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception(tr('home_location_services_off'));
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception(tr('home_location_permission_denied_forever'));
      }
      if (permission == LocationPermission.denied) {
        throw Exception(tr('home_location_permission_needed'));
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final result = await _weatherService.getForecastsForPosition(
        LatLng(position.latitude, position.longitude),
      );
      if (!mounted) return;
      setState(() {
        _weather = result;
        _loading = false;
      });
    } on LocationNotInMalaysiaException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _outsideMalaysia = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: context.colors.ink,
                    size: 20,
                  ),
                ),
                Expanded(
                  child: Text(
                    tr('weather_forecast_title'),
                    style: TextStyle(
                      color: context.colors.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            _buildBody(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_outsideMalaysia) {
      return _HeroMessage(text: tr('home_weather_outside_malaysia'));
    }
    if (_loading) {
      return _HeroMessage(loading: true, text: tr('home_weather_loading'));
    }
    final error = _error;
    if (error != null) {
      return _HeroMessage(text: error, onRetry: _load);
    }
    final weather = _weather;
    if (weather == null || weather.forecasts.isEmpty) {
      return _HeroMessage(text: tr('home_weather_no_forecast'), onRetry: _load);
    }

    final today = DateTime.now();
    bool isSameDay(DateTime d) =>
        d.year == today.year && d.month == today.month && d.day == today.day;
    final startIndex = weather.forecasts.indexWhere(
      (f) => isSameDay(f.date) || f.date.isAfter(today),
    );
    final upcoming = weather.forecasts.sublist(
      startIndex == -1 ? weather.forecasts.length - 1 : startIndex,
    );
    final current = upcoming.first;
    final outlook = upcoming.length > 1
        ? upcoming.sublist(1).take(5).toList()
        : const <WeatherForecast>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CurrentConditions(areaLabel: weather.areaLabel, forecast: current),
        SizedBox(height: 24),
        Text(
          tr('weather_today_forecast'),
          style: TextStyle(
            color: context.colors.ink,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PeriodCard(
                label: tr('home_period_morning'),
                forecastText: current.morningForecast,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _PeriodCard(
                label: tr('home_period_afternoon'),
                forecastText: current.afternoonForecast,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _PeriodCard(
                label: tr('home_period_night'),
                forecastText: current.nightForecast,
              ),
            ),
          ],
        ),
        if (outlook.isNotEmpty) ...[
          SizedBox(height: 24),
          Text(
            tr('weather_five_day_outlook'),
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          SizedBox(height: 14),
          ...outlook.map((f) => _DailyOutlookTile(forecast: f)),
        ],
      ],
    );
  }
}

class _HeroMessage extends StatelessWidget {
  const _HeroMessage({required this.text, this.loading = false, this.onRetry});

  final String text;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2E9CCA), Color(0xFF6DD5FA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF2E9CCA).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          else
            const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 28),
          SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 13.5),
          ),
          if (onRetry != null) ...[
            SizedBox(height: 10),
            GestureDetector(
              onTap: onRetry,
              child: Text(
                tr('home_weather_retry'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CurrentConditions extends StatelessWidget {
  const _CurrentConditions({required this.areaLabel, required this.forecast});

  final String areaLabel;
  final WeatherForecast forecast;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2E9CCA), Color(0xFF6DD5FA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF2E9CCA).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            '$areaLabel, ${tr('home_malaysia_word')}',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Icon(
            weatherIconFor(forecast.summaryForecast),
            color: Colors.white,
            size: 56,
          ),
          SizedBox(height: 8),
          Text(
            '${forecast.minTemp}° – ${forecast.maxTemp}°C',
            style: TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            translateWeather(forecast.summaryForecast),
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.label, required this.forecastText});

  final String label;
  final String forecastText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: context.colors.muted, fontSize: 11),
          ),
          SizedBox(height: 8),
          Icon(
            weatherIconFor(forecastText),
            color: Color(0xFF2E9CCA),
            size: 22,
          ),
          SizedBox(height: 8),
          Text(
            translateWeather(forecastText),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyOutlookTile extends StatelessWidget {
  const _DailyOutlookTile({required this.forecast});

  final WeatherForecast forecast;

  static const _weekdayKeys = [
    'weather_day_mon',
    'weather_day_tue',
    'weather_day_wed',
    'weather_day_thu',
    'weather_day_fri',
    'weather_day_sat',
    'weather_day_sun',
  ];

  String get _dayLabel => tr(_weekdayKeys[forecast.date.weekday - 1]);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              _dayLabel,
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          Icon(
            weatherIconFor(forecast.summaryForecast),
            color: Color(0xFF2E9CCA),
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              translateWeather(forecast.summaryForecast),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.colors.muted, fontSize: 12.5),
            ),
          ),
          Text(
            '${forecast.maxTemp}°',
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          SizedBox(width: 8),
          Text(
            '${forecast.minTemp}°',
            style: TextStyle(color: context.colors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
