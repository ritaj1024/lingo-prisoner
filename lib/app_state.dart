import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class AppState extends ChangeNotifier {
  String? apiKey;
  int totalDialogs = 0;
  int todayDialogs = 0;
  int streak = 0;

  Future<void> loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    apiKey = prefs.getString('api_key');
    totalDialogs = prefs.getInt('total_dialogs') ?? 0;
    todayDialogs = prefs.getInt('today_dialogs') ?? 0;
    streak = prefs.getInt('streak') ?? 0;
    notifyListeners();
  }

  Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key', key);
    apiKey = key;
    notifyListeners();
  }

  Future<void> recordDialog() async {
    final prefs = await SharedPreferences.getInstance();
    totalDialogs++;
    todayDialogs++;
    await prefs.setInt('total_dialogs', totalDialogs);
    await prefs.setInt('today_dialogs', todayDialogs);
    notifyListeners();
  }
}

class ZhipuService {
  static const _url = 'https://open.bigmodel.cn/api/paas/v4/chat/completions';

  static Future<String> chat({
    required String apiKey,
    required List<Map<String, String>> messages,
    String model = 'glm-4-flash',
  }) async {
    final resp = await http.post(
      Uri.parse(_url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': messages,
        'temperature': 0.3,
        'max_tokens': 800,
      }),
    ).timeout(const Duration(seconds: 30));

    if (resp.statusCode == 200) {
      return jsonDecode(utf8.decode(resp.bodyBytes))['choices'][0]['message']
          ['content'] as String;
    }
    final err = jsonDecode(resp.body);
    throw Exception(err['error']?['message'] ?? '请求失败 ${resp.statusCode}');
  }

  static Future<bool> testKey(String apiKey) async {
    try {
      await chat(apiKey: apiKey, messages: [
        {'role': 'user', 'content': 'Hi'}
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }
}
