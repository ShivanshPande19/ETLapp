// lib/app/splash_screen.dart
//
// Premium branded splash, shown on every COLD START (app fully closed -> opened)
// while the saved session is restored from secure storage. A minimum display
// time is enforced in AuthNotifier._restoreSession so this is a deliberate
// ~1.8s brand moment rather than a flash. It is NOT shown on resume-from-background.
//
// The logo is loaded from `assets/images/etl_logo.png`. Until that file is
// added, a built-in fallback badge is shown (so the app always builds/runs).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Brand palette
const _bg = Color(0xFF080808);
const _brandRed = Color(0xFFB4332F);
const _white = Color(0xFFF5F5F5);

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _breathe;

  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _textFade;
  late final Animation<double> _loaderFade;
  late final Animation<double> _breatheScale;

  @override
  void initState() {
    super.initState();

    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _logoFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );
    _textFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.45, 0.9, curve: Curves.easeOut),
    );
    _loaderFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
    );

    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _breatheScale = Tween<double>(begin: 1.0, end: 1.025).animate(
      CurvedAnimation(parent: _breathe, curve: Curves.easeInOut),
    );

    _intro.forward();
    _intro.addStatusListener((s) {
      if (s == AnimationStatus.completed) _breathe.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final logoSize = (size.width * 0.52).clamp(160.0, 240.0);

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Subtle radial glow behind the logo for depth.
          Center(
            child: FadeTransition(
              opacity: _logoFade,
              child: Container(
                width: logoSize * 1.7,
                height: logoSize * 1.7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _brandRed.withOpacity(0.16),
                      _brandRed.withOpacity(0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // Logo + tagline
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: _logoFade,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: AnimatedBuilder(
                      animation: _breatheScale,
                      builder: (_, child) => Transform.scale(
                        scale: _breatheScale.value,
                        child: child,
                      ),
                      child: _Logo(size: logoSize),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                FadeTransition(
                  opacity: _textFade,
                  child: Text(
                    'FOOD COURT MANAGEMENT',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3.2,
                      color: Colors.white.withOpacity(0.42),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom loader
          Positioned(
            left: 0,
            right: 0,
            bottom: 56,
            child: FadeTransition(
              opacity: _loaderFade,
              child: Column(
                children: [
                  const _DotsLoader(),
                  const SizedBox(height: 18),
                  Text(
                    'by Azimuth',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.5,
                      color: Colors.white.withOpacity(0.30),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Real logo from assets with a graceful fallback badge if not added yet.
class _Logo extends StatelessWidget {
  final double size;
  const _Logo({required this.size});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/etl_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => _FallbackBadge(size: size),
    );
  }
}

/// Recreated ETL badge — used until the real PNG is dropped in assets/images/.
class _FallbackBadge extends StatelessWidget {
  final double size;
  const _FallbackBadge({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: _brandRed,
        shape: BoxShape.circle,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'ETL',
            style: GoogleFonts.antonSc(
              fontSize: size * 0.30,
              color: _white,
              letterSpacing: 2,
              height: 1.0,
            ),
          ),
          SizedBox(height: size * 0.04),
          Text(
            'EAT  TRUCK  LOVE',
            style: GoogleFonts.inter(
              fontSize: size * 0.072,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: _white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Three brand-red dots with a sequential pulse.
class _DotsLoader extends StatefulWidget {
  const _DotsLoader();

  @override
  State<_DotsLoader> createState() => _DotsLoaderState();
}

class _DotsLoaderState extends State<_DotsLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final t = (_c.value - i * 0.18) % 1.0;
            final glow = (t < 0.5) ? (t * 2) : (2 - t * 2); // 0->1->0
            return Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(
                  Colors.white.withOpacity(0.14),
                  _brandRed,
                  glow.clamp(0.0, 1.0),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
