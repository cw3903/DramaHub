import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../models/drama.dart';

// ── isolate용 top-level 파싱 함수 ─────────────────────────────────────────────

/// compute()가 보내는 결과 타입 (record)
typedef _ParseResult = ({List<DramaItem> items, Map<String, DramaDetailData> extra});

/// JSON 문자열 → DramaItem 목록 + extra 맵. 별도 isolate에서 실행.
_ParseResult _parseDramasIsolate(String json) {
  final decoded = jsonDecode(json);
  final List<dynamic> dramas = decoded is List<dynamic>
      ? decoded
      : (decoded is Map<String, dynamic>
          ? (decoded['dramas'] as List<dynamic>? ?? [])
          : []);

  final items = <DramaItem>[];
  final extra = <String, DramaDetailData>{};

  for (final raw in dramas) {
    final map = raw as Map<String, dynamic>;
    final id = map['id']?.toString() ?? '';
    if (id.isEmpty) continue;

    final title_ko = (map['title_ko']?.toString().trim().isNotEmpty == true)
        ? map['title_ko'].toString().trim()
        : map['title']?.toString().trim() ?? '';
    final title_en = map['title_en']?.toString().trim() ?? '';
    final title_ja = map['title_ja']?.toString().trim() ?? '';
    if (title_ko.isEmpty && title_en.isEmpty && title_ja.isEmpty) continue;

    final genre_ko = (map['genre_ko']?.toString().trim().isNotEmpty == true)
        ? map['genre_ko'].toString().trim()
        : map['genre']?.toString().trim() ?? '';
    final genre_en = map['genre_en']?.toString().trim() ?? '';
    final genre_ja = map['genre_ja']?.toString().trim() ?? '';

    final imgKo = map['thumbnailImageUrl_ko']?.toString().trim() ?? '';
    final imgEn = map['thumbnailImageUrl_en']?.toString().trim() ?? '';
    final imgJa = map['thumbnailImageUrl_ja']?.toString().trim() ?? '';
    final imgDefault = (map['thumbnailImageUrl']?.toString().trim().isNotEmpty == true)
        ? map['thumbnailImageUrl'].toString().trim()
        : (map['imageUrl']?.toString().trim().isNotEmpty == true)
            ? map['imageUrl'].toString().trim()
            : '';
    final defaultImageUrl = imgKo.isNotEmpty
        ? imgKo
        : (imgDefault.isNotEmpty ? imgDefault : (imgEn.isNotEmpty ? imgEn : imgJa));

    final synopsis_ko = (map['synopsis_ko']?.toString().trim().isNotEmpty == true)
        ? map['synopsis_ko'].toString().trim()
        : (map['description_ko']?.toString().trim().isNotEmpty == true)
            ? map['description_ko'].toString().trim()
            : map['description']?.toString().trim() ?? '';
    final synopsis_en = (map['synopsis_en']?.toString().trim().isNotEmpty == true)
        ? map['synopsis_en'].toString().trim()
        : map['description_en']?.toString().trim() ?? '';
    final synopsis_ja = (map['synopsis_ja']?.toString().trim().isNotEmpty == true)
        ? map['synopsis_ja'].toString().trim()
        : map['description_ja']?.toString().trim() ?? '';
    final displaySynopsis = synopsis_ko.isNotEmpty
        ? synopsis_ko
        : (synopsis_en.isNotEmpty ? synopsis_en : synopsis_ja);

    final episodes = _parseEpisodesIsolate(map['episodes'] ?? map['episode_count']);
    final releaseDate = _parseReleaseDateIsolate(map);
    final cast = _parseCastIsolate(map['cast']) ??
        _parseCastIsolate(map['cast_en']) ??
        _parseCastIsolate(map['cast_ko']) ??
        <String>[];

    items.add(DramaItem(
      id: id,
      title: title_ko.isNotEmpty ? title_ko : title_en,
      subtitle: genre_ko.isNotEmpty ? genre_ko : genre_en,
      views: '0',
      rating: 0,
      isPopular: false,
      isNew: false,
      imageUrl: defaultImageUrl.isNotEmpty ? defaultImageUrl : null,
    ));

    extra[id] = DramaDetailData(
      synopsis: displaySynopsis,
      genre: genre_ko.isNotEmpty ? genre_ko : genre_en,
      episodes: episodes,
      cast: List<String>.from(cast),
      title_ko: title_ko.isNotEmpty ? title_ko : null,
      title_en: title_en.isNotEmpty ? title_en : null,
      title_ja: title_ja.isNotEmpty ? title_ja : null,
      genre_ko: genre_ko.isNotEmpty ? genre_ko : null,
      genre_en: genre_en.isNotEmpty ? genre_en : null,
      genre_ja: genre_ja.isNotEmpty ? genre_ja : null,
      synopsis_ko: synopsis_ko.isNotEmpty ? synopsis_ko : null,
      synopsis_en: synopsis_en.isNotEmpty ? synopsis_en : null,
      synopsis_ja: synopsis_ja.isNotEmpty ? synopsis_ja : null,
      imageUrl_ko: imgKo.isNotEmpty ? imgKo : (imgDefault.isNotEmpty ? imgDefault : null),
      imageUrl_en: imgEn.isNotEmpty ? imgEn : (imgDefault.isNotEmpty ? imgDefault : null),
      imageUrl_ja: imgJa.isNotEmpty ? imgJa : (imgDefault.isNotEmpty ? imgDefault : null),
      cast_ko: null,
      cast_en: null,
      releaseDate: releaseDate,
    );
  }

  return (items: items, extra: extra);
}

