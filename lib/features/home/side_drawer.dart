import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../store/sumi_store.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';
import '../memory/user_model_page.dart';

class SideDrawer extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenMemory;
  final VoidCallback onOpenTools;
  final Future<void> Function(ChatSearchResult result) onOpenSearchResult;

  const SideDrawer({
    super.key,
    required this.isOpen,
    required this.onClose,
    required this.onOpenSettings,
    required this.onOpenMemory,
    required this.onOpenTools,
    required this.onOpenSearchResult,
  });

  @override
  State<SideDrawer> createState() => _SideDrawerState();
}

class _SideDrawerState extends State<SideDrawer> {
  static const _searchDelay = Duration(milliseconds: 250);

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _searchTimer;
  List<ChatSearchResult> _searchResults = const [];
  String _query = '';
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _searchTimer?.cancel();
    setState(() {
      _query = query;
      if (query.isEmpty) {
        _searchResults = const [];
        _isSearching = false;
      }
    });
    if (query.isEmpty) return;
    _searchTimer = Timer(_searchDelay, () => _search(query));
  }

  Future<void> _search(String query) async {
    if (!mounted || query != _searchController.text.trim()) return;
    final store = SumiScope.read(context);
    setState(() => _isSearching = true);
    List<ChatSearchResult> results;
    try {
      results = await store.searchUserMessages(query: query);
    } catch (_) {
      results = const [];
    }
    if (!mounted || query != _searchController.text.trim()) return;
    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.requestFocus();
  }

  Future<void> _openSearchResult(ChatSearchResult result) async {
    _searchFocusNode.unfocus();
    _searchTimer?.cancel();
    setState(() {
      _query = '';
      _searchResults = const [];
      _isSearching = false;
    });
    _searchController.clear();
    H.light();
    widget.onClose();
    await widget.onOpenSearchResult(result);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final drawerWidth = screenWidth * 5 / 6;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      left: widget.isOpen ? 0 : -drawerWidth,
      top: 0,
      bottom: 0,
      width: drawerWidth,
      child: Stack(
        children: [
          Material(
            color: Colors.white,
            child: Column(
              children: [
                _buildUserProfile(context),
                const Divider(height: 1),
                _buildSearchBox(),
                if (_query.isNotEmpty) _buildSearchResults(),
                _buildMemoryButton(),
                _buildToolsButton(),
                const Spacer(),
                _buildSettingsButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserProfile(BuildContext context) {
    final store = SumiScope.watchSettings(context);
    final userName = store.appSettings.userName;

    return Padding(
      padding: EdgeInsets.only(
        left: s16,
        right: s16,
        top: s16 + MediaQuery.of(context).padding.top,
        bottom: s16,
      ),
      child: Row(
          children: [
            GestureDetector(
              onTap: () {
                H.click();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const UserModelPage(),
                  ),
                );
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: primary100,
                  borderRadius: BorderRadius.circular(radiusPill),
                ),
                child: const Icon(Icons.person, size: 24, color: primary500),
              ),
            ),
          const SizedBox(width: s12),
          Expanded(
            child: InkWell(
              onTap: () => _editUserName(context, store),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName.isEmpty ? '点击设置昵称' : userName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: s12, vertical: s8),
        child: InkWell(
          onTap: () {
            H.click();
            widget.onOpenSettings();
          },
          borderRadius: BorderRadius.circular(radius12),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: s12, vertical: s12),
            child: Row(
              children: [
                Icon(Icons.tune, size: 24, color: textTertiary),
                SizedBox(width: s12),
                Text(
                  '设置',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMemoryButton() => Padding(
    padding: const EdgeInsets.fromLTRB(s12, s12, s12, 0),
    child: InkWell(
      onTap: () {
        H.click();
        widget.onOpenMemory();
      },
      borderRadius: BorderRadius.circular(radius12),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: s12, vertical: s12),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, size: 24, color: primary500),
            SizedBox(width: s12),
            Text(
              '记忆',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildToolsButton() => Padding(
    padding: const EdgeInsets.fromLTRB(s12, s4, s12, 0),
    child: InkWell(
      onTap: () {
        H.click();
        widget.onOpenTools();
      },
      borderRadius: BorderRadius.circular(radius12),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: s12, vertical: s12),
        child: Row(
          children: [
            Icon(Icons.handyman_outlined, size: 24, color: primary500),
            SizedBox(width: s12),
            Text(
              '工具',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildSearchBox() => Padding(
    padding: const EdgeInsets.fromLTRB(s12, s12, s12, 0),
    child: TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      textInputAction: TextInputAction.search,
      onTapOutside: (_) => _searchFocusNode.unfocus(),
      onSubmitted: (query) {
        _searchTimer?.cancel();
        _search(query.trim());
      },
      decoration: InputDecoration(
        hintText: '搜索历史消息',
        prefixIcon: const Icon(Icons.search, size: iconMedium),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: '清除搜索',
                onPressed: _clearSearch,
                icon: const Icon(Icons.close, size: iconMedium),
              ),
        filled: true,
        fillColor: surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(vertical: s10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius12),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius12),
          borderSide: const BorderSide(color: line),
        ),
      ),
    ),
  );

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(s24, s12, s24, s4),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_searchResults.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(s24, s12, s24, s4),
        child: Text(
          '没有匹配的历史消息',
          style: TextStyle(fontSize: 13, color: textTertiary),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(s12, s8, s12, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius8),
            border: Border.all(color: line),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: _searchResults.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final result = _searchResults[index];
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: s12),
                title: _buildHighlightedExcerpt(result.content),
                subtitle: Text(
                  _formatResultDate(result),
                  style: const TextStyle(fontSize: 11, color: textTertiary),
                ),
                onTap: () => _openSearchResult(result),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedExcerpt(String content) {
    final lowerContent = content.toLowerCase();
    final lowerQuery = _query.toLowerCase();
    final match = lowerContent.indexOf(lowerQuery);
    if (match < 0) {
      return Text(
        content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, color: ink),
      );
    }

    const maxLength = 96;
    final start = (match - 28).clamp(0, content.length).toInt();
    final end = (start + maxLength).clamp(0, content.length).toInt();
    final excerpt = content.substring(start, end);
    final excerptMatch = match - start;
    final matchEnd = (excerptMatch + _query.length).clamp(0, excerpt.length);
    return Text.rich(
      TextSpan(
        children: [
          if (start > 0) const TextSpan(text: '...'),
          TextSpan(text: excerpt.substring(0, excerptMatch)),
          TextSpan(
            text: excerpt.substring(excerptMatch, matchEnd),
            style: const TextStyle(
              color: primary600,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: excerpt.substring(matchEnd)),
          if (end < content.length) const TextSpan(text: '...'),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, color: ink, height: 1.35),
    );
  }

  String _formatResultDate(ChatSearchResult result) =>
      '${result.date.month}/${result.date.day} · ${result.createdAt.hour.toString().padLeft(2, '0')}:${result.createdAt.minute.toString().padLeft(2, '0')}';

  void _editUserName(BuildContext context, SumiStore store) {
    final controller = TextEditingController(text: store.appSettings.userName);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radiusCard)),
          ),
          title: const Text(
            '设置昵称',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '输入你的昵称'),
            maxLength: 6,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                store.updateUserName(controller.text.trim());
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    ).then((_) => controller.dispose());
  }
}
