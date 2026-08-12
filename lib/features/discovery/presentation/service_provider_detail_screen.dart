import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_controller.dart';
import '../../business/data/availability_models.dart';
import '../../business/data/business_repository.dart';
import '../../business/data/product_models.dart';
import '../../business/data/rate_models.dart';
import '../../home/data/home_models.dart';
import '../../home/presentation/widgets/home_widgets.dart';
import '../../messages/presentation/chat_screen.dart';
import '../../feed/presentation/create_post_screen.dart';
import '../../orders/data/cart.dart';
import '../../orders/data/order_models.dart';
import '../../orders/data/orders_repository.dart';
import '../../orders/presentation/cart_review_screen.dart';
import '../../payments/presentation/payment_method_screen.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/sections/basic_sections.dart';
import '../../business/presentation/setup/sp_setup_wizard_screen.dart';
import '../../business/presentation/sp_products_screen.dart';
import '../../services/data/basic_details_fields.dart';
import '../../services/data/service_profile_repository.dart';
import '../../services/presentation/category_fields_form_screen.dart';
import '../data/sp_detail_models.dart';
import 'sp_menu_listing_screen.dart';
import '../discovery_repository.dart';
import 'discover_screen.dart';
import 'widgets/discover_cards.dart';

/// Full service-provider profile. Opened by tapping any SP card.
class ServiceProviderDetailScreen extends ConsumerStatefulWidget {
  const ServiceProviderDetailScreen({super.key, required this.id});
  final int id;

  @override
  ConsumerState<ServiceProviderDetailScreen> createState() => _ServiceProviderDetailScreenState();
}

class _ServiceProviderDetailScreenState extends ConsumerState<ServiceProviderDetailScreen> with RouteAware {
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

  /// An editor pushed from here has just closed — refetch, since it may have changed anything
  /// on this page. Doing it here rather than at each edit site means a new section or pencil
  /// can't forget to, and it survives the editor's own widget being disposed mid-save.
  @override
  void didPopNext() {
    ref.invalidate(serviceProviderDetailProvider(widget.id));
    ref.invalidate(customFieldsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(serviceProviderDetailProvider(widget.id));
    final myUserId = ref.watch(authControllerProvider).user?.id;
    // A restored cart carries only a saved display snapshot, so refresh it against the live
    // catalogue the moment it arrives — prices are re-read and anything the SP has since
    // withdrawn is dropped rather than silently carried to checkout.
    ref.listen<AsyncValue<ServiceProviderDetail>>(serviceProviderDetailProvider(widget.id), (_, next) {
      final sp = next.asData?.value;
      if (sp == null || ref.read(cartProvider).spProfileId != sp.id) return;
      final dropped = ref.read(cartProvider.notifier).reconcileWith(sp.products);
      if (dropped.isEmpty || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${dropped.join(', ')} ${dropped.length == 1 ? 'is' : 'are'} no longer available'),
      ));
    });
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: async.when(
        // Keep showing the current page while a refetch runs. Swapping to a spinner disposed
        // this subtree — and with it the `ref` any open editor was holding, so the refresh it
        // requested on close silently did nothing. Also kills the full-screen flash on refresh.
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => _ErrorView(onRetry: () => ref.invalidate(serviceProviderDetailProvider(widget.id))),
        data: (sp) {
          final isOwner = sp.userId != null && sp.userId == myUserId;
          return Stack(
            children: [
              RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async => ref.invalidate(serviceProviderDetailProvider(widget.id)),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 90),
                  children: isOwner ? _ownerSections(sp) : _residentSections(sp),
                ),
              ),
              if (!isOwner && sp.hasMenu) CartBar(spId: sp.id),
            ],
          );
        },
      ),
    );
  }
}

// Category-field categories rendered generically. basic_details is absorbed into the
// native-look About/Contact blocks (_BasicDetails), travel/service_type into Availability &
// Travel (_TravelDetails), payment gets its own "Payment & Fee" band, and delivery gets its
// own native-look "Delivery Settings" band (_DeliveryDetails/_DeliveryBlock) — none of those
// four get a second, raw generic band.

bool _hasAvailabilityContent(ServiceProviderDetail sp) {
  final travel = _TravelDetails.fromFields(sp);
  return travel.willingToTravel ||
      travel.maxTravelKm != null ||
      travel.schedule != null ||
      travel.serviceAreas.isNotEmpty ||
      travel.extra.isNotEmpty ||
      (sp.hasDateBooking && sp.availability != null) ||
      (sp.yearsOfExperience ?? _BasicDetails.fromFields(sp).yearsOfExperience) != null;
}

/// Owner order (matches Figma): Header → Contact info → About/Education/Profession →
/// Work Gallery → Availability & Travel (+ any leftover category fields) → Payment & Fee
/// (or Charges/Menu fallback) → Event(s) → Posts → Interest Groups. No Reviews.
List<Widget> _ownerSections(ServiceProviderDetail sp) {
  final hasPayment = sp.customFields.any((f) => f.category == 'payment');
  return [
    _TopBar(),
    _ProfileHeader(sp: sp, isOwner: true),
    _Band(child: _ContactInfoBlock(sp: sp)),
    _Band(color: AppColors.surface, child: _AboutBlock(sp: sp, isOwner: true)),
    // Owners see this even when empty: the block carries the only route into the item editor,
    // so hiding it until items exist left a menu SP with no way to add their first one.
    if (sp.hasMenu)
      _MenuBlock(products: sp.products, spId: sp.id, isOwner: true),
    _GalleryBlock(sp: sp, isOwner: true),
    if (_hasAvailabilityContent(sp))
      _Band(child: _AvailabilityBlock(sp: sp, isOwner: true)),
    if (!_DeliveryDetails.fromFields(sp).isEmpty)
      _Band(color: AppColors.surface, child: _DeliveryBlock(sp: sp, isOwner: true)),
    if (hasPayment)
      _Band(child: _CategoryFieldsBlock(sp: sp, isOwner: true, categories: const ['payment']))
    else if (!sp.hasMenu && sp.rates.isNotEmpty)
      _Band(child: _ChargesBlock(rates: sp.rates)),
    _EventsBlock(events: sp.events),
    _PostsBlock(posts: sp.posts),
    _Band(color: AppColors.surface, child: _GroupsBlock(groups: sp.groups)),
  ];
}