DateTime? _parseReleaseDateIsolate(Map<String, dynamic> map) {
  // 소스별 필드 우선 (Vigloo > Dramabox > ReelShort), 없으면 레거시
  final raw = map['release_date_vigloo'] ?? map['release_date_dramabox'] ?? map['release_date_reelshort'] ?? map['release_date'] ?? map['released_at'] ?? map['releaseDate'] ?? map['year'];
  if (raw == null) return null;
  if (raw is num) {
    final y = raw.toInt();
    if (y > 1900 && y < 2100) return DateTime(y, 1, 1);
    return null;
  }
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  final parsed = DateTime.tryParse(s);
  if (parsed != null) return parsed;
  final y = int.tryParse(s);
  if (y != null && y > 1900 && y < 2100) return DateTime(y, 1, 1);
  return null;
}

List<String>? _parseCastIsolate(dynamic value) {
  if (value == null) return null;
  if (value is List) {
    return value.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
  }
  if (value is String) {
    return value.isEmpty
        ? <String>[]
        : value.split(',').map((e) => e.trim()).where((s) => s.isNotEmpty).toList();
  }
  return null;
}

List<DramaEpisode> _parseEpisodesIsolate(dynamic value) {
  if (value == null) {
    return List.generate(12, (i) => DramaEpisode(number: i + 1, title: '${i + 1}화', duration: '45분'));
  }
  if (value is num) {
    final n = value.toInt();
    if (n <= 0) return [];
    return List.generate(n, (i) => DramaEpisode(number: i + 1, title: '${i + 1}화', duration: '45분'));
  }
  if (value is String) {
    final n = int.tryParse(value.trim());
    if (n != null && n > 0) {
      return List.generate(n, (i) => DramaEpisode(number: i + 1, title: '${i + 1}화', duration: '45분'));
    }
  }
  if (value is List) {
    return value.asMap().entries.map((e) {
      final v = e.value;
      if (v is Map) {
        final epNum = (v['number'] as num?)?.toInt() ?? (e.key + 1);
        final title = v['title']?.toString() ?? '${epNum}화';
        return DramaEpisode(number: epNum, title: title, duration: '45분');
      }
      return DramaEpisode(number: e.key + 1, title: '${e.key + 1}화', duration: '45분');
    }).toList();
  }
  return List.generate(12, (i) => DramaEpisode(number: i + 1, title: '${i + 1}화', duration: '45분'));
}

