import 'dart:convert';
import 'package:http/http.dart' as http;

import 'interface/live_site.dart';
import 'model/live_category.dart';
import 'model/live_category_result.dart';
import 'model/live_play_quality.dart';
import 'model/live_play_url.dart';
import 'model/live_room_detail.dart';
import 'model/live_room_item.dart';

class TwitchSite extends LiveSite {
  @override
  String id = "twitch";

  @override
  String name = "Twitch";

  final String _gqlUrl = 'https://gql.twitch.tv/gql';
  final String _clientId = 'kimne78kx3ncx6brgo4mv6wki5h1ko';

  Future<dynamic> _postGql(Map<String, dynamic> query) async {
    final response = await http.post(
      Uri.parse(_gqlUrl),
      headers: {'Client-Id': _clientId},
      body: jsonEncode([query]), 
    );
    return jsonDecode(response.body)[0]['data'];
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    final query = {
      "query": "query { streams(first: 30) { edges { node { broadcaster { login displayName } title viewersCount previewImageURL(width: 320, height: 180) } } } }"
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
      "query": "query { directoriesWithTags(first: 20) { edges { node { id name avatarURL(width: 144, height: 192) } } } }"
    };
    final data = await _postGql(query);
    
    LiveCategory mainCategory = LiveCategory(id: "all", name: "热门分类", children: []);

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
  Future<LiveCategoryResult> getCategoryRooms(LiveSubCategory category, {int page = 1}) async {
    final query = {
      "query": "query(\$game: String!) { game(name: \$game) { streams(first: 30) { edges { node { broadcaster { login displayName } title viewersCount previewImageURL(width: 320, height: 180) } } } } }",
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
      "query": "query(\$login: String!) { user(login: \$login) { displayName profileImageURL(width: 50) stream { title viewersCount } } }",
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
    );
  }

  // 💡 带有“显影魔法”的最简视频流获取代码
  @override
  Future<LivePlayUrl> getPlayUrls({required LiveRoomDetail detail, required LivePlayQuality quality}) async {
    try {
      final roomId = detail.roomId;

      final body = {
        "query": "query { streamPlaybackAccessToken(channelName: \"$roomId\", params: {platform: \"web\", playerBackend: \"mediaplayer\", playerType: \"embed\"}) { value signature } }"
      };

      final response = await http.post(
        Uri.parse('https://gql.twitch.tv/gql'),
        headers: {
          'Client-Id': 'kimne78kx3ncx6brgo4mv6wki5h1ko',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body), 
      );

      final jsonRes = jsonDecode(response.body);

      // 如果 Twitch 拦截，强行生成错误网址给日志
      if (jsonRes['errors'] != null) {
         String errMsg = Uri.encodeComponent(jsonRes['errors'][0]['message'].toString());
         return LivePlayUrl(urls: ['http://debug.error/api_error_$errMsg.m3u8']);
      }

      final tokenData = jsonRes['data']['streamPlaybackAccessToken'];
      if (tokenData == null) {
         return LivePlayUrl(urls: ['http://debug.error/token_is_null.m3u8']);
      }

      final sig = tokenData['signature'];
      final token = tokenData['value'];
      final randomP = DateTime.now().millisecondsSinceEpoch;

      String videoUrl = 'https://usher.ttvnw.net/api/channel/hls/$roomId.m3u8?allow_source=true&allow_audio_only=true&p=$randomP&sig=$sig&token=${Uri.encodeComponent(token)}';

      return LivePlayUrl(urls: [videoUrl]);
    } catch (e) {
      // 代码报错也生成错误网址
      return LivePlayUrl(urls: ['http://debug.error/code_error_${Uri.encodeComponent(e.toString())}.m3u8']);
    }
  }
  
  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoomDetail detail}) async {
    return [LivePlayQuality(quality: '原画(Twitch 自适应)', sort: 10000, data: '')];
  }
}