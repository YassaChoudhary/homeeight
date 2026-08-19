import 'package:flutter/material.dart';

import '../state/app_scope.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/pill_button.dart';
import 'select_language_screen.dart';

/// Screen 3. Selection is committed to [AppState] on Continue, so currency and
/// permit rules follow the user through the rest of the app instead of being
/// discarded.
class ChooseMarketScreen extends StatefulWidget {
  const ChooseMarketScreen({super.key});

  @override
  State<ChooseMarketScreen> createState() => _ChooseMarketScreenState();
}

class _ChooseMarketScreenState extends State<ChooseMarketScreen> {
  Market? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _selected = AppScope.of(context).appState.market);
    });
  }

  void _continue() {
    final selected = _selected;
    if (selected == null) return;
    AppScope.of(context).appState.setMarket(selected);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SelectLanguageScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text('Choose your market', style: AppTextStyles.display()),
              const SizedBox(height: 10),
              Text(
                'Sets your currency, listing rules and language defaults. '
                'You can switch anytime.',
                style: AppTextStyles.body(color: AppColors.inkMuted),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: Market.values.length,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.92,
                  ),
                  itemBuilder: (context, i) {
                    final market = Market.values[i];
                    final selected = market == _selected;
                    return _MarketTile(
                      market: market,
                      selected: selected,
                      onTap: () => setState(() => _selected = market),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 20, top: 12),
                child: PrimaryButton(
                  label: 'Continue',
                  onTap: _selected == null ? null : _continue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarketTile extends StatelessWidget {
  final Market market;
  final bool selected;
  final VoidCallback onTap;

  const _MarketTile({
    required this.market,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: market.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryTint : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.line,
              width: selected ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.asset(
                  market.flagAsset,
                  width: 56,
                  height: 38,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  market.label,
                  style: AppTextStyles.bodyStrong(),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