/// JSON에서 로드한 드라마별 상세 데이터 + 언어별 제목·장르·시놉시스·이미지 URL
class DramaDetailData {
  const DramaDetailData({
    required this.synopsis,
    required this.genre,
    required this.episodes,
    required this.cast,
    this.title_ko,
    this.title_en,
    this.title_ja,
    this.genre_ko,
    this.genre_en,
    this.genre_ja,
    this.synopsis_ko,
    this.synopsis_en,
    this.synopsis_ja,
  this.imageUrl_ko,
  this.imageUrl_en,
  this.imageUrl_ja,
  this.cast_ko,
  this.cast_en,
  this.releaseDate,
  });
  final String synopsis;
  final String genre;
  final List<DramaEpisode> episodes;
  final List<String> cast;
  final String? title_ko;
  final String? title_en;
  final String? title_ja;
  final String? genre_ko;
  final String? genre_en;
  final String? genre_ja;
  final String? synopsis_ko;
  final String? synopsis_en;
  final String? synopsis_ja;
  /// 국가별 썸네일 이미지 URL
  final String? imageUrl_ko;
  final String? imageUrl_en;
  final String? imageUrl_ja;
  final List<String>? cast_ko;
  final List<String>? cast_en;
  /// 공개/출시일 (최신순 정렬용). JSON에 release_date, released_at, year 등 있으면 파싱.
  final DateTime? releaseDate;
}

/// assets/data/dramas.json 로드.
/// vigloo 포맷: id(숫자), title(한국어), title_en, title_ja,
///   genre(한국어), genre_en, genre_ja,
///   thumbnailImageUrl / thumbnailImageUrl_ko / thumbnailImageUrl_en / thumbnailImageUrl_ja,
///   description(한국어), description_en, description_ja, episode_count
class DramaListService {
  DramaListService._();
  static final DramaListService instance = DramaListService._();

  static const String _assetPath = 'assets/data/dramas.json';

  final ValueNotifier<List<DramaItem>> listNotifier = ValueNotifier<List<DramaItem>>([]);
  final ValueNotifier<Map<String, DramaDetailData>> extraNotifier = ValueNotifier<Map<String, DramaDetailData>>({});

  List<DramaItem> get list => listNotifier.value;
  Map<String, DramaDetailData> get extraById => extraNotifier.value;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// JSON 로드. rootBundle은 main isolate에서만 접근 가능하므로 문자열 로드 후
  /// compute()로 별도 isolate에서 파싱해 첫 프레임 드롭 방지.
  Future<void> loadFromAsset() async {
    if (_loaded) return;
    try {
      final json = await rootBundle.loadString(_assetPath);
      // 무거운 파싱(8,000+ 항목)을 별도 isolate에서 처리
      final result = await compute(_parseDramasIsolate, json);
      listNotifier.value = result.items;
      extraNotifier.value = result.extra;
      _loaded = true;
      debugPrint('DramaListService: ${result.items.length}편 로드됨');
    } catch (e, st) {
      debugPrint('DramaListService loadFromAsset error: $e');
      debugPrint('$st');
      listNotifier.value = [];
      extraNotifier.value = {};
      _loaded = true;
    }
  }

  DramaDetailData? getExtra(String id) => extraNotifier.value[id];

  /// 가입 국가에 따라 표시할 제목.
  /// kr → 한국어, jp → 일본어, us 등 → 영어.
  /// country가 null이면 한국어 우선.
  String getDisplayTitle(String id, String? country) {
    final extra = extraNotifier.value[id];
    if (extra == null) return '';
    final c = country?.toLowerCase();
    if (c == 'kr') return extra.title_ko ?? extra.title_en ?? extra.title_ja ?? '';
    if (c == 'jp') return extra.title_ja ?? extra.title_en ?? extra.title_ko ?? '';
    if (c != null) return extra.title_en ?? extra.title_ko ?? extra.title_ja ?? '';
    // country 미로드: 한국어 우선
    return extra.title_ko ?? extra.title_en ?? extra.title_ja ?? '';
  }