/// Resident order (matches Figma): Header w/ rating → "Contact here:" row (+ three-dot) →
/// About/Education/Profession → Availability & Travel (+ leftover category fields) →
/// Charges/Menu → Work Gallery → Verified Review + Submit → Event(s) → Posts → Groups.
/// No Contact-info block, no Payment & Fee band.
List<Widget> _residentSections(ServiceProviderDetail sp) {
  return [
    _TopBar(),
    _ProfileHeader(sp: sp, isOwner: false),
    _Band(color: AppColors.surface, child: _AboutBlock(sp: sp, isOwner: false)),
    if (sp.hasMenu && sp.products.isNotEmpty)
      _MenuBlock(products: sp.products, spId: sp.id, isOwner: false),
    if (_hasAvailabilityContent(sp))
      _Band(child: _AvailabilityBlock(sp: sp)),
    if (!_DeliveryDetails.fromFields(sp).isEmpty)
      _Band(color: AppColors.surface, child: _DeliveryBlock(sp: sp, isOwner: false)),
    if (!sp.hasMenu && sp.rates.isNotEmpty) _Band(child: _ChargesBlock(rates: sp.rates)),
    _GalleryBlock(sp: sp, isOwner: false),
    _Band(color: AppColors.surface, child: _ReviewsBlock(sp: sp)),
    _SubmitReview(id: sp.id),
    _EventsBlock(events: sp.events),
    _PostsBlock(posts: sp.posts),
    _Band(child: _GroupsBlock(groups: sp.groups)),
  ];
}

// ── Layout helpers ───────────────────────────────────────────
class _Band extends StatelessWidget {
  const _Band({required this.child, this.color = const Color(0xFFF3F6F3)});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: color,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: child,
      );
}

/// Plain muted edit-pencil icon (Figma's `mingcute:edit-fill` style — not a filled square).
class _EditIconButton extends StatelessWidget {
  const _EditIconButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(Icons.edit_outlined, size: 18, color: AppColors.textSecondary),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.ink)),
            ),
            ?trailing,
          ],
        ),
      );
}

// ── Top bar (back + more) ────────────────────────────────────
class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, topPad + 6, 8, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          icon: const Icon(Icons.chevron_left, size: 30, color: AppColors.ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
}

// ── Profile header ───────────────────────────────────────────
class _ProfileHeader extends ConsumerStatefulWidget {
  const _ProfileHeader({required this.sp, required this.isOwner});
  final ServiceProviderDetail sp;
  final bool isOwner;

  @override
  ConsumerState<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends ConsumerState<_ProfileHeader> {
  bool _uploading = false;

  Future<void> _changePhoto() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (img == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await img.readAsBytes();
      await ref.read(profileRepositoryProvider).uploadPhoto(bytes, img.name);
      await ref.read(serviceProviderDetailProvider(widget.sp.id).future);
      ref.invalidate(myProfileProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update photo')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _viewPhoto() {
    if (widget.sp.photoUrl == null || widget.sp.photoUrl!.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ImageViewerScreen(url: widget.sp.photoUrl!, heroTag: 'sp-avatar-${widget.sp.id}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final sp = widget.sp;
    final isOwner = widget.isOwner;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: _viewPhoto,
                    child: Hero(
                      tag: 'sp-avatar-${sp.id}',
                      child: Avatar(name: sp.name, photoUrl: sp.photoUrl, radius: 42),
                    ),
                  ),
                  if (_uploading)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                        child: const Center(
                          child: SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  if (isOwner)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _uploading ? null : _changePhoto,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.surface, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(sp.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 22, color: AppColors.ink)),
                        ),
                        if (!isOwner) RatingBadge(value: sp.ratingAvg),
                      ],
                    ),
                    if (sp.service != null) ...[
                      const SizedBox(height: 4),
                      Text(sp.service!,
                          style: const TextStyle(
                              color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 14)),
                    ],
                    if (sp.locationLabel != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 14, color: AppColors.textMuted),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(sp.locationLabel!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (isOwner) const _OwnerBanner() else _ContactRow(sp: sp),
        ],
      ),
    );
  }
}

/// Resident view: Message (direct chat), Call (only if the SP enabled it), Enquire.
class _ContactRow extends ConsumerWidget {
  const _ContactRow({required this.sp});
  final ServiceProviderDetail sp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sp.userId == null) return const SizedBox.shrink();
    final showCall = sp.showCallButton && (sp.publishedPhone?.isNotEmpty ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('For any inquiry, contact here:',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        Row(
          children: [
            _iconButton(
              icon: Icons.chat_bubble_outline,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ChatScreen(
                  otherUserId: sp.userId!,
                  otherName: sp.name,
                  otherPhoto: sp.photoUrl,
                  messageType: 'direct',
                  entityType: 'sp_profile',
                  entityId: sp.id,
                ),
              )),
            ),
            if (showCall) ...[
              const SizedBox(width: 10),
              _iconButton(icon: Icons.call_outlined, onTap: () => launchUrl(Uri(scheme: 'tel', path: sp.publishedPhone))),
            ],
            const SizedBox(width: 10),
            Expanded(
              child: sp.hasMenu
                  ? ElevatedButton.icon(
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => SpMenuListingScreen(spId: sp.id))),
                      icon: const Icon(Icons.shopping_cart_outlined, size: 16),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 42),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      label: const Text('Order', style: TextStyle(fontWeight: FontWeight.w600)),
                    )
                  : ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          otherUserId: sp.userId!,
                          otherName: sp.name,
                          otherPhoto: sp.photoUrl,
                          messageType: 'enquiry',
                          entityType: 'sp_profile',
                          entityId: sp.id,
                        ),
                      )),
                      icon: const Icon(Icons.help_outline, size: 16),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 42),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      label: const Text('Enquire', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
            ),
            const SizedBox(width: 6),
            Builder(
              builder: (btnContext) => _iconButton(
                icon: Icons.more_vert,
                onTap: () => _showProfileActionsMenu(btnContext, ref, sp),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _iconButton({required IconData icon, required VoidCallback onTap}) => Material(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(height: 42, width: 42, child: Icon(icon, color: AppColors.primary, size: 20)),
        ),
      );
}

/// Owner view: replaces the contact row with a link into the profile-completion flow.
class _OwnerBanner extends ConsumerWidget {
  const _OwnerBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fields = ref.watch(customFieldsProvider).asData?.value;
    final finished = ref.watch(myProfileProvider).asData?.value.hasFinishedOnboarding ?? false;
    // Same rule as the home banner: prompt until they've actually been through the chain, and
    // again if a required field is left blank. Every category counts here (the home banner
    // drops payment).
    if (fields == null || (finished && !hasUnansweredRequiredField(fields))) {
      return const SizedBox.shrink();
    }
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        var hasMenu = false;
        try {
          hasMenu = (await ref.read(businessRepositoryProvider).myProviderFeatures()).hasMenu;
        } catch (_) {}
        final cats = onboardingCategories(fields, hasMenu: hasMenu);
        if (cats.isEmpty || !context.mounted) return;
        await pushOnboardingStep(context, ref, cats);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.primary),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Complete your profile with images and videos to get noticed.',
                  style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
            ),
            const Icon(Icons.chevron_right, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

/// Opens the item editor, then refreshes the profile so added items show without a reload.
Future<void> _editProducts(BuildContext context) async {
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SpProductsScreen()));
}

