// lib/features/auth/presentation/login_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../domain/auth_notifier.dart';
import '../data/auth_repository.dart';
import '../../../core/services/sse_service.dart';

// ─── Palette ─────────────────────────────────────────────────────────────────
const _bg = Color(0xFF080808);
const _black = Color(0xFF0A0A0A);
const _white = Color(0xFFFFFFFF);
const _grey = Color(0xFF888888);
const _danger = Color(0xFFEF4444);
const _card = Color(0xFFF5F5F5);
// Brand red (Eat Truck Love)
const _red = Color(0xFFC1272D);
const _redDark = Color(0xFF9A161B);

// ─── Screen ──────────────────────────────────────────────────────────────────
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _obscure = true;

  // Declare controllers as nullable to avoid LateInitializationError
  AnimationController? _logoCtrl;
  AnimationController? _logoPulseCtrl;
  AnimationController? _brandCtrl;
  AnimationController? _cardCtrl;
  AnimationController? _fieldsCtrl;
  AnimationController? _dotCtrl;

  // Animations — all nullable until initState completes
  Animation<double>? _logoScale;
  Animation<double>? _logoFade;
  Animation<double>? _logoPulse;
  Animation<double>? _brandFade;
  Animation<Offset>? _brandSlide;
  Animation<double>? _cardFade;
  Animation<Offset>? _cardSlide;
  Animation<double>? _field1Fade;
  Animation<double>? _field2Fade;
  Animation<double>? _btnFade;
  Animation<Offset>? _field1Slide;
  Animation<Offset>? _field2Slide;
  Animation<Offset>? _btnSlide;

  bool _ready = false; // guard: show content only after initState

  @override
  void initState() {
    super.initState();

    // ── Step 1: create ALL controllers (no side effects yet) ──────────────
    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _logoPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _brandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _cardCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _fieldsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // ── Step 2: build animations referencing already-created controllers ──
    _logoScale = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _logoCtrl!, curve: Curves.elasticOut));
    _logoFade = CurvedAnimation(parent: _logoCtrl!, curve: Curves.easeOut);
    _logoPulse = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _logoPulseCtrl!, curve: Curves.easeInOut),
    );

    _brandFade = CurvedAnimation(parent: _brandCtrl!, curve: Curves.easeOut);
    _brandSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _brandCtrl!, curve: Curves.easeOutCubic));

    _cardFade = CurvedAnimation(parent: _cardCtrl!, curve: Curves.easeOut);
    _cardSlide = Tween<Offset>(
      begin: const Offset(0, 0.14),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _cardCtrl!, curve: Curves.easeOutCubic));

    _field1Fade = CurvedAnimation(
      parent: _fieldsCtrl!,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    );
    _field1Slide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _fieldsCtrl!,
            curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
          ),
        );

    _field2Fade = CurvedAnimation(
      parent: _fieldsCtrl!,
      curve: const Interval(0.2, 0.6, curve: Curves.easeOut),
    );
    _field2Slide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _fieldsCtrl!,
            curve: const Interval(0.2, 0.7, curve: Curves.easeOutCubic),
          ),
        );

    _btnFade = CurvedAnimation(
      parent: _fieldsCtrl!,
      curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
    );
    _btnSlide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _fieldsCtrl!,
            curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
          ),
        );

    // ── Step 3: mark ready so build() can render, THEN start animations ──
    // addPostFrameCallback ensures all controllers are set before any
    // repeat/forward triggers a frame rebuild.
    setState(() => _ready = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _logoPulseCtrl!.repeat(reverse: true);
      _dotCtrl!.repeat();
      _logoCtrl!.forward();
      Future.delayed(const Duration(milliseconds: 180), () {
        if (mounted) _brandCtrl!.forward();
      });
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _cardCtrl!.forward();
      });
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _fieldsCtrl!.forward();
      });

      // If we landed here because the session expired (auto sign-out on a 401),
      // surface a one-time message so the user knows why they're back at login.
      final auth = ref.read(authNotifierProvider);
      if (auth.status == AuthStatus.idle &&
          (auth.errorMessage?.isNotEmpty ?? false)) {
        _showError(auth.errorMessage!);
      }
    });

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _logoCtrl?.dispose();
    _logoPulseCtrl?.dispose();
    _brandCtrl?.dispose();
    _cardCtrl?.dispose();
    _fieldsCtrl?.dispose();
    _dotCtrl?.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    _emailFocus.unfocus();
    _passwordFocus.unfocus();
    await ref
        .read(authNotifierProvider.notifier)
        .login(_emailCtrl.text.trim(), _passwordCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.status == AuthStatus.loading;

    ref.listen<AuthState>(authNotifierProvider, (_, next) {
      if (next.status == AuthStatus.success) {
        // Start the realtime SSE stream as soon as we're authenticated. This is
        // idempotent (connect() disconnects first), and guarantees SSE is live
        // even if this login flow doesn't pass through the biometric gate.
        ref.read(sseServiceProvider).connect();
        context.go(next.isStaff ? '/staff/home' : '/home');
      }
      if (next.status == AuthStatus.error) {
        _showError(next.errorMessage ?? 'Login failed');
      }
    });

    // Show plain scaffold until controllers are ready (first frame only)
    if (!_ready) {
      return const Scaffold(backgroundColor: _bg);
    }

    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Floating dots background
          _FloatingDots(animation: _dotCtrl!),

          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // ── Brand section (dark top) ──────────────────────
                Expanded(
                  flex: 4,
                  child: _BrandSection(
                    logoScale: _logoScale!,
                    logoFade: _logoFade!,
                    logoPulse: _logoPulse!,
                    brandFade: _brandFade!,
                    brandSlide: _brandSlide!,
                  ),
                ),

                // ── White form card ───────────────────────────────
                Expanded(
                  flex: 7,
                  child: FadeTransition(
                    opacity: _cardFade!,
                    child: SlideTransition(
                      position: _cardSlide!,
                      child: Theme(
                        // KEY FIX: override global dark theme inside white card
                        data: ThemeData.light().copyWith(
                          colorScheme: ColorScheme.light(
                            primary: _black,
                            onSurface: _black,
                          ),
                          // Ensure a visible BLACK caret/handles on the light
                          // card (global dark theme made the cursor white).
                          textSelectionTheme: const TextSelectionThemeData(
                            cursorColor: _black,
                            selectionColor: Color(0x33C1272D),
                            selectionHandleColor: _red,
                          ),
                        ),
                        child: Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: _white,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(28),
                            ),
                          ),
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              24,
                              28,
                              24,
                              MediaQuery.of(context).viewInsets.bottom + 32,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Heading
                                Text(
                                  'Welcome back',
                                  style: GoogleFonts.antonSc(
                                    fontSize: 26,
                                    color: _black,
                                    letterSpacing: -.5,
                                    height: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Sign in to your manager account',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: _grey,
                                  ),
                                ),
                                const SizedBox(height: 28),

                                // Email
                                FadeTransition(
                                  opacity: _field1Fade!,
                                  child: SlideTransition(
                                    position: _field1Slide!,
                                    child: _InputField(
                                      label: 'Email',
                                      hint: 'manager@etlfoodcourt.com',
                                      icon: Icons.mail_outline_rounded,
                                      controller: _emailCtrl,
                                      focusNode: _emailFocus,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      onSubmitted: (_) =>
                                          _passwordFocus.requestFocus(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // Password
                                FadeTransition(
                                  opacity: _field2Fade!,
                                  child: SlideTransition(
                                    position: _field2Slide!,
                                    child: _InputField(
                                      label: 'Password',
                                      hint: '••••••••',
                                      icon: Icons.lock_outline_rounded,
                                      controller: _passwordCtrl,
                                      focusNode: _passwordFocus,
                                      obscureText: _obscure,
                                      textInputAction: TextInputAction.done,
                                      onSubmitted: (_) => _login(),
                                      suffix: GestureDetector(
                                        onTap: () => setState(
                                          () => _obscure = !_obscure,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            right: 14,
                                          ),
                                          child: Icon(
                                            _obscure
                                                ? Icons.visibility_off_outlined
                                                : Icons.visibility_outlined,
                                            size: 20,
                                            color: _grey,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),

                                // Forgot password
                                FadeTransition(
                                  opacity: _btnFade!,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: _showForgotPasswordSheet,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        child: Text(
                                          'Forgot password?',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: _red,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),

                                // Button
                                FadeTransition(
                                  opacity: _btnFade!,
                                  child: SlideTransition(
                                    position: _btnSlide!,
                                    child: _SignInButton(
                                      isLoading: isLoading,
                                      onTap: _login,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                FadeTransition(
                                  opacity: _btnFade!,
                                  child: Center(
                                    child: Text(
                                      'ETL Food Courts  ·  Internal use only',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: _grey.withOpacity(0.5),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showForgotPasswordSheet() {
    HapticFeedback.selectionClick();
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    bool loading = false;
    bool sent = false;
    String? resultMsg;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            decoration: const BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E5E5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Reset password',
                  style: GoogleFonts.antonSc(
                      fontSize: 22, color: _black, letterSpacing: -0.3),
                ),
                const SizedBox(height: 6),
                Text(
                  sent
                      ? (resultMsg ??
                          'If an account exists for that email, a reset link has been sent.')
                      : 'Enter your account email — we\'ll send you a link to set a new password.',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: _grey, height: 1.5),
                ),
                const SizedBox(height: 20),
                if (!sent) ...[
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    style: GoogleFonts.inter(fontSize: 15, color: _black),
                    cursorColor: _black,
                    decoration: InputDecoration(
                      hintText: 'you@example.com',
                      hintStyle: GoogleFonts.inter(fontSize: 14, color: _grey),
                      filled: true,
                      fillColor: _card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFFE5E5E5)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFFE5E5E5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _red, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: loading
                          ? null
                          : () async {
                              final email = emailCtrl.text.trim();
                              if (email.isEmpty || !email.contains('@')) {
                                setSheet(() => resultMsg = null);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Enter a valid email address'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                return;
                              }
                              setSheet(() => loading = true);
                              try {
                                final msg = await ref
                                    .read(authRepositoryProvider)
                                    .forgotPassword(email);
                                setSheet(() {
                                  sent = true;
                                  loading = false;
                                  resultMsg = msg;
                                });
                              } catch (_) {
                                setSheet(() => loading = false);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Could not reach server. Try again.'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              }
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_red, _redDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: _white, strokeWidth: 2),
                                )
                              : Text(
                                  'Send reset link',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      const Icon(Icons.mark_email_read_rounded,
                          color: Color(0xFF16A34A), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Check your email and open the link to reset your password.',
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              color: _black,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(sheetCtx),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_red, _redDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            'Done',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _danger.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _danger.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: _danger, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: _black,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Floating Dots ────────────────────────────────────────────────────────────
class _FloatingDots extends StatelessWidget {
  final Animation<double> animation;
  const _FloatingDots({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) => SizedBox.expand(
        child: CustomPaint(painter: _DotsPainter(animation.value)),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  final double t;
  _DotsPainter(this.t);

  // [x%, y%, radius, speed, phase]
  static const _dots = [
    [0.12, 0.10, 2.5, 1.0, 0.0],
    [0.80, 0.08, 2.0, 0.7, 0.4],
    [0.55, 0.22, 3.0, 1.2, 0.8],
    [0.25, 0.35, 1.8, 0.9, 1.2],
    [0.90, 0.30, 2.2, 1.1, 0.2],
    [0.07, 0.55, 2.8, 0.8, 1.6],
    [0.70, 0.50, 1.5, 1.3, 0.6],
    [0.40, 0.68, 2.0, 0.6, 2.0],
    [0.85, 0.70, 2.5, 1.0, 1.0],
    [0.15, 0.80, 1.8, 1.4, 0.3],
    [0.60, 0.85, 2.2, 0.7, 1.8],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < _dots.length; i++) {
      final d = _dots[i];
      final val = (t * d[3] + d[4]) % 1.0;
      final opacity = (0.5 - (val - 0.5).abs()) * 0.25;
      final yOffset = (val - 0.5) * 18 * d[3];
      // Every third dot is brand-red for a subtle warm accent.
      final base = i % 3 == 0 ? _red : _white;
      paint.color = base.withOpacity(opacity.clamp(0.0, 0.18));
      canvas.drawCircle(
        Offset(d[0] * size.width, d[1] * size.height + yOffset),
        d[2],
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.t != t;
}

// ─── Brand Section ────────────────────────────────────────────────────────────
class _BrandSection extends StatelessWidget {
  final Animation<double> logoScale;
  final Animation<double> logoFade;
  final Animation<double> logoPulse;
  final Animation<double> brandFade;
  final Animation<Offset> brandSlide;

  const _BrandSection({
    required this.logoScale,
    required this.logoFade,
    required this.logoPulse,
    required this.brandFade,
    required this.brandSlide,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo: pop-in scale + continuous breathe
          FadeTransition(
            opacity: logoFade,
            child: ScaleTransition(
              scale: logoScale,
              child: AnimatedBuilder(
                animation: logoPulse,
                builder: (_, child) =>
                    Transform.scale(scale: logoPulse.value, child: child),
                child: Container(
                  width: 108,
                  height: 108,
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: _white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _red.withOpacity(0.50),
                        blurRadius: 44,
                        spreadRadius: 3,
                      ),
                      BoxShadow(
                        color: _red.withOpacity(0.20),
                        blurRadius: 80,
                        spreadRadius: 14,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/etl_logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Title + pill: slide up from below
          FadeTransition(
            opacity: brandFade,
            child: SlideTransition(
              position: brandSlide,
              child: Column(
                children: [
                  Text(
                    'ETL Management',
                    style: GoogleFonts.antonSc(
                      fontSize: 32,
                      color: _white,
                      letterSpacing: -.5,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _red.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _red.withOpacity(0.40),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      'Food Court Management',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFF0B4B4),
                      ),
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

// ─── Input Field ──────────────────────────────────────────────────────────────
class _InputField extends StatefulWidget {
  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool obscureText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  const _InputField({
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    required this.focusNode,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.suffix,
  });

  @override
  State<_InputField> createState() => _InputFieldState();
}

class _InputFieldState extends State<_InputField> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(() {
      if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _focused ? _red : _grey,
            letterSpacing: .6,
          ),
          child: Text(widget.label.toUpperCase()),
        ),
        const SizedBox(height: 6),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: _focused ? _white : _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _focused ? _red : Colors.grey.shade200,
              width: 1.5,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: _red.withOpacity(0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  widget.icon,
                  key: ValueKey(_focused),
                  color: _focused ? _red : _grey,
                  size: 18,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  obscureText: widget.obscureText,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  onSubmitted: widget.onSubmitted,
                  // Explicit colors — not inherited from dark theme
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    color: _black, // always black text on white bg
                    fontWeight: FontWeight.w500,
                  ),
                  cursorColor: _black,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: GoogleFonts.inter(
                      fontSize: 14,
                      color: _grey.withOpacity(0.55),
                    ),
                    filled: true,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                  ),
                ),
              ),
              if (widget.suffix != null) widget.suffix!,
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Sign In Button ───────────────────────────────────────────────────────────
class _SignInButton extends StatefulWidget {
  final bool isLoading;
  final VoidCallback onTap;
  const _SignInButton({required this.isLoading, required this.onTap});
  @override
  State<_SignInButton> createState() => _SignInButtonState();
}

class _SignInButtonState extends State<_SignInButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  AnimationController? _shimmerCtrl;
  Animation<double>? _shimmer;

  @override
  void initState() {
    super.initState();
    // Init controller first, then start in post-frame
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _shimmer = CurvedAnimation(parent: _shimmerCtrl!, curve: Curves.easeInOut);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _shimmerCtrl!.repeat();
    });
  }

  @override
  void dispose() {
    _shimmerCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.isLoading
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onTap();
            },
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            gradient: widget.isLoading
                ? null
                : const LinearGradient(
                    colors: [_red, _redDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: widget.isLoading ? _redDark.withOpacity(0.5) : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: (!widget.isLoading && !_pressed)
                ? [
                    BoxShadow(
                      color: _red.withOpacity(0.40),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                // Shimmer sweep
                if (!widget.isLoading && _shimmer != null)
                  AnimatedBuilder(
                    animation: _shimmer!,
                    builder: (_, __) => Positioned.fill(
                      child: FractionallySizedBox(
                        widthFactor: 0.35,
                        alignment: Alignment(_shimmer!.value * 3 - 1.5, 0),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                _white.withOpacity(0.06),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // Label / spinner
                Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: widget.isLoading
                        ? const SizedBox(
                            key: ValueKey('loading'),
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: _white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Row(
                            key: const ValueKey('label'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Sign In',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _white,
                                  letterSpacing: .3,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                color: _white,
                                size: 17,
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