  /// 가입 국가에 따라 표시할 장르(부제).
  String getDisplaySubtitle(String id, String? country) {
    final extra = extraNotifier.value[id];
    if (extra == null) return '';
    final c = country?.toLowerCase();
    if (c == 'kr') return extra.genre_ko ?? extra.genre_en ?? extra.genre_ja ?? extra.genre;
    if (c == 'jp') return extra.genre_ja ?? extra.genre_en ?? extra.genre_ko ?? extra.genre;
    if (c != null) return extra.genre_en ?? extra.genre_ko ?? extra.genre_ja ?? extra.genre;
    return extra.genre_ko ?? extra.genre_en ?? extra.genre_ja ?? extra.genre;
  }

  /// 가입 국가에 따라 목록 필터: 해당 언어 정보가 있는 편만 반환.
  /// kr → title_ko 있는 편만, jp → title_ja 있는 편만, 그 외(미국 등) → title_en 있는 편만.
  /// country가 null이면 한국어(title_ko) 있는 편만.
  List<DramaItem> getListForCountry(String? country) {
    final c = country?.toLowerCase();
    final extraById = extraNotifier.value;
    return listNotifier.value.where((item) {
      final ex = extraById[item.id];
      if (ex == null) return false;
      if (c == 'kr') return (ex.title_ko ?? '').trim().isNotEmpty;
      if (c == 'jp') return (ex.title_ja ?? '').trim().isNotEmpty;
      return (ex.title_en ?? '').trim().isNotEmpty;
    }).toList();
  }

  /// getListForCountry + releaseDate 기준 최신순 정렬 (null은 맨 뒤).
  List<DramaItem> getListForCountrySortedByReleaseDate(String? country) {
    final list = getListForCountry(country);
    final extraById = extraNotifier.value;
    list.sort((a, b) {
      final da = extraById[a.id]?.releaseDate;
      final db = extraById[b.id]?.releaseDate;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return list;
  }

  /// 가입 국가에 따라 표시할 줄거리.
  /// kr → 한국어, jp → 일본어, 그 외 → 영어. country가 null이면 한국어 우선.
  String getDisplaySynopsis(String id, String? country) {
    final extra = extraNotifier.value[id];
    if (extra == null) return '';
    final c = country?.toLowerCase();
    if (c == 'kr') return extra.synopsis_ko ?? extra.synopsis_en ?? extra.synopsis_ja ?? extra.synopsis;
    if (c == 'jp') return extra.synopsis_ja ?? extra.synopsis_en ?? extra.synopsis_ko ?? extra.synopsis;
    if (c != null) return extra.synopsis_en ?? extra.synopsis_ko ?? extra.synopsis_ja ?? extra.synopsis;
    return extra.synopsis_ko ?? extra.synopsis_en ?? extra.synopsis_ja ?? extra.synopsis;
  }

  /// 가입 국가에 따라 표시할 썸네일 이미지 URL.
  /// kr → 한국어 썸네일, jp → 일본어 썸네일, 그 외 → 영어 썸네일.
  String? getDisplayImageUrl(String id, String? country) {
    final extra = extraNotifier.value[id];
    if (extra == null) return null;
    final c = country?.toLowerCase();
    if (c == 'kr') return extra.imageUrl_ko ?? extra.imageUrl_en ?? extra.imageUrl_ja;
    if (c == 'jp') return extra.imageUrl_ja ?? extra.imageUrl_en ?? extra.imageUrl_ko;
    if (c != null) return extra.imageUrl_en ?? extra.imageUrl_ko ?? extra.imageUrl_ja;
    // country 미로드: 한국어 우선
    return extra.imageUrl_ko ?? extra.imageUrl_en ?? extra.imageUrl_ja;
  }

  /// 제목으로 드라마 썸네일 URL 조회 (내가 본 드라마 등에서 id 없을 때 사용).
  String? getDisplayImageUrlByTitle(String title, String? country) {
    if (title.trim().isEmpty) return null;
    final t = title.trim();
    for (final item in listNotifier.value) {
      if (getDisplayTitle(item.id, country) == t || item.title == t) {
        return getDisplayImageUrl(item.id, country);
      }
    }
    return null;
  }

  /// 제목(한국어 등)으로 드라마를 찾아 현재 언어의 표시 제목 반환.
  String getDisplayTitleByTitle(String title, String? country) {
    if (title.trim().isEmpty) return title;
    final t = title.trim();
    for (final item in listNotifier.value) {
      if (getDisplayTitle(item.id, country) == t || item.title == t) {
        return getDisplayTitle(item.id, country);
      }
    }
    return title;
  }

  /// 같은 장르(부제)를 가진 드라마 목록. [excludeId] 제외, 최대 [limit]개.
  /// [genreDisplay]는 getDisplaySubtitle으로 얻은 장르 문자열(예: "로맨스·반전·사이다").
  /// [maxScan]: 후보를 너무 많이 돌면 탭 지연이 커져 상한(기본 700)으로 자름.
  List<DramaItem> getSimilarByGenre(
    String excludeId,
    String genreDisplay,
    String? country, {
    int limit = 8,
    int maxScan = 700,
  }) {
    if (genreDisplay.trim().isEmpty) return [];
    final tags = genreDisplay.split(RegExp(r'[·,]')).map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toSet();
    if (tags.isEmpty) return [];
    final candidates = getListForCountry(country);
    final result = <DramaItem>[];
    var scanned = 0;
    for (final item in candidates) {
      if (item.id == excludeId) continue;
      if (result.length >= limit) break;
      if (scanned >= maxScan) break;
      scanned++;
      final otherGenre = getDisplaySubtitle(item.id, country);
      final otherTags = otherGenre.split(RegExp(r'[·,]')).map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty);
      if (otherTags.any((t) => tags.contains(t))) result.add(item);
    }
    return result;
  }

  /// 시놉시스 아래 장르·태그 토큰(예: "Twist", "반전")과 동일한 토큰이 부제에 포함된 작품만.
  /// [tag]는 상세에서 탭한 문자열과 동일(공백·대소문자 무시 후 토큰 단위 일치).
  List<DramaItem> getDramasMatchingGenreTag(
    String tag,
    String? country, {
    int limit = 200,
    int maxScan = 3000,
  }) {
    final needle = tag.trim().toLowerCase();
    if (needle.isEmpty) return [];
    final candidates = getListForCountry(country);
    final result = <DramaItem>[];
    var scanned = 0;
    for (final item in candidates) {
      if (result.length >= limit) break;
      if (scanned >= maxScan) break;
      scanned++;
      final otherGenre = getDisplaySubtitle(item.id, country);
      final otherTags = otherGenre
          .split(RegExp(r'[·,]'))
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty);
      if (otherTags.contains(needle)) result.add(item);
    }
    return result;
  }