/// Opens the onboarding step a section's content was collected in, then refreshes the profile.
///
/// Every one of these sections is rendered from admin-configured category fields, so the form
/// that owns them is [CategoryFieldsFormScreen] for that category — the same screen the SP
/// filled during onboarding. Pencils used to open unrelated screens (About Me → the name/DOB
/// form, Contact info → a bespoke sheet), which couldn't edit most of what was on display.
///
/// The await-then-invalidate is what makes a save show up. The editors refresh
/// `customFieldsProvider` / `myProfileProvider`, but this screen renders
/// `serviceProviderDetailProvider`, which nothing was refreshing — so edits only appeared
/// after a hot reload rebuilt the container. Invalidating the whole family avoids threading
/// the profile id through every call site; other SPs simply refetch when next viewed.
///
/// Falls back to the native editor when the SP's subcategory configures no fields for the
/// category, so the pencil is never a dead end: `travel` → the availability wizard (where a
/// date-booking SP's working days really live), anything else → the profile's Basic Info.
Future<void> _editSection(
  BuildContext context,
  WidgetRef ref,
  ServiceProviderDetail sp,
  String category,
) async {
  final hasFields = sp.customFields.any((f) => f.category == category);
  final Widget screen = hasFields
      ? CategoryFieldsFormScreen(
          category: category,
          categoryLabel: kCategoryLabels[category] ?? category,
        )
      : category == 'travel'
          ? SpSetupWizardScreen(
              initialAvailability: sp.availability,
              initialName: sp.name,
              hasMenu: sp.hasMenu,
              hasDateBooking: sp.hasDateBooking,
            )
          : const BasicInfoScreen();
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  // No invalidate here: ServiceProviderDetailScreen refreshes itself in didPopNext(), which
  // works even if this widget's ref was disposed while the editor was open.
}

// ── Contact info (owner-only) ─────────────────────────────────
/// What the SP publishes, and where they change it. These are NOT the sign-in credentials:
/// editing here never touches the number or address used to log in, so an SP can keep a
/// private number for access and show a business one here. Using the same value for both is
/// perfectly fine — that's the SP's call.
class _ContactInfoBlock extends ConsumerWidget {
  const _ContactInfoBlock({required this.sp});
  final ServiceProviderDetail sp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = sp.servicePhone?.isNotEmpty == true ? sp.servicePhone : sp.mobile;
    final email = sp.serviceEmail?.isNotEmpty == true ? sp.serviceEmail : sp.email;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Contact info:',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink)),
        const SizedBox(height: 2),
        const Text('Shown to neighbours. Your sign-in details stay private.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 10),
        // Both live on the Basic Details step ("Service Phone No." / "Service Email"), which
        // writes them through to the profile — so that's the form the pencil opens.
        _line(context, 'Mobile: ${phone?.isNotEmpty == true ? phone : '—'}',
            onEdit: () => _editSection(context, ref, sp, 'basic_details')),
        const SizedBox(height: 6),
        _line(context, 'Email: ${email?.isNotEmpty == true ? email : '—'}',
            onEdit: () => _editSection(context, ref, sp, 'basic_details')),
      ],
    );
  }

  Widget _line(BuildContext context, String text, {required VoidCallback onEdit}) => Row(
        children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary))),
          _EditIconButton(onTap: onEdit),
        ],
      );

}

/// Lets the resident enter (and confirm) how much to pay a non-menu SP directly — services
/// are priced by negotiation with the SP, so the "Payment & Fee" rate is only a prefill hint,
/// not an authoritative charge.
class _EnterAmountSheet extends ConsumerStatefulWidget {
  const _EnterAmountSheet({required this.sp});
  final ServiceProviderDetail sp;
  @override
  ConsumerState<_EnterAmountSheet> createState() => _EnterAmountSheetState();
}

class _EnterAmountSheetState extends ConsumerState<_EnterAmountSheet> {
  late final _ctrl = TextEditingController(text: _suggestedAmount(widget.sp) ?? '');
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final amount = double.tryParse(_ctrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final order =
          await ref.read(ordersRepositoryProvider).createDirectPayment(widget.sp.id, amount);
      if (mounted) {
        Navigator.pop(context);
        _openPayment(context, order);
      }
    } on DioException catch (e) {
      final message = (e.response?.data is Map ? (e.response!.data as Map)['message'] as String? : null) ??
          'Could not start payment';
      setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text('Pay ${widget.sp.name}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 4),
          const Text('Enter the amount you\'ve agreed with the provider.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              prefixText: '₹ ',
              hintText: 'Amount',
              errorText: _error,
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _continue,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Continue', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Basic Details mapping ──────────────────────────────────────
/// Resolves About Me / Education / Profession / Years of experience from whichever source
/// has data, native `Profile` columns first, falling back to the admin-configured
/// `basic_details` category custom fields (a genuinely separate data store — see
/// `backend/src/lib/customFields.ts`). Name/Phone/Email `basic_details` fields are
/// deliberately suppressed: the native header name and Contact Info block are authoritative.
/// Anything else unmatched is surfaced under "Additional Details" so nothing configured by
/// the admin (for other subcategories with a different field set) is silently dropped.
class _BasicDetails {
  const _BasicDetails({this.aboutMe, this.education, this.profession, this.yearsOfExperience, this.extra = const []});
  final String? aboutMe;
  final String? education;
  final String? profession;
  final int? yearsOfExperience;
  final List<CustomField> extra;

  factory _BasicDetails.fromFields(ServiceProviderDetail sp) {
    final basicFields = sp.customFields.where((f) => f.category == 'basic_details').toList();
    final matched = <int>{};
    String? pick(RegExp pattern) {
      String? found;
      for (final f in basicFields) {
        if (!pattern.hasMatch(f.fieldName)) continue;
        matched.add(f.fieldId);
        if (found == null && (f.value?.trim().isNotEmpty ?? false)) found = f.value!.trim();
      }
      return found;
    }

    pick(kBasicNamePattern);
    pick(kBasicPhonePattern);
    pick(kBasicEmailPattern);
    final aboutField = pick(kBasicAboutPattern);
    final eduField = pick(kBasicEducationPattern);
    final profField = pick(kBasicProfessionPattern);
    final expField = pick(kBasicExperiencePattern);
    final extra = basicFields.where((f) => !matched.contains(f.fieldId) && (f.value?.trim().isNotEmpty ?? false)).toList();

    return _BasicDetails(
      aboutMe: (sp.aboutMe?.trim().isNotEmpty ?? false) ? sp.aboutMe : aboutField,
      education: sp.educations.isNotEmpty ? null : eduField,
      profession: sp.professions.isNotEmpty ? null : profField,
      yearsOfExperience: sp.yearsOfExperience ?? int.tryParse(expField ?? ''),
      extra: extra,
    );
  }
}

// ── About / Education / Profession ───────────────────────────
class _AboutBlock extends ConsumerWidget {
  const _AboutBlock({required this.sp, required this.isOwner});
  final ServiceProviderDetail sp;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basic = _BasicDetails.fromFields(sp);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          'About Me',
          trailing: isOwner
              ? _EditIconButton(onTap: () => _editSection(context, ref, sp, 'basic_details'))
              : null,
        ),
        Text(
          basic.aboutMe?.isNotEmpty == true ? basic.aboutMe! : 'No description added yet.',
          style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.textSecondary),
        ),
        if (sp.educations.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('Education', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink)),
          const SizedBox(height: 6),
          ...sp.educations.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  e.institution != null ? '${e.label} · ${e.institution}' : e.label,
                  style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
                ),
              )),
        ] else if (basic.education != null) ...[
          const SizedBox(height: 18),
          const Text('Education', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink)),
          const SizedBox(height: 6),
          Text(basic.education!, style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
        ],
        if (sp.professions.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('Profession', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink)),
          const SizedBox(height: 6),
          ...sp.professions.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(p.label, style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
              )),
        ] else if (basic.profession != null) ...[
          const SizedBox(height: 18),
          const Text('Profession', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink)),
          const SizedBox(height: 6),
          Text(basic.profession!, style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
        ],
        if (basic.extra.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('Additional Details',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink)),
          const SizedBox(height: 6),
          ...basic.extra.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('${f.fieldName}: ${f.value}',
                    style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
              )),
        ],
      ],
    );
  }
}

