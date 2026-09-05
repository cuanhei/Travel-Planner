import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/gradient_button.dart';
import 'auth_screen.dart';

class _OnboardData {
  _OnboardData({
    required this.icon,
    required this.title,
    required this.description,
    required this.gradient,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<Color> gradient;
}

List<_OnboardData> _pages = [
  _OnboardData(
    icon: Icons.explore_rounded,
    title: 'Discover Your Next\nAdventure',
    description:
        'Explore thousands of destinations curated for every kind of '
        'traveler, from hidden gems to iconic landmarks.',
    gradient: AppColors.horizon,
  ),
  _OnboardData(
    icon: Icons.map_rounded,
    title: 'Plan Every Detail\nEffortlessly',
    description:
        'Build day-by-day itineraries, organize bookings, and keep your '
        'whole trip in one beautiful timeline.',
    gradient: AppColors.dusk,
  ),
  _OnboardData(
    icon: Icons.flight_takeoff_rounded,
    title: 'Travel Smarter,\nStress-Free',
    description:
        'Get real-time tips, budget tracking, and packing checklists so '
        'all you have to do is enjoy the ride.',
    gradient: AppColors.sunset,
  ),
];

/// The app's intro / welcome experience: a swipeable feature carousel
/// that leads into the sign in / sign up screen.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _controller = PageController();
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() => _page = _controller.page ?? 0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Color> _currentGradient() {
    final lower = _page.floor().clamp(0, _pages.length - 1);
    final upper = (lower + 1).clamp(0, _pages.length - 1);
    final t = _page - lower;
    final a = _pages[lower].gradient;
    final b = _pages[upper].gradient;
    return [Color.lerp(a[0], b[0], t)!, Color.lerp(a[1], b[1], t)!];
  }

  void _goToAuth() => Navigator.of(context).push(_authRoute());

  Route _authRoute() {
    return PageRouteBuilder(
      transitionDuration: Duration(milliseconds: 500),
      pageBuilder: (context, animation, secondary) => AuthScreen(),
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final gradient = _currentGradient();
    final isLast = _page.round() == _pages.length - 1;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: -70,
            right: -50,
            child: _softCircle(200, Colors.white.withValues(alpha: 0.08)),
          ),
          Positioned(
            bottom: 140,
            left: -70,
            child: _softCircle(230, Colors.white.withValues(alpha: 0.06)),
          ),
          SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 48,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AnimatedOpacity(
                      opacity: isLast ? 0 : 1,
                      duration: Duration(milliseconds: 250),
                      child: IgnorePointer(
                        ignoring: isLast,
                        child: Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: TextButton(
                            onPressed: _goToAuth,
                            child: Text(
                              'Skip',
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    itemBuilder: (context, index) {
                      return AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          final delta = (index - _page).clamp(-1.0, 1.0);
                          final opacity = (1 - delta.abs()).clamp(0.0, 1.0);
                          final scale = (1 - delta.abs() * 0.25).clamp(
                            0.75,
                            1.0,
                          );
                          return Opacity(
                            opacity: opacity,
                            child: Transform.translate(
                              offset: Offset(delta * 50, 0),
                              child: Transform.scale(
                                scale: scale,
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: _OnboardPage(data: _pages[index]),
                      );
                    },
                  ),
                ),
                _PageIndicator(count: _pages.length, page: _page),
                SizedBox(height: 28),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 28),
                  child: GradientButton(
                    key: ValueKey(isLast),
                    label: isLast ? 'Get Started' : 'Next',
                    icon: Icons.arrow_forward_rounded,
                    colors: [Colors.white, Colors.white],
                    foregroundColor: gradient[0],
                    shadowColor: Colors.black,
                    onPressed: () {
                      if (isLast) {
                        _goToAuth();
                      } else {
                        _controller.nextPage(
                          duration: Duration(milliseconds: 450),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                  ),
                ),
                SizedBox(height: 16),
                TextButton(
                  onPressed: _goToAuth,
                  child: Text(
                    'I already have an account',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _softCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _OnboardPage extends StatelessWidget {
  const _OnboardPage({required this.data});

  final _OnboardData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 600),
            curve: Curves.easeOutBack,
            builder: (context, value, child) {
              return Transform.scale(scale: value, child: child);
            },
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.15),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
              child: Icon(data.icon, size: 72, color: Colors.white),
            ),
          ),
          SizedBox(height: 48),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.25,
            ),
          ),
          SizedBox(height: 16),
          Text(
            data.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.count, required this.page});

  final int count;
  final double page;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final distance = (page - index).abs().clamp(0.0, 1.0);
        final isActive = distance < 0.5;
        return AnimatedContainer(
          duration: Duration(milliseconds: 250),
          curve: Curves.easeOut,
          margin: EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: isActive ? 1 : 0.4),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
