import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..loadApiKey(),
      child: const LingoPrisonerApp(),
    ),
  );
}

// ─── State ────────────────────────────────────────────────────────────────────

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

// ─── ZhipuAI Service ──────────────────────────────────────────────────────────

class ZhipuService {
  static const _baseUrl = 'https://open.bigmodel.cn/api/paas/v4/chat/completions';

  static Future<String> chat({
    required String apiKey,
    required List<Map<String, String>> messages,
    String model = 'glm-4-flash',
  }) async {
    final resp = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 500,
      }),
    ).timeout(const Duration(seconds: 30));

    if (resp.statusCode == 200) {
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      return data['choices'][0]['message']['content'] as String;
    } else {
      final err = jsonDecode(resp.body);
      throw Exception(err['error']?['message'] ?? '请求失败 ${resp.statusCode}');
    }
  }

  static Future<bool> testKey(String apiKey) async {
    try {
      await chat(apiKey: apiKey, messages: [{'role': 'user', 'content': 'Hi'}]);
      return true;
    } catch (_) {
      return false;
    }
  }
}

// ─── App ──────────────────────────────────────────────────────────────────────

class LingoPrisonerApp extends StatelessWidget {
  const LingoPrisonerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '语言囚徒',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2196F3)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

// ─── Home ─────────────────────────────────────────────────────────────────────

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('语言囚徒', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.apiKey == null || state.apiKey!.isEmpty)
              _buildApiKeyBanner(context),
            _buildStatsRow(state),
            const SizedBox(height: 20),
            const Text('学习功能', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildFeatureCard(context,
              icon: Icons.chat_bubble_outline, title: '情景对话',
              subtitle: '一问一答英语练习，支持语音回复',
              color: const Color(0xFF4CAF50), progress: 0.9,
              onTap: state.apiKey?.isNotEmpty == true
                  ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DialogScreen()))
                  : () => _showNeedApiKey(context)),
            const SizedBox(height: 12),
            _buildFeatureCard(context,
              icon: Icons.hearing, title: '听力训练',
              subtitle: '听AI朗读，训练英语听力',
              color: const Color(0xFF9C27B0), progress: 0.8, badge: '开发中',
              onTap: () => _showComingSoon(context, '听力训练')),
            const SizedBox(height: 12),
            _buildFeatureCard(context,
              icon: Icons.mic, title: '口语练习',
              subtitle: '开口说英语，AI纠正发音',
              color: const Color(0xFFFF9800), progress: 0.7, badge: '开发中',
              onTap: () => _showComingSoon(context, '口语练习')),
            const SizedBox(height: 20),
            const Text('工具', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildFeatureCard(context,
              icon: Icons.lock, title: '监狱模式',
              subtitle: '完成学习目标才能解锁手机',
              color: const Color(0xFFF44336), progress: 0.6, badge: '开发中',
              onTap: () => _showComingSoon(context, '监狱模式')),
            const SizedBox(height: 12),
            _buildFeatureCard(context,
              icon: Icons.bar_chart, title: '学习统计',
              subtitle: '查看学习进度和数据',
              color: const Color(0xFF2196F3), progress: 1.0,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen()))),
          ],
        ),
      ),
    );
  }

  Widget _buildApiKeyBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF9800)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Color(0xFFFF9800)),
          const SizedBox(width: 8),
          const Expanded(child: Text('请先设置智谱AI API Key才能使用对话功能')),
          TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(AppState state) {
    return Row(
      children: [
        _buildStatCard('今日对话', '${state.todayDialogs}次', Icons.today, const Color(0xFF4CAF50)),
        const SizedBox(width: 12),
        _buildStatCard('累计对话', '${state.totalDialogs}次', Icons.history, const Color(0xFF2196F3)),
        const SizedBox(width: 12),
        _buildStatCard('连续天数', '${state.streak}天', Icons.local_fire_department, const Color(0xFFFF5722)),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(BuildContext context, {
    required IconData icon, required String title, required String subtitle,
    required Color color, required double progress, required VoidCallback onTap, String? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
                          child: Text(badge, style: TextStyle(fontSize: 10, color: Colors.orange.shade800)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey.shade200,
                    color: color, minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  void _showNeedApiKey(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('请先在设置中填写智谱AI API Key'),
      action: SnackBarAction(label: '去设置',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
    ));
  }

  void _showComingSoon(BuildContext context, String feature) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(feature),
        content: const Text('该功能正在开发中，敬请期待！\n\n目前请先体验「情景对话」功能。'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('好的'))],
      ),
    );
  }
}

