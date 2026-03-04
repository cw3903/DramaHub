import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _keyBlockedAuthors = 'blocked_authors';
const String _keyBlockedPostIds = 'blocked_post_ids';

/// 차단한 작성자(author) + 차단한 글(postId) 목록. 로컬 저장, 피드에서 숨김.
class BlockService extends ChangeNotifier {
  BlockService._();
  static final BlockService instance = BlockService._();

  Set<String> _blocked = {};
  Set<String> _blockedPostIds = {};
  bool _loaded = false;

  Set<String> get blockedAuthorIds => Set.unmodifiable(_blocked);
  bool get isLoaded => _loaded;

  bool isBlocked(String authorId) {
    if (authorId.isEmpty) return false;
    return _blocked.contains(authorId);
  }

  /// 글 하나 차단 여부 (해당 글을 피드에서 숨김)
  bool isPostBlocked(String postId) {
    if (postId.isEmpty) return false;
    return _blockedPostIds.contains(postId);
  }

  /// 초기 로드 (CommunityScreen 등에서 호출)
  Future<void> ensureLoaded() async => _ensureLoaded();

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyBlockedAuthors);
    _blocked = list != null ? Set.from(list) : {};
    final postList = prefs.getStringList(_keyBlockedPostIds);
    _blockedPostIds = postList != null ? Set.from(postList) : {};
    _loaded = true;
    notifyListeners();
  }

  /// 작성자 차단 (예: post.author)
  Future<void> block(String authorId) async {
    if (authorId.isEmpty) return;
    await _ensureLoaded();
    _blocked.add(authorId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyBlockedAuthors, _blocked.toList());
    notifyListeners();
  }

  /// 글 차단 (해당 글만 피드에서 숨김, 작성자는 차단하지 않음)
  Future<void> blockPost(String postId) async {
    if (postId.isEmpty) return;
    await _ensureLoaded();
    _blockedPostIds.add(postId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyBlockedPostIds, _blockedPostIds.toList());
    notifyListeners();
  }

  /// 차단 해제
  Future<void> unblock(String authorId) async {
    await _ensureLoaded();
    _blocked.remove(authorId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyBlockedAuthors, _blocked.toList());
    notifyListeners();
  }
}
