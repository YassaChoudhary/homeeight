import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/pill_button.dart';
import 'choose_market_screen.dart';

class _Slide {
  final String heading;
  final String body;

  /// Full-screen photo behind the slide (assets/images/onboarding/).
  final String image;

  /// Which part of the photo stays in view when it's cropped to the screen
  /// (BoxFit.cover). (0, 0) is the centre; x −1…1 is left…right, y −1…1 is
  /// top…bottom. Tuned per photo so its subject isn't cut off.
  final Alignment focus;

  const _Slide(this.heading, this.body, this.image, this.focus);
}

const List<_Slide> _slides = [
  _Slide(
    'Search homes across\nthe Gulf & South Asia',
    'Verified listings, fair-price insight and direct chat with trusted agents '
        '— in English and Arabic.',
    'assets/images/onboarding/onboarding_1.jpg', // Dubai skyline & marina
    // Slightly above centre, so the Burj Khalifa stays in view.
    Alignment(0, -0.1),
  ),
  _Slide(
    'Built-up area,\nfront and center',
    'Filter and sort by BUA — the one number that actually tells you how big a '
        'home is.',
    'assets/images/onboarding/onboarding_2.jpg', // street between buildings
    Alignment.center,
  ),
  _Slide(
    'Verified listings\nyou can trust',
    'Permit checks, agent licences and owner verification — visible on every '
        'card, before the tap.',
    'assets/images/onboarding/onboarding_3.jpg', // palm tree & villa
    Alignment.center,
  ),
  _Slide(
    'One app,\nthree currencies',
    'Switch between AED, SAR and PKR without ever leaving your search.',
    'assets/images/onboarding/onboarding_4.jpg', // hands holding a phone
    // Landscape photo: keep the phone and hands in frame on a tall screen.
    Alignment(-0.12, 0),
  ),
];

/// Screen 2. The "Next" button is the one place in the app that uses a
/// hug-width primary button (`expand: false`) — everywhere else the CTA is
/// full-bleed, per the Figma frames.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  final ValueNotifier<int> _index = ValueNotifier<int>(0);

  /// Decode all four photos up front, so swiping never shows a blank frame
  /// while the next one loads.
  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    for (final slide in _slides) {
      precacheImage(AssetImage(slide.image), context);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _index.dispose();
    super.dispose();
  }

  void _finish() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ChooseMarketScreen()),
    );
  }

  void _next() {
    if (_index.value == _slides.length - 1) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navDark,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: _slides.length,
            onPageChanged: (i) => _index.value = i,
            itemBuilder: (context, i) => _SlideBackground(slide: _slides[i]),
          ),
          SafeArea(
            child: ValueListenableBuilder<int>(
              valueListenable: _index,
              builder: (context, index, _) {
                final slide = _slides[index];
                final isLast = index == _slides.length - 1;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.topEnd,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                            0, 16, 20, 0),
                        child: AnimatedOpacity(
                          opacity: isLast ? 0 : 1,
                          duration: const Duration(milliseconds: 200),
                          child: IgnorePointer(
                            ignoring: isLast,
                            child: OverlayPillButton(
                              label: 'Skip',
                              bordered: false,
                              onTap: _finish,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            slide.heading,
                            style: AppTextStyles.display(color: Colors.white),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            slide.body,
                            style: AppTextStyles.body(color: Colors.white70),
                          ),
                          const SizedBox(height: 28),
                          Row(
                            children: [
                              for (var i = 0; i < _slides.length; i++)
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin:
                                      const EdgeInsetsDirectional.only(end: 6),
                                  width: i == index ? 22 : 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: i == index
                                        ? const Color(0xFF3FD6C8)
                                        : Colors.white38,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              const Spacer(),
                              PrimaryButton(
                                label: isLast ? 'Get Started' : 'Next',
                                trailingIcon: Icons.arrow_forward_rounded,
                                expand: false,
                                onTap: _next,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The photo, darkened so white text reads on any part of it.
///
/// Two layers over the image:
///   1. an even 18% black tint, which calms bright skies and white walls;
///   2. a top-to-bottom gradient — light at the top (the Skip button still
///      reads), heavy at the bottom where the heading, text and button sit.
class _SlideBackground extends StatelessWidget {
  final _Slide slide;
  const _SlideBackground({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          slide.image,
          fit: BoxFit.cover,
          alignment: slide.focus,
          filterQuality: FilterQuality.medium,
          // Shown while the photo decodes on very slow devices.
          frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
            opacity: frame == null && !sync ? 0 : 1,
            duration: const Duration(milliseconds: 250),
            child: child,
          ),
        ),
        const ColoredBox(color: Color(0x2E000000)), // 18% black
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, 0.40, 0.62, 1],
              colors: [
                Color(0x4D000000), // 30%
                Color(0x61000000), // 38%
                Color(0xB3000000), // 70%
                Color(0xF0000000), // 94%
              ],
            ),
          ),
        ),
      ],
    );
  }
}
