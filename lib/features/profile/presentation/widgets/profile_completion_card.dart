import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/navigation/push_guard.dart';
import '../../../../core/router/app_router.dart' show appRouteObserver, lastPopWasMenuOrDialog;
import '../../../../core/theme/app_colors.dart';
import '../../data/profile_repository.dart';
import '../profile_completion_screen.dart';

/// The Profile tab's completion meter, between the profile card and My Shop: how complete the
/// profile is, a bar, and the next step. Tapping opens the checklist. It stays at 100% ("Your
/// profile is complete"), and refreshes whenever a screen opened from the tab closes.
class ProfileCompletionCard extends ConsumerStatefulWidget {
  const ProfileCompletionCard({super.key});

  @override
  ConsumerState<ProfileCompletionCard> createState() => _ProfileCompletionCardState();
}

class _ProfileCompletionCardState extends ConsumerState<ProfileCompletionCard> with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  /// Back from My Profile, My Services, My Shop or the checklist: any of them may have moved it.
  @override
  void didPopNext() {
    if (lastPopWasMenuOrDialog()) return;
    ref.invalidate(profileCompletionProvider);
  }

  @override
  Widget build(BuildContext context) {
    // Nothing until it loads, or if it can't: the tab works without it. A refresh keeps the
    // last value on screen.
    final completion = ref.watch(profileCompletionProvider).value;
    if (completion == null) return const SizedBox.shrink();
    final complete = completion.isComplete;
    final next = completion.next;
    final title = complete ? 'Your profile is complete' : 'Profile ${completion.percent}% complete';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            // The checklist reads the same value: fetch it fresh, in case something changed
            // while the tab was open (the last value stays on screen meanwhile).
            ref.invalidate(profileCompletionProvider);
            context.pushPage(MaterialPageRoute(builder: (_) => const ProfileCompletionScreen()));
          },
          child: Semantics(
            button: true,
            label: title,
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      ),
                      Icon(
                        complete ? Icons.check_circle : Icons.chevron_right_rounded,
                        color: complete ? AppColors.primary : AppColors.textMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: completion.percent / 100,
                        minHeight: 8,
                        backgroundColor: AppColors.primarySurface,
                        valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                      ),
                    ),
                  ),
                  if (!complete && next != null) ...[
                    const SizedBox(height: 8),
                    Text('Next: ${completionStepHint(next)}',
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
