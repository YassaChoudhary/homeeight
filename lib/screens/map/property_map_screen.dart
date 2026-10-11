import 'package:flutter/material.dart';

import '../../models/property.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/home8_map.dart';

/// Full-screen map of one listing's approximate area (from the detail page).
///
/// Shades a circle instead of dropping a pin — the exact address stays
/// private until the owner accepts an enquiry. Later this screen also lists
/// nearby schools, hospitals and so on as extra pin sets.
class PropertyMapScreen extends StatefulWidget {
  final Property property;

  const PropertyMapScreen({super.key, required this.property});

  @override
  State<PropertyMapScreen> createState() => _PropertyMapScreenState();
}

class _PropertyMapScreenState extends State<PropertyMapScreen> {
  final Home8MapController _map = Home8MapController();

  @override
  Widget build(BuildContext context) {
    final p = widget.property;
    final area = p.mapLocation;
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: area == null
                ? const MapUnavailable()
                : Home8Map(
                    controller: _map,
                    initialCenter: area,
                    initialZoom: 14.5,
                    area: area,
                    showMyLocation: true,
                  ),
          ),
          Positioned(
            left: AppSpacing.screenPadding,
            top: top + 10,
            child: MapCircleButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          if (area != null)
            Positioned(
              right: AppSpacing.screenPadding,
              bottom: bottom + 150,
              child: MapCircleButton(
                icon: Icons.center_focus_strong_rounded,
                tooltip: 'Back to the listing',
                onTap: () => _map.flyTo(area, zoom: 14.5),
              ),
            ),
          Positioned(
            left: AppSpacing.screenPadding,
            right: AppSpacing.screenPadding,
            bottom: bottom + 16,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.s4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyStrong(),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.addressLine.isNotEmpty ? p.addressLine : p.area,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption(),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.shield_outlined,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'The home is inside the shaded area. The exact '
                          'address is shared after the owner accepts your '
                          'enquiry.',
                          style: AppTextStyles.caption(),
                        ),
                      ),
                    ],
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