// ── Travel details mapping ─────────────────────────────────────
/// Resolves Willing-to-travel / max distance / service areas / schedule from whichever
/// source has data, native first, falling back to the admin-configured `travel` /
/// `service_type` category custom fields — mirrors `_BasicDetails`. Matches Figma's single
/// merged "Availability & Travel" section: there is no separate generic "Travel" band.
class _TravelDetails {
  const _TravelDetails({
    required this.willingToTravel,
    this.maxTravelKm,
    this.serviceAreas = const [],
    this.schedule,
    this.extra = const [],
  });
  final bool willingToTravel;
  final double? maxTravelKm;
  final List<String> serviceAreas;
  final String? schedule;
  final List<CustomField> extra;

  static final _travelPat = RegExp('travel', caseSensitive: false);
  static final _distancePat = RegExp('distance', caseSensitive: false);
  static final _schedulePat = RegExp('schedule', caseSensitive: false);

  factory _TravelDetails.fromFields(ServiceProviderDetail sp) {
    final fields = sp.customFields.where((f) => f.category == 'travel' || f.category == 'service_type').toList();
    final matched = <int>{};

    CustomField? pincodeField;
    for (final f in fields) {
      if (f.fieldType == 'pincode') {
        matched.add(f.fieldId);
        pincodeField ??= f;
      }
    }

    String? pick(RegExp pattern) {
      String? found;
      for (final f in fields) {
        if (f.fieldType == 'pincode' || !pattern.hasMatch(f.fieldName)) continue;
        matched.add(f.fieldId);
        if (found == null && (f.value?.trim().isNotEmpty ?? false)) found = f.value!.trim();
      }
      return found;
    }

    final willingField = pick(_travelPat);
    final distanceField = pick(_distancePat);
    final scheduleField = pick(_schedulePat);

    final serviceAreas = (pincodeField?.resolvedAreas?.isNotEmpty ?? false)
        ? pincodeField!.resolvedAreas!.map((a) => a.label).toList()
        : (sp.locationLabel != null ? [sp.locationLabel!] : const <String>[]);

    final extra = fields.where((f) => !matched.contains(f.fieldId) && (f.value?.trim().isNotEmpty ?? false)).toList();

    return _TravelDetails(
      willingToTravel: sp.willingToTravel || willingField?.toLowerCase() == 'yes',
      maxTravelKm: sp.availability?.maxTravelKm ?? double.tryParse(distanceField ?? ''),
      serviceAreas: serviceAreas,
      schedule: scheduleField,
      extra: extra,
    );
  }
}

// ── Availability & Travel ────────────────────────────────────
class _AvailabilityBlock extends ConsumerWidget {
  const _AvailabilityBlock({required this.sp, this.isOwner = false});
  final ServiceProviderDetail sp;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = sp.availability;
    final years = sp.yearsOfExperience ?? _BasicDetails.fromFields(sp).yearsOfExperience;
    final travel = _TravelDetails.fromFields(sp);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          'Availability & Travel',
          trailing: isOwner
              ? _EditIconButton(onTap: () => _editSection(context, ref, sp, 'travel'))
              : null,
        ),
        if (travel.willingToTravel) _check('Willing to Travel'),
        if (travel.maxTravelKm != null) _check('Travels up to ${travel.maxTravelKm!.toStringAsFixed(0)} km'),
        if (years != null) _check('$years+ years of experience'),
        if (travel.schedule != null) ...[
          const SizedBox(height: 12),
          const Text('Schedule:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.ink)),
          const SizedBox(height: 6),
          Text(travel.schedule!,
              style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.5)),
        ] else if (sp.hasDateBooking && a != null) ...[
          const SizedBox(height: 12),
          _scheduleCard(context, a),
        ],
        if (travel.serviceAreas.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Service Areas:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.ink)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: travel.serviceAreas.map(_areaDot).toList(),
          ),
        ],
        if (travel.extra.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...travel.extra.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${f.fieldName}: ${f.value}',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              )),
        ],
      ],
    );
  }

  Widget _areaDot(String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 6),
            decoration: const BoxDecoration(color: AppColors.textMuted, shape: BoxShape.circle),
          ),
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      );

  Widget _scheduleCard(BuildContext context, SpAvailability a) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primarySurface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_month_rounded, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Schedule',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text('${a.daysLabel} · ${a.timeLabel}',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            TextButton(
              onPressed: () => showModalBottomSheet(
                context: context,
                backgroundColor: AppColors.surface,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (_) => _SlotsSheet(spId: sp.id),
              ),
              child: const Text('View slots'),
            ),
          ],
        ),
      );

  Widget _check(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.primary, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary))),
          ],
        ),
      );
}

