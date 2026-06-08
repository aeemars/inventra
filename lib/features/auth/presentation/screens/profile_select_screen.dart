import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/extensions/theme_ext.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/entities/app_user.dart';
import '../controllers/auth_controller.dart';
import '../../../../shared/providers/active_profile_provider.dart';

class ProfileSelectScreen extends ConsumerWidget {
  const ProfileSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider)!;

    return Scaffold(
      backgroundColor: context.appBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.screenPaddingH),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              Text('Welcome back',
                  style: AppTypography.bodyMedium
                      .copyWith(color: context.appTextSecondary)),
              const SizedBox(height: 4),
              Text('Choose a profile',
                  style: AppTypography.h2),
              const SizedBox(height: 6),
              Text(
                'You have ${user.profiles.length} profiles linked to '
                '${user.email}. Select one to continue.',
                style: AppTypography.bodySmall
                    .copyWith(color: context.appTextSecondary),
              ),
              const SizedBox(height: AppSizes.xxl),
              ...user.profiles.map(
                (profile) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.md),
                  child: GestureDetector(
                     behavior: HitTestBehavior.opaque,
                    onTap: () {
                      ref
                          .read(activeProfileProvider.notifier)
                          .setProfile(profile);
                      context.go('/dashboard');
                    },
                    child: AppCard(
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.primarySurface,
                              borderRadius: BorderRadius.circular(
                                  AppSizes.radiusMd),
                            ),
                            child: Icon(
                              profile.role == UserRole.admin
                                  ? Icons.admin_panel_settings_rounded
                                  : Icons.person_rounded,
                              color: AppColors.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: AppSizes.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(profile.displayName,
                                    style: AppTypography.bodyMedium
                                        .copyWith(
                                            fontWeight:
                                                FontWeight.w600)),
                                Text(profile.role.displayName,
                                    style: AppTypography.bodySmall
                                        .copyWith(
                                            color: context
                                                .appTextSecondary)),
                                if (profile.shopName != null)
                                  Text(profile.shopName!,
                                      style: AppTypography.labelSmall
                                          .copyWith(
                                              color:
                                                  AppColors.primary)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Center(
                child: TextButton(
                  onPressed: () async {
                    await ref
                        .read(authControllerProvider.notifier)
                        .signOut();
                    if (context.mounted) context.go('/login');
                  },
                  child: Text('Sign out',
                      style: AppTypography.bodyMedium.copyWith(
                          color: context.appTextSecondary)),
                ),
              ),
              const SizedBox(height: AppSizes.xl),
            ],
          ),
        ),
      ),
    );
  }
}
