import 'package:flutter/material.dart';

/// Brand icon lookup for service categories / service types.
///
/// Categories and their types are admin-editable master data, so this matches on
/// keywords rather than exact names — a newly added "Cake baker" still lands on the
/// catering icon. Rules are ordered: the first whose keyword appears in the name wins,
/// so narrow terms ('tax', 'nail') must sit above broad ones ('agent', 'art').
///
/// A rule's icon is a brand PNG (its asset name) or, where the set has nothing that fits, a
/// filled Material glyph. Anything unmatched falls back to a Material glyph rather than a wrong
/// picture.
abstract class ServiceIcons {
  static const String _dir = 'assets/icons';

  static const List<(Object icon, List<String> keywords)> _rules = [
    // Food
    ('temaki_catering', ['baker', 'bake', 'cake', 'tiffin', 'biryani', 'chef', 'food', 'meal',
      'snack', 'dessert', 'caterer', 'catering', 'cook']),
    // Teaching
    ('tabler_tax', ['tax', 'gst', 'ca ', 'chartered']),
    ('mingcute_music-fill', ['music', 'sing', 'guitar', 'piano', 'keyboard', 'violin', 'drum']),
    ('mdi_dance-ballroom', ['dance', 'choreograph', 'zumba']),
    ('si_book-duotone', ['tutor', 'teacher', 'teaching', 'handwriting', 'coaching', 'academic',
      'tuition', 'school']),
    // Beauty (before 'art' so 'nail art' / 'tattoo artist' don't fall through to paint). The
    // salon PNG is scissors and a comb, so it's for hair only: every Beautician type used to
    // share it, "Beauty service provider" and "Hair stylist" included (BUG-088). Stopgap
    // glyphs until the Figma icons arrive.
    ('temaki_beauty-salon', ['hair', 'barber', 'salon']),
    (Icons.front_hand, ['nail']),
    (Icons.back_hand, ['mehendi', 'mehandi', 'henna']),
    (Icons.draw, ['tattoo']),
    (Icons.brush, ['make up', 'makeup']),
    (Icons.face_retouching_natural, ['beaut', 'spa', 'grooming']),
    // Art & design
    ('mdi_paint', ['art', 'craft', 'paint', 'interior', 'architect', 'design', 'decor']),
    // Sports & wellness
    ('material-symbols_sports-cricket', ['sport', 'cricket', 'skating', 'badminton', 'swim',
      'table tennis', 'football', 'gymnast', 'karate', 'taekwondo', 'mma', 'fitness', 'gym',
      'trainer']),
    ('hugeicons_yoga-02', ['yoga', 'wellness', 'healing', 'counselor', 'counsellor', 'dietician',
      'dietitian', 'panchakarma', 'meditat', 'therap']),
    // Events
    ('material-symbols_candle', ['party', 'birthday', 'wedding', 'event', 'organiser', 'organizer',
      'planner', 'decoration']),
    // Professional
    ('mdi_account-tie', ['doctor', 'lawyer', 'dentist', 'physio', 'homeopath', 'ayurved',
      'professional', 'consultant', 'advocate']),
    ('material-symbols_finance-mode', ['invest', 'finance', 'mutual fund', 'insurance',
      'real estate', 'agent', 'account', 'audit', 'wealth']),
    // Making things
    ('game-icons_sewing-string', ['tailor', 'stitch', 'sewing', 'alteration', 'boutique',
      'garment', 'fashion', 'jewellery', 'jewelry', 'embroider']),
    // Care
    ('icon-park-twotone_baby', ['baby', 'infant', 'nanny', 'creche', 'child care',
      'childcare', 'day care', 'daycare']),
    ('streamline-plump_pet-paw-solid', ['pet', 'dog', 'cat ', 'grooming', 'veterinar']),
  ];

  /// The icon for [serviceName]: a brand PNG's asset path ([String]), a Material glyph
  /// ([IconData]), or null when no rule fits.
  static Object? lookup(String? serviceName) {
    final name = serviceName?.trim().toLowerCase();
    if (name == null || name.isEmpty) return null;
    for (final (icon, keywords) in _rules) {
      for (final k in keywords) {
        if (name.contains(k)) return icon is String ? '$_dir/$icon.png' : icon;
      }
    }
    return null;
  }

  /// Asset path for [serviceName], or null when its icon isn't a brand PNG.
  static String? assetFor(String? serviceName) => switch (lookup(serviceName)) {
        final String asset => asset,
        _ => null,
      };

  /// Material fallback for names the icon set doesn't cover.
  static const IconData fallback = Icons.handyman_outlined;
}

/// Renders the brand PNG for a service, falling back to a Material glyph.
///
/// The supplied PNGs are flat single-tone silhouettes, so `srcIn` recolours them
/// cleanly to [color] and they sit alongside Material icons without looking pasted in.
class ServiceIcon extends StatelessWidget {
  const ServiceIcon({super.key, required this.serviceName, this.size = 28, required this.color});

  final String? serviceName;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final icon = ServiceIcons.lookup(serviceName);
    if (icon is IconData) return Icon(icon, size: size, color: color);
    final asset = icon is String ? icon : null;
    if (asset == null) return Icon(ServiceIcons.fallback, size: size, color: color);
    return Image.asset(
      asset,
      width: size,
      height: size,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => Icon(ServiceIcons.fallback, size: size, color: color),
    );
  }
}