/// Bottom sheet listing an SP's open bookable slots (view-only; booking happens at checkout).
class _SlotsSheet extends ConsumerWidget {
  const _SlotsSheet({required this.spId});
  final int spId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(spSlotsProvider(spId));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Available slots', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 4),
            const Text('Pick a slot at checkout after adding items to your cart.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            const SizedBox(height: 14),
            slots.when(
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              error: (_, _) => const Padding(padding: EdgeInsets.all(24), child: Text('Could not load slots')),
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No open slots right now.', style: TextStyle(color: AppColors.textSecondary)),
                  );
                }
                final byDay = <String, List<OpenSlot>>{};
                for (final s in list) {
                  byDay.putIfAbsent(s.dayLabel, () => []).add(s);
                }
                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                  child: ListView(
                    shrinkWrap: true,
                    children: byDay.entries.map((e) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 6),
                            child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: e.value
                                .map((s) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: AppColors.primarySurface,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(s.timeLabel,
                                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12.5)),
                                    ))
                                .toList(),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Charges (service SP, buyer view) ─────────────────────────
class _ChargesBlock extends StatelessWidget {
  const _ChargesBlock({required this.rates});
  final List<SpRate> rates;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Charges'),
        ...rates.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined, color: AppColors.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(r.typeLabel, style: const TextStyle(fontSize: 14.5, color: AppColors.textPrimary))),
                  Text('₹${r.amount.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
                ],
              ),
            )),
      ],
    );
  }
}

// ── Delivery Settings (native-look, sourced from the 'delivery' custom fields) ───────
class _DeliveryDetails {
  const _DeliveryDetails({
    this.deliveryMethod,
    this.orderTiming,
    this.shippingCharges,
    this.freeThreshold,
    this.belowThreshold,
    this.asPerActuals = false,
    this.packagingCharge,
    this.advanceType,
    this.advancePercentage,
  });
  final String? deliveryMethod;
  final String? orderTiming;
  final String? shippingCharges;
  final double? freeThreshold;
  final double? belowThreshold;
  final bool asPerActuals;
  final double? packagingCharge;
  final String? advanceType;
  final double? advancePercentage;

  bool get chargesShipping => shippingCharges?.toLowerCase() == 'yes';

  bool get isEmpty =>
      deliveryMethod == null &&
      orderTiming == null &&
      shippingCharges == null &&
      freeThreshold == null &&
      belowThreshold == null &&
      packagingCharge == null &&
      advanceType == null;

  factory _DeliveryDetails.fromFields(ServiceProviderDetail sp) {
    final fields = sp.customFields.where((f) => f.category == 'delivery').toList();
    String? byName(String name) {
      for (final f in fields) {
        if (f.fieldName.trim().toLowerCase() == name.toLowerCase()) {
          final v = f.value?.trim();
          return (v != null && v.isNotEmpty) ? v : null;
        }
      }
      return null;
    }

    double? numByName(String name) => double.tryParse(byName(name) ?? '');

    return _DeliveryDetails(
      deliveryMethod: byName('Delivery Method'),
      orderTiming: byName('Order placement timing'),
      shippingCharges: byName('Shipping Charges'),
      freeThreshold: numByName('Free Delivery Threshold'),
      belowThreshold: numByName('Below Threshold'),
      asPerActuals: byName('As Per Actuals')?.toLowerCase() == 'true',
      packagingCharge: numByName('Packaging charges'),
      advanceType: byName('Advanced Payment Settings'),
      advancePercentage: numByName('Advance percentage'),
    );
  }
}

class _DeliveryBlock extends ConsumerWidget {
  const _DeliveryBlock({required this.sp, required this.isOwner});
  final ServiceProviderDetail sp;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = _DeliveryDetails.fromFields(sp);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          'Delivery Settings',
          trailing: isOwner
              // Already opened the right form, but the profile kept showing pre-edit data
              // until a reload — routing through _editSection refreshes it on return.
              ? _EditIconButton(onTap: () => _editSection(context, ref, sp, 'delivery'))
              : null,
        ),
        if (d.deliveryMethod != null) _kv('Delivery Method', d.deliveryMethod!),
        if (d.orderTiming != null) _kv('Order Placement Timing', d.orderTiming!),
        if (d.shippingCharges != null) _kv('Shipping Charges', d.shippingCharges!),
        if (d.chargesShipping && d.freeThreshold != null)
          _row('Free Delivery above order value', '₹${d.freeThreshold!.toStringAsFixed(0)}'),
        if (d.chargesShipping && d.asPerActuals)
          _kv('Delivery Charge', 'As per actuals')
        else if (d.chargesShipping && d.belowThreshold != null)
          _row('Delivery charge below threshold', '₹${d.belowThreshold!.toStringAsFixed(0)}'),
        if (d.packagingCharge != null) _row('Packaging charges', '₹${d.packagingCharge!.toStringAsFixed(0)}'),
        if (d.advanceType != null) _advanceLine(d),
      ],
    );
  }

  Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(text: '$label : ', style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
              TextSpan(text: value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
            ],
          ),
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textMuted))),
            const SizedBox(width: 10),
            Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
          ],
        ),
      );

  Widget _advanceLine(_DeliveryDetails d) {
    final lower = d.advanceType!.toLowerCase();
    final text = lower.contains('percentage') && d.advancePercentage != null
        ? '${d.advancePercentage!.toStringAsFixed(0)}% Advance payment'
        : lower.contains('no advance')
            ? 'No advance payment required'
            : d.advanceType!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
    );
  }
}

// ── Category fields (Basic Details / Travel / Payment / Service Type / Delivery) ─────
/// Renders the SP's answered onboarding fields grouped by admin-configured category. Owners
/// get an edit-pencil per section that deep-links straight into that category's form.
class _CategoryFieldsBlock extends ConsumerWidget {
  const _CategoryFieldsBlock({required this.sp, required this.isOwner, required this.categories});
  final ServiceProviderDetail sp;
  final bool isOwner;
  /// Which categories (in `kCategoryOrder`) this instance renders — callers pass a subset
  /// so "Payment & Fee" (inline text) and the leftover generic categories can be positioned
  /// separately in the section order. `basic_details` is never passed here — it's absorbed
  /// into the native-look About/Contact blocks (see `_BasicDetails`).
  final List<String> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byCategory = <String, List<CustomField>>{};
    for (final f in sp.customFields) {
      if (!categories.contains(f.category)) continue;
      byCategory.putIfAbsent(f.category, () => []).add(f);
    }
    final present = kCategoryOrder.where(byCategory.containsKey).toList();
    if (present.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < present.length; i++) ...[
          if (i != 0) const SizedBox(height: 20),
          _categorySection(context, ref, present[i], byCategory[present[i]]!),
        ],
      ],
    );
  }

  Widget _categorySection(
      BuildContext context, WidgetRef ref, String category, List<CustomField> fields) {
    final pencil = isOwner ? _EditIconButton(onTap: () => _editSection(context, ref, sp, category)) : null;

    if (category == 'payment') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(kCategoryLabels[category] ?? category, trailing: pencil),
          ...fields.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${f.fieldName}: ${f.value ?? ''}',
                    style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary)),
              )),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(kCategoryLabels[category] ?? category, trailing: pencil),
        ...fields.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(f.fieldName, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: f.fieldType == 'pincode'
                        ? Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: (f.resolvedAreas ?? [])
                                .map((a) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.primarySurface,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(a.label,
                                          style: const TextStyle(
                                              color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                                    ))
                                .toList(),
                          )
                        : Text(f.value ?? '',
                            style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary)),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}

