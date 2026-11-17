import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/push_guard.dart';
import '../../../core/theme/app_colors.dart';
import '../../discovery/presentation/service_provider_detail_screen.dart';
import '../../discovery/presentation/user_profile_screen.dart';
import '../../home/presentation/widgets/home_widgets.dart';
import '../data/members_repository.dart';

/// The members behind Home's "Members" tile: searchable, scoped like Home (My Society /
/// Lane / Area / City), paged as you scroll. Opens with the scope Home was showing.
/// Laid out as the Figma's "All members nearby" page (BUG-079).
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key, this.initialScope = 'city', this.areaId});

  final String initialScope;

  /// An area picked on Home's location selector, carried over.
  final int? areaId;

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  static const _scopes = ['society', 'lane', 'area', 'city'];
  static const _labels = ['My Society', 'Lane', 'Area', 'City'];
  static const _pageSize = 30;

  late String _scope = _scopes.contains(widget.initialScope) ? widget.initialScope : 'city';
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  final _items = <MemberItem>[];
  int _total = 0;
  int _page = 0;
  bool _loading = false;
  String? _error;

  /// Bumped per reload so a slow response for an old query can't land in a new one.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadMore();
    });
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _hasMore => _items.length < _total;

  void _reload() {
    _generation++;
    setState(() {
      _items.clear();
      _total = 0;
      _page = 0;
      _error = null;
      _loading = false;
    });
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || (_page > 0 && !_hasMore)) return;
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final page = await ref.read(membersRepositoryProvider).list(
            scope: _scope,
            // A picked area only means something at area level and below.
            areaId: _scope == 'city' ? null : widget.areaId,
            q: _search.text,
            page: _page + 1,
            pageSize: _pageSize,
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _total = page.total;
        _page++;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _reload);
  }

  void _open(MemberItem m) => context.pushPage(MaterialPageRoute(
        builder: (_) => m.isServiceProvider
            ? ServiceProviderDetailScreen(id: m.profileId)
            : UserProfileScreen(id: m.profileId),
      ));

  Future<void> _pickScope() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text('Show members in',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
            ),
            for (var i = 0; i < _scopes.length; i++)
              ListTile(
                title: Text(_labels[i]),
                trailing: _scope == _scopes[i] ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                onTap: () => Navigator.of(sheet).pop(_scopes[i]),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == _scope || !mounted) return;
    _scope = picked;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final label = _labels[_scopes.indexOf(_scope)];
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(controller: _search, onQuery: _onSearch),
          // "Members in Area (12) ▾", like Home's section headers: the dropdown picks the scope.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _pickScope,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Row(
                children: [
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 17),
                        children: [
                          const TextSpan(text: 'Members in '),
                          TextSpan(text: label, style: const TextStyle(color: AppColors.primary)),
                          if (_page > 0) TextSpan(text: ' ($_total)', style: const TextStyle(color: AppColors.primary)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down, color: AppColors.primary, size: 22),
                ],
              ),
            ),
          ),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _list() {
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
            TextButton(onPressed: _reload, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Center(
              child: Text(
                _search.text.trim().isEmpty ? 'No members here yet.' : 'No members match "${_search.text.trim()}".',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            );
    }
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          if (i >= _items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
            );
          }
          final m = _items[i];
          return _MemberCard(key: ValueKey('member-${m.profileId}'), member: m, onTap: () => _open(m));
        },
      ),
    );
  }
}

/// Green header with the title and a white search pill (Figma: "All members nearby").
class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onQuery});
  final TextEditingController controller;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, topPad + 12, 16, 18),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.chevron_left, color: Colors.white, size: 28),
                ),
              ),
              const Expanded(
                child: Text('All members nearby',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                const Icon(Icons.search, color: AppColors.ink, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onQuery,
                    textInputAction: TextInputAction.search,
                    cursorColor: AppColors.primary,
                    style: const TextStyle(fontSize: 15, color: AppColors.ink),
                    // Transparent so the whole white pill is the field (see the Services header).
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: 'Search members by name',
                      hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 15),
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: controller,
                  builder: (_, _) => controller.text.isEmpty
                      ? const SizedBox.shrink()
                      : GestureDetector(
                          onTap: () {
                            controller.clear();
                            onQuery('');
                          },
                          child: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One member: photo, name, role, area, and a "Welcome" for anyone who joined recently.
class _MemberCard extends StatelessWidget {
  const _MemberCard({super.key, required this.member, required this.onTap});
  final MemberItem member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final role = m.roleLabel?.trim() ?? '';
    final area = m.areaName?.trim() ?? '';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Avatar(name: m.name, photoUrl: m.photoUrl, radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.ink)),
                    if (role.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(role,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    ],
                    if (area.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(area,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ],
                ),
              ),
              if (m.isNew) ...[
                const SizedBox(width: 8),
                const Text('Welcome 🎉',
                    style: TextStyle(
                        fontSize: 14, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600, color: AppColors.ink)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
