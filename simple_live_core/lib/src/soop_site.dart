import 'package:simple_live_core/src/common/http_client.dart';

import 'interface/live_site.dart';
import 'model/live_category.dart';
import 'model/live_category_result.dart';
import 'model/live_play_quality.dart';
import 'model/live_play_url.dart';
import 'model/live_room_detail.dart';
import 'model/live_room_item.dart';

class SoopSite extends LiveSite {
  @override
  String id = "soop";

  @override
  String name = "SOOP";

  static String globalCookie = "";

  String cookie = "";

  static const String _playHost = 'https://play.sooplive.com';
  static const String _liveListUrl =
      'https://live.sooplive.com/api/main_broad_list_api.php';
  static const String _playerApiUrl =
      'https://live.sooplive.com/afreeca/player_live_api.php';

  Map<String, String> get _headers => {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/120.0.0.0 Safari/537.36',
        'Origin': _playHost,
        'Referer': '$_playHost/',
        if (_requestCookie.isNotEmpty) 'Cookie': _requestCookie,
      };

  String get _requestCookie => cookie.isNotEmpty ? cookie : globalCookie;

  Map<String, dynamic> _toStringKeyMap(dynamic value) {
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return {};
  }

  Future<Map<String, dynamic>> _postPlayerApi(
    Map<String, String> data, {
    String? referer,
  }) async {
    final jsonRes = _toStringKeyMap(await HttpClient.instance.postJson(
      _playerApiUrl,
      header: {
        ..._headers,
        if (referer != null) 'Referer': referer,
      },
      data: data,
      formUrlEncoded: true,
    ));
    final channel = jsonRes['CHANNEL'];
    if (channel is Map) {
      return _toStringKeyMap(channel);
    }
    return {
      'RESULT': jsonRes['RESULT'] ?? -1,
      'ERROR': channel?.toString() ?? jsonRes.toString(),
    };
  }