/// Sticky "Book" bar for service SPs → opens the booking request flow.
// ── Work Gallery ─────────────────────────────────────────────
// ── Menu / products — horizontally-scrolling preview (mirrors Work Gallery). Read-only
// for the owner (no cart controls on their own items); residents get Add/stepper + a
// "Show All" link into the full listing screen.
class _MenuBlock extends ConsumerWidget {
  const _MenuBlock({required this.products, required this.spId, required this.isOwner});
  final List<SpProduct> products;
  final int spId;
  final bool isOwner;

  static const _previewCount = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = products.take(_previewCount).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: _SectionTitle(
              'Item List (${products.length})',
              trailing: isOwner
                  ? _EditIconButton(onTap: () => _editProducts(context))
                  : InkWell(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SpMenuListingScreen(spId: spId),
                      )),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Show All', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                          Icon(Icons.chevron_right, size: 18, color: AppColors.primary),
                        ],
                      ),
                    ),
            ),
          ),
          if (preview.isEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 20, top: 4, bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "You haven't added any items yet. Residents can't order until you do.",
                    style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _editProducts(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add items'),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 168,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 20),
                itemCount: preview.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _MenuItemCard(product: preview[i]),
              ),
            ),
        ],
      ),
    );
  }
}

/// A read-only preview tile. Adding to the cart lives in [SpMenuListingScreen] — reached from
/// the Order button and "Show All" — so the profile stays a summary rather than a shop counter.
class _MenuItemCard extends StatelessWidget {
  const _MenuItemCard({required this.product});
  final SpProduct product;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: (product.photoUrl != null && product.photoUrl!.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: AppConfig.assetUrl(product.photoUrl!),
                    width: 128,
                    height: 90,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => _ph(),
                  )
                : _ph(),
          ),
          const SizedBox(height: 8),
          Text(product.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          if (product.price != null)
            Text('₹${product.price!.toStringAsFixed(0)}${product.quantityLabel.isNotEmpty ? '  ·  ${product.quantityLabel}' : ''}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _ph() => Container(
        width: 128,
        height: 90,
        color: AppColors.primarySurface,
        child: const Icon(Icons.bakery_dining_outlined, color: AppColors.primary),
      );
}

// ── Sticky cart bar (also reused standalone by SpMenuListingScreen) ──────────────────
class CartBar extends ConsumerWidget {
  const CartBar({super.key, required this.spId});
  final int spId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    if (cart.spProfileId != spId || cart.isEmpty) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CartReviewScreen())),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(
                  children: [
                    Text('${cart.count} item${cart.count == 1 ? '' : 's'}  ·  ₹${cart.subtotal.toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                    const Spacer(),
                    const Text('View Cart', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                    const Icon(Icons.chevron_right, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryBlock extends ConsumerWidget {
  const _GalleryBlock({required this.sp, required this.isOwner});
  final ServiceProviderDetail sp;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = sp.gallery;
    if (items.isEmpty && !isOwner) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 0, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 20),
            child: _SectionTitle('Work Gallery'),
          ),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length + (isOwner ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                if (isOwner && i == items.length) return _AddGalleryTile(spId: sp.id);
                final item = items[i];
                return _GalleryTile(
                  item: item,
                  isOwner: isOwner,
                  onDelete: () async {
                    await ref.read(profileRepositoryProvider).deleteMedia(item.id);
                    ref.invalidate(serviceProviderDetailProvider(sp.id));
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({required this.item, required this.isOwner, required this.onDelete});
  final ProfileMediaItem item;
  final bool isOwner;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: item.isVideo
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _ImageViewerScreen(url: item.url, heroTag: 'gallery-${item.id}'),
                  )),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: item.isVideo
                ? Container(
                    width: 114,
                    height: 64,
                    color: Colors.black87,
                    alignment: Alignment.center,
                    child: const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 26),
                  )
                : Hero(
                    tag: 'gallery-${item.id}',
                    child: CachedNetworkImage(
                      imageUrl: AppConfig.assetUrl(item.url),
                      width: 114,
                      height: 64,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(width: 114, height: 64, color: AppColors.primarySurface),
                      errorWidget: (_, _, _) => Container(
                        width: 114,
                        height: 64,
                        color: AppColors.primarySurface,
                        child: const Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
                      ),
                    ),
                  ),
          ),
        ),
        if (isOwner)
          Positioned(
            top: -6,
            right: -6,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

class _AddGalleryTile extends ConsumerStatefulWidget {
  const _AddGalleryTile({required this.spId});
  final int spId;
  @override
  ConsumerState<_AddGalleryTile> createState() => _AddGalleryTileState();
}

class _AddGalleryTileState extends ConsumerState<_AddGalleryTile> {
  bool _busy = false;

  Future<void> _pick(String mediaType) async {
    final picker = ImagePicker();
    final file = mediaType == 'video'
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      await ref.read(profileRepositoryProvider).addMedia(bytes, file.name, mediaType);
      await ref.read(serviceProviderDetailProvider(widget.spId).future);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload failed')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showChoice() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_outlined, color: AppColors.primary),
              title: const Text('Add photo'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pick('photo');
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined, color: AppColors.primary),
              title: const Text('Add video'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pick('video');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _busy ? null : _showChoice,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 114,
        height: 64,
        decoration: BoxDecoration(
          color: AppColors.primarySurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        alignment: Alignment.center,
        child: _busy
            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add, color: AppColors.primary),
      ),
    );
  }
}

// ── Verified Reviews ─────────────────────────────────────────
class _ReviewsBlock extends StatelessWidget {
  const _ReviewsBlock({required this.sp});
  final ServiceProviderDetail sp;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          'Verified Review',
          trailing: sp.reviews.length > 2
              ? const Text('View All >',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13))
              : null,
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('Verified Reviews from your area',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        ),
        if (sp.reviews.isEmpty)
          const Text('No reviews yet — be the first to review.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted))
        else
          ...sp.reviews.take(3).map((r) => _ReviewTile(review: r)),
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});
  final SpReview review;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(name: review.raterName, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(review.raterName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        ),
                        const SizedBox(width: 8),
                        Text(review.raterTypeLabel,
                            style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      review.review?.isNotEmpty == true ? review.review! : 'Rated ${review.rating}★',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              RatingBadge(value: review.rating.toDouble()),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.divider),
        ],
      ),
    );
  }
}