// ─── Settings ─────────────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  bool _isTesting = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final key = context.read<AppState>().apiKey;
    if (key != null) _controller.text = key;
  }

  Future<void> _save() async {
    final apiKey = _controller.text.trim();
    if (apiKey.isEmpty) { _snack('请输入API Key', isError: true); return; }
    setState(() => _isTesting = true);
    try {
      final ok = await ZhipuService.testKey(apiKey);
      if (!mounted) return;
      if (ok) {
        await context.read<AppState>().saveApiKey(apiKey);
        _snack('✅ API Key验证成功，已保存！');
        Navigator.pop(context);
      } else {
        _snack('❌ API Key无效，请检查后重试', isError: true);
      }
    } catch (e) {
      if (mounted) _snack('❌ 连接失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), backgroundColor: const Color(0xFF2196F3), foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('智谱AI API Key', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('访问 open.bigmodel.cn 注册获取免费API Key', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              obscureText: _obscure,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: '粘贴您的API Key',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isTesting ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isTesting
                    ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                        SizedBox(width: 10), Text('正在验证...'),
                      ])
                    : const Text('保存并验证', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 12),
            const Text('* 点击保存后会自动调用API验证Key是否有效', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }
}

// ─── Dialog Screen（一问一答 + 语音输入）────────────────────────────────────────

class DialogScreen extends StatefulWidget {
  const DialogScreen({Key? key}) : super(key: key);
  @override
  State<DialogScreen> createState() => _DialogScreenState();
}