  Future<String> _getCurrentBno(String bid) async {
    try {
      final html = await HttpClient.instance.getText(
        '$_playHost/$bid',
        header: _headers,
      );
      final patterns = [
        RegExp(r'nBroadNo\s*[=:]\s*[\"\']?(\d+)', caseSensitive: false),
        RegExp(r'broad_no[\"\']?\s*[:=]\s*[\"\']?(\d+)', caseSensitive: false),
        RegExp(r'BNO[\"\']?\s*[:=]\s*[\"\']?(\d+)', caseSensitive: false),
        RegExp(r'bno[\"\']?\s*[:=]\s*[\"\']?(\d+)', caseSensitive: false),
      ];
      for (final pattern in patterns) {
        final match = pattern.firstMatch(html);
        final bno = match?.group(1) ?? '';
        if (bno.isNotEmpty) {
          return bno;
        }
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  Future<Map<String, dynamic>> _getLiveInfo(String roomId) async {
    final parts = roomId.split('/');
    final bid = parts.first;
    final bno = parts.length > 1 ? parts[1] : await _getCurrentBno(bid);
    return _postPlayerApi({
      'from_api': '0',
      'mode': 'landing',
      'player_type': 'html5',
      'stream_type': 'common',
      'type': 'live',
      'bid': bid,
      'bno': bno,
      'pwd': '',
    }, referer: '$_playHost/$roomId');
  }

  String _normalizeImageUrl(dynamic url) {
    final value = url?.toString() ?? '';
    if (value.startsWith('//')) return 'https:$value';
    return value;
  }

  LiveRoomItem _toRoomItem(Map<String, dynamic> item) {
    final bid = item['user_id']?.toString() ?? '';
    final bno = item['broad_no']?.toString() ?? '';
    return LiveRoomItem(
      roomId: bno.isNotEmpty ? '$bid/$bno' : bid,
      title: item['broad_title']?.toString() ?? '',
      userName: item['user_nick']?.toString() ?? bid,
      cover: _normalizeImageUrl(item['broad_thumb'] ?? item['broad_img']),
      online: int.tryParse(
            (item['current_view_cnt'] ?? item['pc_view_cnt'] ?? '0')
                .toString(),
          ) ??
          0,
    );
  }

  @override
  Future<List<LiveCategory>> getCategores() async {
    return [
      LiveCategory(
        id: 'all',
        name: '热门直播',
        children: [
          LiveSubCategory(id: 'all', name: '全部', parentId: 'all'),
          LiveSubCategory(id: '00040000', name: '游戏', parentId: 'all'),
          LiveSubCategory(id: '00130000', name: '聊天', parentId: 'all'),
          LiveSubCategory(id: '00030000', name: '体育', parentId: 'all'),
          LiveSubCategory(id: '00010000', name: '娱乐', parentId: 'all'),
        ],
      ),
    ];
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    return getCategoryRooms(
      LiveSubCategory(id: 'all', name: '全部', parentId: 'all'),
      page: page,
    );
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    final query = {
      'selectType': category.id == 'all' ? 'action' : 'cate',
      'selectValue': category.id == 'all' ? 'all' : category.id,
      'orderType': 'view_cnt',
      'pageNo': page.toString(),
      'lang': 'ko_KR',
    };
    final jsonRes = _toStringKeyMap(await HttpClient.instance.getJson(
      _liveListUrl,
      queryParameters: query,
      header: _headers,
    ));
    final broad = (jsonRes['broad'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(_toRoomItem)
        .toList();
    return LiveCategoryResult(
      hasMore: broad.isNotEmpty,
      items: broad,
    );
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final data = await _getLiveInfo(roomId);
    return int.tryParse(data['RESULT']?.toString() ?? '') == 1;
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    final data = await _getLiveInfo(roomId);
    final result = int.tryParse(data['RESULT']?.toString() ?? '') ?? 0;
    final isLive = result == 1;
    final bid = roomId.split('/').first;
    final bno = data['BNO']?.toString() ??
        (roomId.contains('/') ? roomId.split('/')[1] : '');
    final normalizedRoomId = bno.isNotEmpty ? '$bid/$bno' : roomId;

    return LiveRoomDetail(
      roomId: normalizedRoomId,
      title: data['TITLE']?.toString() ?? (isLive ? '' : '未开播 / 无法观看'),
      userName: data['BJNICK']?.toString() ?? bid,
      cover: '',
      status: isLive,
      online: int.tryParse(data['CTUSER']?.toString() ?? '0') ?? 0,
      url: '$_playHost/$normalizedRoomId',
      userAvatar: '',
      data: data,
    );
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({
    required LiveRoomDetail detail,
  }) async {
    final data = (detail.data is Map)
        ? _toStringKeyMap(detail.data)
        : await _getLiveInfo(detail.roomId);
    if (int.tryParse(data['RESULT']?.toString() ?? '') != 1) {
      return [];
    }

    final presets = data['VIEWPRESET'] as List? ?? [];
    final qualities = <LivePlayQuality>[];
    for (final item in presets.whereType<Map<String, dynamic>>()) {
      final name = item['name']?.toString() ?? '';
      if (name.isEmpty || name == 'auto') continue;
      qualities.add(LivePlayQuality(
        quality: item['label']?.toString() ?? name,
        sort: int.tryParse(item['bps']?.toString() ?? '0') ?? 0,
        data: name,
      ));
    }
    qualities.sort((a, b) => b.sort.compareTo(a.sort));
    return qualities;
  }

  @override
  Future<LivePlayUrl> getPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    try {
      final parts = detail.roomId.split('/');
      final bid = parts.first;
      final liveInfo = (detail.data is Map)
          ? _toStringKeyMap(detail.data)
          : await _getLiveInfo(detail.roomId);
      final bno = liveInfo['BNO']?.toString() ??
          (parts.length > 1 ? parts[1] : '');
      final rmd = liveInfo['RMD']?.toString() ?? '';
      final cdn = liveInfo['CDN']?.toString() ?? '';
      final qualityName = quality.data?.toString() ?? 'original';
      if (bno.isEmpty || rmd.isEmpty) {
        return LivePlayUrl(
          urls: ['http://debug.error/soop_live_info_invalid.m3u8'],
        );
      }

      final aidData = await _postPlayerApi({
        'from_api': '0',
        'mode': 'landing',
        'player_type': 'html5',
        'stream_type': 'common',
        'type': 'aid',
        'bid': bid,
        'bno': bno,
        'pwd': '',
        'quality': qualityName,
      }, referer: '$_playHost/$bid/$bno');
      final aid = aidData['AID']?.toString() ?? '';
      if (int.tryParse(aidData['RESULT']?.toString() ?? '') != 1 ||
          aid.isEmpty) {
        return LivePlayUrl(urls: ['http://debug.error/soop_aid_error.m3u8']);
      }

      final assignUri = Uri.parse('$rmd/broad_stream_assign.html').replace(
        queryParameters: {
          'return_type': cdn,
          'broad_key': '$bno-common-$qualityName-hls',
        },
      );
      final assignJson = _toStringKeyMap(await HttpClient.instance.getJson(
        assignUri.toString(),
        header: _headers,
      ));
      final viewUrl = assignJson['view_url']?.toString() ?? '';
      if (viewUrl.isEmpty) {
        return LivePlayUrl(
          urls: ['http://debug.error/soop_view_url_empty.m3u8'],
        );
      }

      final playUrl = Uri.parse(viewUrl).replace(
        queryParameters: {
          ...Uri.parse(viewUrl).queryParameters,
          'aid': aid,
        },
      );
      return LivePlayUrl(urls: [playUrl.toString()], headers: _headers);
    } catch (e) {
      return LivePlayUrl(
        urls: [
          'http://debug.error/soop_code_error_${Uri.encodeComponent(e.toString())}.m3u8',
        ],
      );
    }
  }
}
