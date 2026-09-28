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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(_page > 0 ? 'Members ($_total)' : 'Members')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search members by name',
                prefixIcon: Icon(Icons.search, color: AppColors.textMuted),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _scopes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ChoiceChip(
                label: Text(_labels[i]),
                selected: _scope == _scopes[i],
                selectedColor: AppColors.primarySurface,
                onSelected: (_) {
                  if (_scope == _scopes[i]) return;
                  _scope = _scopes[i];
                  _reload();
                },
              ),
            ),
          ),
          const SizedBox(height: 4),
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
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.divider),
        itemBuilder: (_, i) {
          if (i >= _items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
            );
          }
          final m = _items[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: Avatar(name: m.name, photoUrl: m.photoUrl),
            title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: m.subtitle.isEmpty ? null : Text(m.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: m.isServiceProvider
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Provider',
                        style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                  )
                : null,
            onTap: () => _open(m),
          );
        },
      ),
    );
  }
}