// ── Submit a Review ──────────────────────────────────────────
class _SubmitReview extends ConsumerStatefulWidget {
  const _SubmitReview({required this.id});
  final int id;
  @override
  ConsumerState<_SubmitReview> createState() => _SubmitReviewState();
}

class _SubmitReviewState extends ConsumerState<_SubmitReview> {
  int _stars = 0;
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tap a star to rate first')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(discoveryRepositoryProvider).submitReview(
            widget.id,
            rating: _stars,
            review: _controller.text,
          );
      if (!mounted) return;
      _controller.clear();
      setState(() => _stars = 0);
      ref.invalidate(serviceProviderDetailProvider(widget.id));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks for your review!')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not submit review')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Band(
      color: const Color(0xFFF3F6F3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Submit a Review'),
          Row(
            children: List.generate(5, (i) {
              final filled = i < _stars;
              return GestureDetector(
                onTap: () => setState(() => _stars = i + 1),
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(filled ? Icons.star_rounded : Icons.star_border_rounded,
                      color: filled ? AppColors.warning : AppColors.textMuted, size: 30),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Share your experience....',
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Submit', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Event(s) ─────────────────────────────────────────────────
/// Muted label + green tappable CTA, matching Figma's empty-state pattern
/// (Events/Posts/Interest Groups when the SP has none yet).
class _EmptyStateCta extends StatelessWidget {
  const _EmptyStateCta({required this.label, required this.cta, required this.onTap});
  final String label;
  final String cta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
        const SizedBox(height: 44),
        Center(
          child: InkWell(
            onTap: onTap,
            child: Text(cta,
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13.5)),
          ),
        ),
      ],
    );
  }
}

void _openDiscoverTab(BuildContext context, WidgetRef ref, int tab) {
  ref.read(discoverTabProvider.notifier).set(tab);
  final navigator = Navigator.of(context);
  navigator.push(MaterialPageRoute(
    builder: (_) => DiscoverScreen(onBack: () => navigator.maybePop()),
  ));
}

class _EventsBlock extends ConsumerWidget {
  const _EventsBlock({required this.events});
  final List<SpEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 0, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 20),
            child: _SectionTitle('Event(s)'),
          ),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: _EmptyStateCta(
                label: 'None',
                cta: 'Explore Events near you',
                onTap: () => _openDiscoverTab(context, ref, 1),
              ),
            )
          else
            SizedBox(
              height: 210,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: events.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _SpEventCard(item: events[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _SpEventCard extends StatelessWidget {
  const _SpEventCard({required this.item});
  final SpEvent item;

  @override
  Widget build(BuildContext context) {
    final e = item.event;
    final date = e.date != null ? DateFormat('EEE, MMM d').format(e.date!) : '';
    final time = eventTimeRange(e);
    final closed = item.isPast;
    final statusLabel = closed ? 'Closed' : (item.isHosting ? 'Hosting' : 'Attending');
    final statusColor = closed ? AppColors.textMuted : AppColors.primary;
    return Container(
      width: 190,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              NetworkThumb(
                photoUrl: e.photoUrl,
                fallbackIcon: Icons.celebration_rounded,
                width: double.infinity,
                height: 92,
                radius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(6)),
                  child: Text(statusLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ),
              Positioned(top: 8, right: 8, child: RatingBadge(value: e.ratingAvg, compact: true)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 4),
                Text(time.isNotEmpty ? '$date | $time' : date,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                if (e.location != null && e.location!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(e.location!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text('By : ${e.creatorName ?? 'Organizer'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                    ),
                    if (!closed) const JoinButton(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Posts ────────────────────────────────────────────────────
class _PostsBlock extends StatelessWidget {
  const _PostsBlock({required this.posts});
  final List<DiscussionItem> posts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Posts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.ink)),
            const SizedBox(height: 10),
            if (posts.isEmpty)
              _EmptyStateCta(
                label: 'No Post Found',
                cta: 'Create a post now',
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const CreatePostScreen())),
              ),
            ...posts.take(2).map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Avatar(name: p.authorName, photoUrl: p.authorPhoto, radius: 16),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.authorName,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                const Text('Resident',
                                    style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(p.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.favorite_border, size: 15, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text('${p.likes}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ],
                  ),
                )),
            if (posts.isNotEmpty)
              Center(
                child: TextButton(
                  onPressed: () {},
                  child: const Text('View More',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Interest Groups ──────────────────────────────────────────
class _GroupsBlock extends ConsumerWidget {
  const _GroupsBlock({required this.groups});
  final List<SpGroup> groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = groups.where((g) => g.role == 'admin').toList();
    final member = groups.where((g) => g.role == 'member').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Interest Groups'),
        if (groups.isEmpty)
          _EmptyStateCta(
            label: 'No groups joined',
            cta: 'Join your interest groups',
            onTap: () => _openDiscoverTab(context, ref, 3),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (admin.isNotEmpty) Expanded(child: _roleColumn('Admin', admin)),
              if (member.isNotEmpty) Expanded(child: _roleColumn('Member', member)),
            ],
          ),
      ],
    );
  }

  Widget _roleColumn(String label, List<SpGroup> items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: items.map((g) => _GroupChip(group: g.group)).toList(),
          ),
        ],
      );
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({required this.group});
  final GroupItem group;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              NetworkThumb(
                photoUrl: group.photoUrl,
                fallbackIcon: Icons.groups_rounded,
                width: 66,
                height: 66,
                radius: BorderRadius.circular(33),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.surface, width: 1.5),
                  ),
                  child: Text('${group.members}',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(group.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ── Three-dot menu: Make Payment / Report Abuse / Share / Block ──────────────
/// Small anchored popup matching Figma's 3-dot component exactly (`EL-41292289`: 91×191,
/// white, 5px corner radius, 3 thin dividers) — not a full-width bottom sheet.
Future<void> _showProfileActionsMenu(BuildContext anchorContext, WidgetRef ref, ServiceProviderDetail sp) async {
  final box = anchorContext.findRenderObject() as RenderBox;
  final overlay = Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
  final position = RelativeRect.fromRect(
    Rect.fromPoints(
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      box.localToGlobal(Offset.zero, ancestor: overlay),
    ),
    Offset.zero & overlay.size,
  );

  const labelStyle = TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: 12, color: AppColors.ink);

  final action = await showMenu<String>(
    context: anchorContext,
    position: position,
    color: AppColors.surface,
    elevation: 4,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    constraints: const BoxConstraints(minWidth: 110, maxWidth: 140),
    items: [
      PopupMenuItem<String>(
        value: 'payment',
        height: 58,
        padding: EdgeInsets.zero,
        child: const Center(
          child: Text('Make\nPayment',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: 12, color: AppColors.primary)),
        ),
      ),
      const PopupMenuDivider(height: 1),
      PopupMenuItem<String>(
        value: 'report',
        height: 52,
        child: Row(
          children: [
            const Icon(Icons.flag_outlined, size: 20, color: AppColors.ink),
            const SizedBox(width: 10),
            const Text('Report\nAbuse', style: labelStyle),
          ],
        ),
      ),
      const PopupMenuDivider(height: 1),
      PopupMenuItem<String>(
        value: 'share',
        height: 40,
        child: Row(
          children: [
            const Icon(Icons.share_outlined, size: 20, color: AppColors.ink),
            const SizedBox(width: 10),
            const Text('Share', style: labelStyle),
          ],
        ),
      ),
      const PopupMenuDivider(height: 1),
      PopupMenuItem<String>(
        value: 'block',
        height: 41,
        child: Row(
          children: [
            const Icon(Icons.block, size: 20, color: AppColors.ink),
            const SizedBox(width: 10),
            Text(sp.isBlocked ? 'Unblock' : 'Block', style: labelStyle),
          ],
        ),
      ),
    ],
  );

  if (action == null || !anchorContext.mounted) return;
  switch (action) {
    case 'payment':
      await _makePayment(anchorContext, ref, sp);
    case 'report':
      showModalBottomSheet<void>(
        context: anchorContext,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => _ReportSheet(sp: sp),
      );
    case 'share':
      await _shareProfile(anchorContext, ref, sp);
    case 'block':
      await _toggleBlockSp(anchorContext, ref, sp);
  }
}

/// Best-effort prefill only (not authoritative — the resident can change it freely):
/// prefer a `payment`-category field named like "charge/fee/amount/price", else the first
/// numeric `payment` field. Mirrors the matching pattern used by `_BasicDetails`/`_TravelDetails`.
String? _suggestedAmount(ServiceProviderDetail sp) {
  final fields = sp.customFields.where((f) => f.category == 'payment').toList();
  bool numeric(String? v) => v != null && v.trim().isNotEmpty && double.tryParse(v) != null;
  final named = fields.where((f) => RegExp('charge|fee|amount|price', caseSensitive: false).hasMatch(f.fieldName));
  for (final f in named) {
    if (numeric(f.value)) return f.value;
  }
  for (final f in fields) {
    if (numeric(f.value)) return f.value;
  }
  return null;
}

Future<void> _makePayment(BuildContext context, WidgetRef ref, ServiceProviderDetail sp) async {
  // Menu/product SPs (bakers, food, delivery): payment always attaches to a real placed
  // order — cart/quantities/delivery must exist before there's anything to pay for.
  if (!sp.hasMenu) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EnterAmountSheet(sp: sp),
    );
    return;
  }

  List<OrderModel> orders;
  try {
    orders = await ref.read(ordersRepositoryProvider).myOrders();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not load orders')));
    }
    return;
  }
  final pending = orders.where((o) => o.spProfileId == sp.id && !o.paid && o.status == 'accepted').toList();
  if (!context.mounted) return;
  if (pending.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('No pending payment for this provider.')));
    return;
  }
  if (pending.length == 1) {
    _openPayment(context, pending.first);
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Pending payments', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
          for (final o in pending)
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined, color: AppColors.primary),
              title: Text(o.placedAt != null ? DateFormat('EEE, MMM d').format(o.placedAt!) : 'Order #${o.id}'),
              trailing: Text('₹${o.totalAmount.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.of(ctx).pop();
                _openPayment(context, o);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Pays an existing booking from the SP's profile. The flow pops itself when it finishes, so
/// this lands back here either way; the result isn't needed.
void _openPayment(BuildContext context, OrderModel order) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => PaymentMethodScreen(orderId: order.id, total: order.totalAmount),
  ));
}

