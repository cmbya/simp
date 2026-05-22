import 'dart:convert';
import 'package:http/http.dart' as http;

import 'interface/live_danmaku.dart';
import 'interface/live_site.dart';
import 'model/live_category.dart';
import 'model/live_category_result.dart';
import 'model/live_play_quality.dart';
import 'model/live_play_url.dart';
import 'model/live_room_detail.dart';
import 'model/live_room_item.dart';
import 'danmaku/twitch_danmaku.dart';

class TwitchSite extends LiveSite {
  @override
  String id = "twitch";

  @override
  String name = "Twitch";

  final String _gqlUrl = 'https://gql.twitch.tv/gql';
  final String _clientId = 'kimne78kx3ncx6brgo4mv6wki5h1ko';

  @override
  LiveDanmaku getDanmaku() => TwitchDanmaku();

  Future<dynamic> _postGql(Map<String, dynamic> query) async {
    final response = await http.post(
      Uri.parse(_gqlUrl),
      headers: {
        'Client-Id': _clientId,
        'Content-Type': 'application/json',
      },
      body: jsonEncode([query]),
    );
    return jsonDecode(response.body)[0]['data'];
  }

  Future<Map<String, dynamic>?> _getPlaybackAccessToken(String roomId) async {
    final body = {
      "query":
          "query(\$login: String!) { streamPlaybackAccessToken(channelName: \$login, params: {platform: \"web\", playerBackend: \"mediaplayer\", playerType: \"site\"}) { value signature } }",
      "variables": {"login": roomId}
    };

    final response = await http.post(
      Uri.parse(_gqlUrl),
      headers: {
        'Client-Id': _clientId,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    final jsonRes = jsonDecode(response.body);
    if (jsonRes['errors'] != null) {
      throw Exception(jsonRes['errors'][0]['message'].toString());
    }
    return jsonRes['data']?['streamPlaybackAccessToken'];
  }

  String _buildMasterPlaylistUrl({
    required String roomId,
    required String sig,
    required String token,
  }) {
    final query = {
      'allow_source': 'true',
      'allow_audio_only': 'true',
      'fast_bread': 'true',
      'p': DateTime.now().millisecondsSinceEpoch.toString(),
      'sig': sig,
      'token': token,
    };
    return Uri.https(
      'usher.ttvnw.net',
      '/api/channel/hls/$roomId.m3u8',
      query,
    ).toString();
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    final query = {
      "query":
          "query { streams(first: 30) { edges { node { broadcaster { login displayName } title viewersCount previewImageURL(width: 320, height: 180) } } } }"
    };
    final data = await _postGql(query);
    List<LiveRoomItem> items = [];

    for (var edge in data['streams']['edges']) {
      var node = edge['node'];
      var bc = node['broadcaster'];
      items.add(LiveRoomItem(
        roomId: bc['login'],
        title: node['title'],
        userName: bc['displayName'],
        cover: node['previewImageURL'],
        online: node['viewersCount'],
      ));
    }
    return LiveCategoryResult(hasMore: false, items: items);
  }

  @override
  Future<List<LiveCategory>> getCategores() async {
    final query = {
      "query":
          "query { directoriesWithTags(first: 20) { edges { node { id name avatarURL(width: 144, height: 192) } } } }"
    };
    final data = await _postGql(query);

    LiveCategory mainCategory =
        LiveCategory(id: "all", name: "热门分类", children: []);

    for (var edge in data['directoriesWithTags']['edges']) {
      var node = edge['node'];
      mainCategory.children.add(LiveSubCategory(
        id: node['name'],
        name: node['name'],
        pic: node['avatarURL'],
        parentId: "all",
      ));
    }
    return [mainCategory];
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(LiveSubCategory category,
      {int page = 1}) async {
    final query = {
      "query":
          "query(\$game: String!) { game(name: \$game) { streams(first: 30) { edges { node { broadcaster { login displayName } title viewersCount previewImageURL(width: 320, height: 180) } } } } }",
      "variables": {"game": category.name}
    };
    final data = await _postGql(query);
    List<LiveRoomItem> items = [];

    if (data['game'] != null && data['game']['streams'] != null) {
      for (var edge in data['game']['streams']['edges']) {
        var node = edge['node'];
        var bc = node['broadcaster'];
        items.add(LiveRoomItem(
          roomId: bc['login'],
          title: node['title'],
          userName: bc['displayName'],
          cover: node['previewImageURL'],
          online: node['viewersCount'],
        ));
      }
    }
    return LiveCategoryResult(hasMore: false, items: items);
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final query = {
      "query": "query(\$login: String!) { user(login: \$login) { stream { id } } }",
      "variables": {"login": roomId}
    };
    final data = await _postGql(query);
    return data['user'] != null && data['user']['stream'] != null;
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    final query = {
      "query":
          "query(\$login: String!) { user(login: \$login) { displayName profileImageURL(width: 50) stream { title viewersCount } } }",
      "variables": {"login": roomId}
    };
    final data = await _postGql(query);
    var user = data['user'];
    bool isLive = user != null && user['stream'] != null;

    return LiveRoomDetail(
      roomId: roomId,
      title: isLive ? user['stream']['title'] : '未开播 / 离线',
      userName: user != null ? user['displayName'] : roomId,
      cover: '',
      status: isLive,
      online: isLive ? user['stream']['viewersCount'] : 0,
      url: 'https://www.twitch.tv/$roomId',
      userAvatar: user != null ? user['profileImageURL'] : '',
      danmakuData: TwitchDanmakuArgs(roomId: roomId),
    );
  }

  @override
  Future<LivePlayUrl> getPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    try {
      if (quality.data is String && quality.data.toString().isNotEmpty) {
        return LivePlayUrl(urls: [quality.data.toString()]);
      }

      final tokenData = await _getPlaybackAccessToken(detail.roomId);
      if (tokenData == null) {
        return LivePlayUrl(urls: ['http://debug.error/token_is_null.m3u8']);
      }

      final videoUrl = _buildMasterPlaylistUrl(
        roomId: detail.roomId,
        sig: tokenData['signature'].toString(),
        token: tokenData['value'].toString(),
      );
      return LivePlayUrl(urls: [videoUrl]);
    } catch (e) {
      return LivePlayUrl(
        urls: ['http://debug.error/code_error_${Uri.encodeComponent(e.toString())}.m3u8'],
      );
    }
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({
    required LiveRoomDetail detail,
  }) async {
    try {
      final tokenData = await _getPlaybackAccessToken(detail.roomId);
      if (tokenData == null) {
        return _fallbackQualities();
      }

      final masterUrl = _buildMasterPlaylistUrl(
        roomId: detail.roomId,
        sig: tokenData['signature'].toString(),
        token: tokenData['value'].toString(),
      );
      final response = await http.get(Uri.parse(masterUrl));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _fallbackQualities(masterUrl: masterUrl);
      }

      final qualities = _parseM3u8Qualities(response.body);
      if (qualities.isEmpty) {
        return _fallbackQualities(masterUrl: masterUrl);
      }
      return qualities;
    } catch (_) {
      return _fallbackQualities();
    }
  }

  List<LivePlayQuality> _parseM3u8Qualities(String body) {
    final result = <LivePlayQuality>[];
    final lines = const LineSplitter().convert(body);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) {
        continue;
      }

      final urlLine = i + 1 < lines.length ? lines[i + 1].trim() : '';
      if (urlLine.isEmpty || urlLine.startsWith('#')) {
        continue;
      }

      final resolution =
          RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(line)?.group(1);
      final frameRateText =
          RegExp(r'FRAME-RATE=([0-9.]+)').firstMatch(line)?.group(1);
      final name = RegExp(r'VIDEO="([^"]+)"').firstMatch(line)?.group(1);
      final frameRate = double.tryParse(frameRateText ?? '');
      final height = int.tryParse(resolution ?? '') ?? 0;
      final url = Uri.parse(urlLine).isAbsolute
          ? urlLine
          : Uri.parse('https://usher.ttvnw.net').resolve(urlLine).toString();

      if (height == 0 && name == 'audio_only') {
        continue;
      }

      var title = name ?? (height > 0 ? '${height}p' : '自动');
      if (height > 0) {
        title = '${height}p${frameRate != null && frameRate >= 50 ? '60' : ''}';
      }
      result.add(LivePlayQuality(
        quality: title,
        sort: height * 1000 + (frameRate?.round() ?? 0),
        data: url,
      ));
    }

    result.sort((a, b) => b.sort.compareTo(a.sort));
    for (var i = 0; i < result.length; i++) {
      final item = result[i];
      if (i == 0 && !item.quality.contains('来源')) {
        result[i] = LivePlayQuality(
          quality: '${item.quality}（来源）',
          sort: item.sort,
          data: item.data,
        );
      }
    }
    return result;
  }

  List<LivePlayQuality> _fallbackQualities({String? masterUrl}) {
    return [
      LivePlayQuality(
        quality: '自动',
        sort: 10000,
        data: masterUrl ?? '',
      ),
    ];
  }
}
