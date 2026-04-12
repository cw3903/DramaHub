import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Mux 무료 플랜 에셋 한도(10개) 초과 시
class MuxAssetLimitException implements Exception {
  @override
  String toString() =>
      'Mux 무료 플랜은 에셋 10개까지입니다. dashboard.mux.com에서 기존 에셋을 삭제하거나 플랜을 업그레이드해 주세요.';
}

/// Mux 영상 스트리밍 서비스 (HLS)
/// 사용법:
///   1. dashboard.mux.com 에서 API Token 발급
///   2. 아래 _tokenId, _tokenSecret 을 실제 값으로 교체
///   3. 운영 서버로 가면 이 값들을 Firebase Cloud Functions 등 백엔드로 이전 권장
class MuxService {
  MuxService._();
  static final MuxService instance = MuxService._();

  // ★ Mux 대시보드에서 발급받은 값 (운영 시 백엔드로 이전 권장)
  static const String _tokenId = '166ec1c0-9d8a-4625-b320-42569cced60d';
  static const String _tokenSecret = 'vweJZ/O6yieEhdLI9h/Fjr8y+YAD9d9610rtzNI5lkkHgVNDqRA/RW4tvaAC1QPkGbNw0Pi2CQ6';

  String get _basicAuth =>
      'Basic ${base64Encode(utf8.encode('$_tokenId:$_tokenSecret'))}';

  static const String _apiBase = 'https://api.mux.com';

  // ─────────────────────────────────────────────
  // 1단계: 업로드 URL 발급
  // ─────────────────────────────────────────────
  Future<_MuxUpload> createUploadUrl() async {
    final response = await http.post(
      Uri.parse('$_apiBase/video/v1/uploads'),
      headers: {
        'Authorization': _basicAuth,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'new_asset_settings': {
          'playback_policy': ['public'],
          'mp4_support': 'none',
        },
        'cors_origin': '*',
      }),
    );
    if (response.statusCode != 201) {
      final body = response.body;
      if (response.statusCode == 400 && body.contains('10 assets') && body.contains('Free plan')) {
        throw MuxAssetLimitException();
      }
      throw Exception('Mux 업로드 URL 발급 실패 (${response.statusCode}): $body');
    }
    final data = jsonDecode(response.body)['data'] as Map<String, dynamic>;
    return _MuxUpload(
      uploadId: data['id'] as String,
      uploadUrl: data['url'] as String,
    );
  }

  // ─────────────────────────────────────────────
  // 2단계: 영상 파일을 Mux 업로드 URL로 PUT 전송 (스트리밍)
  // ─────────────────────────────────────────────
  Future<void> uploadFile(String uploadUrl, String filePath) async {
    final file = File(filePath);
    final fileSize = await file.length();

    final request = http.StreamedRequest('PUT', Uri.parse(uploadUrl))
      ..headers['Content-Type'] = 'video/mp4'
      ..headers['Content-Length'] = fileSize.toString()
      ..contentLength = fileSize;

    file.openRead().listen(
      request.sink.add,
      onDone: request.sink.close,
      onError: (e) => request.sink.addError(e),
    );

    final response = await http.Client().send(request);
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Mux 업로드 실패 (${response.statusCode})');
    }
  }

  // ─────────────────────────────────────────────
  // 3단계: asset_id 확인 → playback_id 즉시 반환
  // Mux는 에셋 생성 직후(preparing 단계)에도 playback_id를 발급하므로
  // ready 완료를 기다리지 않아도 됨. (HLS URL은 인코딩 진행 중에도 서서히 재생 가능)
  // ─────────────────────────────────────────────
  Future<String> waitForPlaybackId(
    String uploadId, {
    void Function(String status)? onStatus,
  }) async {
    // 업로드 처리 → asset_id 연결까지 최대 30초 대기
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(seconds: 2));

      final uploadRes = await http.get(
        Uri.parse('$_apiBase/video/v1/uploads/$uploadId'),
        headers: {'Authorization': _basicAuth},
      );
      if (uploadRes.statusCode != 200) continue;

      final uploadData =
          jsonDecode(uploadRes.body)['data'] as Map<String, dynamic>;
      final assetId = uploadData['asset_id'] as String?;
      onStatus?.call(uploadData['status'] as String? ?? 'waiting');

      if (assetId == null) continue;

      // asset_id 연결되면 → playback_id 즉시 가져오기 (ready 완료 불필요)
      final assetRes = await http.get(
        Uri.parse('$_apiBase/video/v1/assets/$assetId'),
        headers: {'Authorization': _basicAuth},
      );
      if (assetRes.statusCode != 200) continue;

      final assetData =
          jsonDecode(assetRes.body)['data'] as Map<String, dynamic>;
      final assetStatus = assetData['status'] as String?;
      if (assetStatus == 'errored') throw Exception('Mux 트랜스코딩 실패');

      final playbackIds = assetData['playback_ids'] as List?;
      if (playbackIds != null && playbackIds.isNotEmpty) {
        return playbackIds[0]['id'] as String;
      }
    }
    throw Exception('Mux asset_id 확인 타임아웃 (30초 초과)');
  }

  // ─────────────────────────────────────────────
  // URL 헬퍼
  // ─────────────────────────────────────────────

  /// HLS 스트리밍 URL (video_player 에서 바로 사용 가능)
  static String hlsUrl(String playbackId) =>
      'https://stream.mux.com/$playbackId.m3u8';

  /// 썸네일 URL (시간 지정 가능, 기본 0초)
  static String thumbnailUrl(String playbackId, {double timeSec = 0}) =>
      'https://image.mux.com/$playbackId/thumbnail.jpg?time=$timeSec&width=640';

  /// Mux 키가 설정되어 있는지 확인
  static bool get isConfigured =>
      _tokenId != 'YOUR_MUX_TOKEN_ID' &&
      _tokenSecret != 'YOUR_MUX_TOKEN_SECRET';

  // ─────────────────────────────────────────────
  // 통합 업로드 (압축 → Mux 업로드 → 완료 대기)
  // playbackId 를 반환. hlsUrl(), thumbnailUrl() 로 URL 생성 가능
  // ─────────────────────────────────────────────
  Future<String> uploadAndGetPlaybackId(
    String filePath, {
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('uploading');
    final upload = await createUploadUrl();
    await uploadFile(upload.uploadUrl, filePath);
    onStatus?.call('processing');
    final playbackId = await waitForPlaybackId(upload.uploadId, onStatus: onStatus);
    return playbackId;
  }
}

class _MuxUpload {
  const _MuxUpload({required this.uploadId, required this.uploadUrl});
  final String uploadId;
  final String uploadUrl;
}
