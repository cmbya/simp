import 'dart:async';
import 'dart:convert';

import 'package:simple_live_core/src/common/web_socket_util.dart';
import 'package:simple_live_core/src/model/live_message.dart';

import '../interface/live_danmaku.dart';

class TwitchDanmakuArgs {
  final String roomId;

  TwitchDanmakuArgs({required this.roomId});
}

class TwitchDanmaku implements LiveDanmaku {
  @override
  int heartbeatTime = 4 * 60 * 1000;

  @override
  Function(LiveMessage msg)? onMessage;

  @override
  Function(String msg)? onClose;

  @override
  Function()? onReady;

  WebScoketUtils? webScoketUtils;

  @override
  Future start(dynamic args) async {
    if (args is! TwitchDanmakuArgs || args.roomId.isEmpty) {
      onClose?.call('Twitch 弹幕参数错误');
      return;
    }

    webScoketUtils = WebScoketUtils(
      url: 'wss://irc-ws.chat.twitch.tv:443',
      heartBeatTime: heartbeatTime,
      onMessage: decodeMessage,
      onReady: () {
        onReady?.call();
        joinRoom(args.roomId);
      },
      onHeartBeat: heartbeat,
      onReconnect: () {
        onClose?.call('与 Twitch 弹幕服务器断开连接，正在尝试重连');
      },
      onClose: (e) {
        onClose?.call('Twitch 弹幕服务器连接失败 $e');
      },
    );
    webScoketUtils?.connect();
  }

  void joinRoom(String roomId) {
    final channel = roomId.toLowerCase();
    webScoketUtils?.sendMessage('CAP REQ :twitch.tv/tags twitch.tv/commands');
    webScoketUtils?.sendMessage('PASS SCHMOOPIIE');
    webScoketUtils?.sendMessage(
      'NICK justinfan${DateTime.now().millisecondsSinceEpoch % 100000}',
    );
    webScoketUtils?.sendMessage('JOIN #$channel');
  }

  @override
  void heartbeat() {
    webScoketUtils?.sendMessage('PING :tmi.twitch.tv');
  }

  @override
  Future stop() async {
    onMessage = null;
    onClose = null;
    webScoketUtils?.close();
  }

  void decodeMessage(dynamic data) {
    try {
      final text = data.toString();
      for (final line in const LineSplitter().convert(text)) {
        if (line.isEmpty) {
          continue;
        }
        if (line.startsWith('PING')) {
          webScoketUtils?.sendMessage(line.replaceFirst('PING', 'PONG'));
          continue;
        }
        if (line.contains('PRIVMSG')) {
          final liveMsg = _parsePrivMsg(line);
          if (liveMsg != null) {
            onMessage?.call(liveMsg);
          }
        }
      }
    } catch (_) {}
  }

  LiveMessage? _parsePrivMsg(String line) {
    final msgStart = line.indexOf(' :', line.indexOf('PRIVMSG'));
    if (msgStart < 0) {
      return null;
    }

    final tags = _parseTags(line);
    final message = line.substring(msgStart + 2);
    final userName = tags['display-name']?.isNotEmpty == true
        ? tags['display-name']!
        : _parseUserName(line);
    final color = _parseColor(tags['color']);

    return LiveMessage(
      type: LiveMessageType.chat,
      userName: userName,
      message: message,
      color: color,
    );
  }

  Map<String, String> _parseTags(String line) {
    if (!line.startsWith('@')) {
      return {};
    }

    final end = line.indexOf(' ');
    if (end <= 1) {
      return {};
    }

    final result = <String, String>{};
    for (final item in line.substring(1, end).split(';')) {
      final index = item.indexOf('=');
      if (index <= 0) {
        continue;
      }
      result[item.substring(0, index)] = _unescapeTag(item.substring(index + 1));
    }
    return result;
  }

  String _parseUserName(String line) {
    final start = line.indexOf(':');
    final end = line.indexOf('!');
    if (start >= 0 && end > start) {
      return line.substring(start + 1, end);
    }
    return 'Twitch';
  }

  String _unescapeTag(String value) {
    return value
        .replaceAll(r'\s', ' ')
        .replaceAll(r'\:', ';')
        .replaceAll(r'\\', r'\')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\n', '\n');
  }

  LiveMessageColor _parseColor(String? color) {
    if (color == null || color.isEmpty || !color.startsWith('#')) {
      return LiveMessageColor.white;
    }
    final value = int.tryParse(color.substring(1), radix: 16);
    if (value == null) {
      return LiveMessageColor.white;
    }
    return LiveMessageColor.numberToColor(value);
  }
}