  /// [item]에 대한 상세 정보 생성(비슷한 작품 탭 시 상세 페이지 진입용). 평점·리뷰는 페이지에서 로드.
  /// 비슷한 작품은 목록이 클 때 동기 전부 스캔하면 탭이 버벅이므로 비워 두고 상세 UI에서 지연 로드.
  DramaDetail buildDetailForItem(DramaItem item, String? country) {
    final extra = getExtra(item.id);
    final displayGenre = getDisplaySubtitle(item.id, country).isNotEmpty
        ? getDisplaySubtitle(item.id, country)
        : (extra?.genre ?? item.subtitle);
    final displaySynopsis = getDisplaySynopsis(item.id, country);
    final fallbackSynopsis = '${item.title}의 줄거리입니다.';
    final episodes = extra?.episodes ?? List.generate(12, (i) => DramaEpisode(number: i + 1, title: '에피소드 ${i + 1}', duration: '45분'));
    final cast = extra?.cast ?? const [];
    return DramaDetail(
      item: item,
      synopsis: displaySynopsis.isNotEmpty ? displaySynopsis : (extra?.synopsis ?? fallbackSynopsis),
      year: '2024',
      genre: displayGenre.isNotEmpty ? displayGenre : (extra?.genre ?? item.subtitle),
      averageRating: 0,
      ratingCount: 0,
      reviews: const [],
      episodes: episodes,
      similar: const [],
      cast: cast,
    );
  }
}
