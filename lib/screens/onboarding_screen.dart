import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/pill_button.dart';
import '../widgets/property_image.dart';
import 'choose_market_screen.dart';

class _Slide {
  final String heading;
  final String body;
  final int seed;
  const _Slide(this.heading, this.body, this.seed);
}

const List<_Slide> _slides = [
  _Slide(
    'Search homes across\nthe Gulf & South Asia',
    'Verified listings, fair-price insight and direct chat with trusted agents '
        '— in English and Arabic.',
    0,
  ),
  _Slide(
    'Built-up area,\nfront and center',
    'Filter and sort by BUA — the one number that actually tells you how big a '
        'home is.',
    5,
  ),
  _Slide(
    'Verified listings\nyou can trust',
    'Permit checks, agent licences and owner verification — visible on every '
        'card, before the tap.',
    2,
  ),
  _Slide(
    'One app,\nthree currencies',
    'Switch between AED, SAR and PKR without ever leaving your search.',
    6,
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
            itemBuilder: (context, i) => PropertyImage(
              seed: _slides[i].seed,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.45, 1],
                    colors: [
                      Color(0x26000000),
                      Color(0x8C000000),
                      Color(0xEB000000),
                    ],
                  ),
                ),
              ),
            ),
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