class _DialogScreenState extends State<DialogScreen> with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final SpeechToText _speech = SpeechToText();

  final List<_Message> _messages = [];
  bool _isLoading = false;
  bool _isListening = false;
  bool _speechAvailable = false;
  String _liveText = '';          // 实时识别文字
  late AnimationController _pulseController;

  // 一问一答：等待用户回答状态
  bool _waitingForAnswer = false;

  static const _scenarios = [
    ('☕ 咖啡厅点单', 'You are a barista at a cozy English café. Have a one-question-at-a-time conversation with the customer. Ask ONE question, wait for their answer, then respond naturally and ask the next question. Occasionally correct their English mistakes in brackets like [Correction: ...]. Keep it natural and friendly.'),
    ('💼 求职面试', 'You are an English-speaking HR interviewer. Conduct a job interview one question at a time. Ask ONE interview question, wait for the answer, evaluate it briefly, then ask the next question. Correct major English mistakes in brackets like [Correction: ...].'),
    ('🗺️ 问路指路', 'You are a local in an English-speaking city. Help a tourist find their way. Ask or answer ONE thing at a time. Correct their English mistakes in brackets like [Correction: ...]. Keep directions simple and clear.'),
    ('🛍️ 购物还价', 'You are a shop owner in an English-speaking market. Have a one-exchange-at-a-time shopping conversation. Respond to ONE thing at a time. Correct English mistakes in brackets like [Correction: ...].'),
  ];

  int _scenarioIndex = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    _initSpeech();
    _startScenario();
  }

  Future<void> _initSpeech() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      _speechAvailable = await _speech.initialize(
        onError: (e) => setState(() => _isListening = false),
        onStatus: (s) { if (s == 'done' || s == 'notListening') _stopListening(); },
      );
      setState(() {});
    }
  }

  Future<void> _startScenario() async {
    final apiKey = context.read<AppState>().apiKey!;
    setState(() { _messages.clear(); _isLoading = true; _waitingForAnswer = false; });

    try {
      final reply = await ZhipuService.chat(
        apiKey: apiKey,
        messages: [
          {'role': 'system', 'content': _scenarios[_scenarioIndex].$2},
          {'role': 'user', 'content': 'Start the conversation by greeting me and asking your first question.'},
        ],
      );
      setState(() {
        _messages.add(_Message(text: reply, isUser: false));
        _waitingForAnswer = true;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() => _messages.add(_Message(text: '⚠️ 连接失败: $e', isUser: false, isError: true)));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _send([String? overrideText]) async {
    final text = (overrideText ?? _controller.text).trim();
    if (text.isEmpty || _isLoading) return;

    _controller.clear();
    setState(() {
      _messages.add(_Message(text: text, isUser: true));
      _isLoading = true;
      _waitingForAnswer = false;
      _liveText = '';
    });
    _scrollToBottom();

    final apiKey = context.read<AppState>().apiKey!;
    final history = _messages.map((m) => {
      'role': m.isUser ? 'user' : 'assistant',
      'content': m.text,
    }).toList();

    try {
      final reply = await ZhipuService.chat(
        apiKey: apiKey,
        messages: [
          {'role': 'system', 'content': _scenarios[_scenarioIndex].$2},
          ...history,
        ],
      );
      setState(() {
        _messages.add(_Message(text: reply, isUser: false));
        _waitingForAnswer = true;
      });
      await context.read<AppState>().recordDialog();
    } catch (e) {
      setState(() => _messages.add(_Message(text: '⚠️ 发送失败: $e', isUser: false, isError: true)));
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('麦克风权限未开启，请在系统设置中允许')));
      return;
    }
    setState(() { _isListening = true; _liveText = ''; });
    await _speech.listen(
      onResult: (result) {
        setState(() {
          _liveText = result.recognizedWords;
          if (result.finalResult && _liveText.isNotEmpty) {
            _stopListening();
            _send(_liveText);
          }
        });
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_US',
      listenMode: ListenMode.confirmation,
    );
  }

  void _stopListening() {
    _speech.stop();
    setState(() { _isListening = false; });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: Text(_scenarios[_scenarioIndex].$1),
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.swap_horiz),
            tooltip: '切换场景',
            onSelected: (i) { setState(() => _scenarioIndex = i); _startScenario(); },
            itemBuilder: (_) => _scenarios.asMap().entries
                .map((e) => PopupMenuItem(value: e.key, child: Text(e.value.$1)))
                .toList(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 场景提示条
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: const Color(0xFFE8F5E9),
            child: Text(
              _waitingForAnswer ? '💬 轮到你回答了！可以打字或按麦克风说话' : '⏳ AI思考中...',
              style: TextStyle(fontSize: 12, color: _waitingForAnswer ? const Color(0xFF2E7D32) : Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),

          // 消息列表
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _messages.length) return _buildTyping();
                return _buildBubble(_messages[i]);
              },
            ),
          ),

          // 实时语音识别显示
          if (_isListening && _liveText.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mic, color: Colors.green, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_liveText, style: const TextStyle(color: Colors.black87))),
                ],
              ),
            ),

          // 输入区
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, -2))],
      ),
      child: Row(
        children: [
          // 文字输入
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: _isListening ? '正在聆听...' : '用英语回答...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              enabled: !_isLoading && !_isListening,
            ),
          ),
          const SizedBox(width: 8),

          // 语音按钮
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, child) {
              final scale = _isListening ? (1.0 + _pulseController.value * 0.15) : 1.0;
              return Transform.scale(
                scale: scale,
                child: GestureDetector(
                  onTap: !_isLoading ? _toggleListening : null,
                  child: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: _isListening ? Colors.red : const Color(0xFF4CAF50),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(
                        color: (_isListening ? Colors.red : const Color(0xFF4CAF50)).withOpacity(0.4),
                        blurRadius: _isListening ? 12 : 4,
                      )],
                    ),
                    child: Icon(
                      _isListening ? Icons.stop : Icons.mic,
                      color: Colors.white, size: 24,
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(width: 8),

          // 发送按钮
          GestureDetector(
            onTap: (!_isLoading && !_isListening) ? _send : null,
            child: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: (!_isLoading && !_isListening) ? const Color(0xFF2196F3) : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(_Message msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          bottom: 10,
          left: msg.isUser ? 48 : 0,
          right: msg.isUser ? 0 : 48,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: msg.isError
              ? Colors.red.shade50
              : msg.isUser
                  ? const Color(0xFF4CAF50)
                  : Colors.white,
          borderRadius: BorderRadius.circular(18).copyWith(
            bottomRight: msg.isUser ? const Radius.circular(4) : null,
            bottomLeft: msg.isUser ? null : const Radius.circular(4),
          ),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            color: msg.isUser ? Colors.white : Colors.black87,
            fontSize: 15, height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildTyping() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18).copyWith(bottomLeft: const Radius.circular(4)),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4CAF50))),
            SizedBox(width: 8),
            Text('AI正在思考...', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _pulseController.dispose();
    _speech.stop();
    super.dispose();
  }
}

class _Message {
  final String text;
  final bool isUser;
  final bool isError;
  _Message({required this.text, required this.isUser, this.isError = false});
}

// ─── Stats Screen ─────────────────────────────────────────────────────────────

class StatsScreen extends StatelessWidget {
  const StatsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('学习统计'), backgroundColor: const Color(0xFF2196F3), foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildCard('📅 今日对话次数', '${state.todayDialogs} 次', const Color(0xFF4CAF50)),
            const SizedBox(height: 16),
            _buildCard('📊 累计对话次数', '${state.totalDialogs} 次', const Color(0xFF2196F3)),
            const SizedBox(height: 16),
            _buildCard('🔥 连续学习天数', '${state.streak} 天', const Color(0xFFFF5722)),
            const SizedBox(height: 32),
            const Text('坚持每天练习，英语水平会稳步提升！',
                style: TextStyle(color: Colors.grey, fontSize: 14), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(String label, String value, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}