Future<void> _shareProfile(BuildContext context, WidgetRef ref, ServiceProviderDetail sp) async {
  final parts = <String>[sp.name];
  if (sp.service != null) parts.add(sp.service!);
  if (sp.showCallButton && (sp.publishedPhone?.isNotEmpty ?? false)) parts.add('Contact: ${sp.publishedPhone}');
  await SharePlus.instance.share(ShareParams(text: parts.join(' · ')));
  try {
    await ref.read(discoveryRepositoryProvider).shareProfile(sp.id);
  } catch (_) {
    // Non-blocking — the share sheet already completed.
  }
}

Future<void> _toggleBlockSp(BuildContext context, WidgetRef ref, ServiceProviderDetail sp) async {
  final userId = sp.userId;
  if (userId == null) return;
  if (sp.isBlocked) {
    await ref.read(discoveryRepositoryProvider).unblockUser(userId);
    ref.invalidate(serviceProviderDetailProvider(sp.id));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unblocked')));
    }
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Block ${sp.name}?'),
      content: const Text("You won't be able to message or call each other."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Block', style: TextStyle(color: AppColors.error)),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(discoveryRepositoryProvider).blockUser(userId);
  ref.invalidate(serviceProviderDetailProvider(sp.id));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Blocked')));
  }
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.sp});
  final ServiceProviderDetail sp;
  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  static const _reasons = ['Spam', 'Fake profile', 'Inappropriate content', 'Fraud/Scam', 'Other'];
  String? _selected;
  final _otherCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _selected == 'Other' ? _otherCtrl.text.trim() : _selected;
    if (reason == null || reason.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await ref.read(discoveryRepositoryProvider).reportProfile(widget.sp.id, reason: reason);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not submit report')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const Text('Report abuse', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 10),
          ..._reasons.map((r) => RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: r,
                groupValue: _selected,
                onChanged: (v) => setState(() => _selected = v),
                title: Text(r),
              )),
          if (_selected == 'Other') ...[
            const SizedBox(height: 4),
            TextField(
              controller: _otherCtrl,
              decoration: InputDecoration(
                hintText: 'Tell us more',
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting || _selected == null ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Submit', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen tap-to-view image viewer (avatar / Work Gallery photos). Pinch-to-zoom via
/// `InteractiveViewer`, `Hero`-animated in from the tapped thumbnail, tap to dismiss.
class _ImageViewerScreen extends StatelessWidget {
  const _ImageViewerScreen({required this.url, required this.heroTag});
  final String url;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: Stack(
          children: [
            Center(
              child: Hero(
                tag: heroTag,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: CachedNetworkImage(
                    imageUrl: AppConfig.assetUrl(url),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 52, color: AppColors.textMuted),
            const SizedBox(height: 14),
            const Text("Couldn't load this profile", style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
