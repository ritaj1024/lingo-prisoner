import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ChangeNotifierProvider(
    create: (_) => AppState()..loadApiKey(),
    child: const LingoPrisonerApp(),
  ));
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

// ─── ZhipuAI ─────────────────────────────────────────────────────────────────

class ZhipuService {
  static const _url = 'https://open.bigmodel.cn/api/paas/v4/chat/completions';

  static Future<String> chat({
    required String apiKey,
    required List<Map<String, String>> messages,
    String model = 'glm-4-flash',
  }) async {
    final resp = await http.post(
      Uri.parse(_url),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
      body: jsonEncode({'model': model, 'messages': messages, 'temperature': 0.7, 'max_tokens': 500}),
    ).timeout(const Duration(seconds: 30));
    if (resp.statusCode == 200) {
      return jsonDecode(utf8.decode(resp.bodyBytes))['choices'][0]['message']['content'] as String;
    }
    final err = jsonDecode(resp.body);
    throw Exception(err['error']?['message'] ?? '请求失败 ${resp.statusCode}');
  }

  static Future<bool> testKey(String apiKey) async {
    try { await chat(apiKey: apiKey, messages: [{'role': 'user', 'content': 'Hi'}]); return true; }
    catch (_) { return false; }
  }
}

// ─── App ─────────────────────────────────────────────────────────────────────

class LingoPrisonerApp extends StatelessWidget {
  const LingoPrisonerApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '语言囚徒',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2196F3)), useMaterial3: true),
    home: const HomeScreen(),
  );
}

// ─── Home ─────────────────────────────────────────────────────────────────────

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final hasKey = state.apiKey?.isNotEmpty == true;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('语言囚徒', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.settings),
            onPressed: () => _push(context, const SettingsScreen()))],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!hasKey) _apiBanner(context),
          _statsRow(state),
          const SizedBox(height: 20),
          const Text('学习功能', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _card(context, icon: Icons.chat_bubble_outline, title: '情景对话',
              sub: '一问一答英语练习，支持语音回复', color: const Color(0xFF4CAF50), progress: 0.9,
              onTap: hasKey ? () => _push(context, const DialogScreen()) : () => _needKey(context)),
          const SizedBox(height: 12),
          _card(context, icon: Icons.hearing, title: '听力训练',
              sub: 'AI朗读句子，听写检验理解', color: const Color(0xFF9C27B0), progress: 0.8,
              onTap: hasKey ? () => _push(context, const ListeningScreen()) : () => _needKey(context)),
          const SizedBox(height: 12),
          _card(context, icon: Icons.mic, title: '口语练习',
              sub: 'AI给出话题，开口说英语，AI评分', color: const Color(0xFFFF9800), progress: 0.7,
              onTap: hasKey ? () => _push(context, const SpeakingScreen()) : () => _needKey(context)),
          const SizedBox(height: 20),
          const Text('工具', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _card(context, icon: Icons.lock, title: '监狱模式',
              sub: '完成学习目标才能解锁手机', color: const Color(0xFFF44336), progress: 0.6, badge: '开发中',
              onTap: () => _soon(context, '监狱模式')),
          const SizedBox(height: 12),
          _card(context, icon: Icons.bar_chart, title: '学习统计',
              sub: '查看学习进度和数据', color: const Color(0xFF2196F3), progress: 1.0,
              onTap: () => _push(context, const StatsScreen())),
        ]),
      ),
    );
  }

  void _push(BuildContext ctx, Widget w) =>
      Navigator.push(ctx, MaterialPageRoute(builder: (_) => w));

  void _needKey(BuildContext ctx) => ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
    content: const Text('请先设置智谱AI API Key'),
    action: SnackBarAction(label: '去设置',
        onPressed: () => _push(ctx, const SettingsScreen())),
  ));

  void _soon(BuildContext ctx, String name) => showDialog(
    context: ctx,
    builder: (_) => AlertDialog(
      title: Text(name),
      content: const Text('该功能正在开发中，敬请期待！'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('好的'))],
    ),
  );

  Widget _apiBanner(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFF9800)),
    ),
    child: Row(children: [
      const Icon(Icons.warning_amber, color: Color(0xFFFF9800)),
      const SizedBox(width: 8),
      const Expanded(child: Text('请先设置智谱AI API Key才能使用学习功能')),
      TextButton(onPressed: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const SettingsScreen())), child: const Text('去设置')),
    ]),
  );

  Widget _statsRow(AppState state) => Row(children: [
    _stat('今日对话', '${state.todayDialogs}次', Icons.today, const Color(0xFF4CAF50)),
    const SizedBox(width: 12),
    _stat('累计对话', '${state.totalDialogs}次', Icons.history, const Color(0xFF2196F3)),
    const SizedBox(width: 12),
    _stat('连续天数', '${state.streak}天', Icons.local_fire_department, const Color(0xFFFF5722)),
  ]);

  Widget _stat(String label, String value, IconData icon, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]),
      child: Column(children: [
        Icon(icon, color: color, size: 24), const SizedBox(height: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    ),
  );

  Widget _card(BuildContext context, {
    required IconData icon, required String title, required String sub,
    required Color color, required double progress, required VoidCallback onTap, String? badge,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))]),
      child: Row(children: [
        Container(width: 48, height: 48,
          decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 26)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
                child: Text(badge, style: TextStyle(fontSize: 10, color: Colors.orange.shade800)),
              ),
            ],
          ]),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: progress, backgroundColor: Colors.grey.shade200,
              color: color, minHeight: 4, borderRadius: BorderRadius.circular(2)),
        ])),
        Icon(Icons.chevron_right, color: Colors.grey.shade400),
      ]),
    ),
  );
}

// ─── Settings ─────────────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _ctrl = TextEditingController();
  bool _testing = false, _obscure = true;

  @override
  void initState() {
    super.initState();
    final k = context.read<AppState>().apiKey;
    if (k != null) _ctrl.text = k;
  }

  Future<void> _save() async {
    final key = _ctrl.text.trim();
    if (key.isEmpty) { _snack('请输入API Key', true); return; }
    setState(() => _testing = true);
    try {
      if (await ZhipuService.testKey(key)) {
        await context.read<AppState>().saveApiKey(key);
        if (mounted) { _snack('✅ 验证成功，已保存！', false); Navigator.pop(context); }
      } else { if (mounted) _snack('❌ API Key无效', true); }
    } catch (e) { if (mounted) _snack('❌ 连接失败：$e', true); }
    finally { if (mounted) setState(() => _testing = false); }
  }

  void _snack(String m, bool err) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(m), backgroundColor: err ? Colors.red : Colors.green));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置'), backgroundColor: const Color(0xFF2196F3), foregroundColor: Colors.white),
    body: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('智谱AI API Key', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      const Text('访问 open.bigmodel.cn 注册获取免费API Key', style: TextStyle(color: Colors.grey, fontSize: 13)),
      const SizedBox(height: 16),
      TextField(
        controller: _ctrl, obscureText: _obscure,
        decoration: InputDecoration(
          border: const OutlineInputBorder(), hintText: '粘贴您的API Key',
          suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscure = !_obscure)),
        ),
      ),
      const SizedBox(height: 24),
      SizedBox(width: double.infinity, child: ElevatedButton(
        onPressed: _testing ? null : _save,
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3),
            foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
        child: _testing
            ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                SizedBox(width: 10), Text('正在验证...'),
              ])
            : const Text('保存并验证', style: TextStyle(fontSize: 16)),
      )),
    ])),
  );

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
}

// ─── Dialog Screen ────────────────────────────────────────────────────────────

class DialogScreen extends StatefulWidget {
  const DialogScreen({Key? key}) : super(key: key);
  @override
  State<DialogScreen> createState() => _DialogScreenState();
}

class _DialogScreenState extends State<DialogScreen> with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _speech = SpeechToText();
  final List<_Msg> _msgs = [];
  bool _loading = false, _listening = false, _speechOk = false;
  String _live = '';
  bool _waiting = false;
  late AnimationController _pulse;

  static const _scenes = [
    ('☕ 咖啡厅', 'You are a barista at a cozy English café. Have a one-question-at-a-time conversation. Ask ONE question, wait for the answer, then respond and ask the next. Correct English mistakes in brackets [Correction: ...].'),
    ('💼 面试', 'You are an English HR interviewer. Ask ONE interview question at a time, evaluate the answer briefly, then ask the next. Correct mistakes in brackets [Correction: ...].'),
    ('🗺️ 问路', 'You are a local in an English-speaking city. Help a tourist one exchange at a time. Correct mistakes in brackets [Correction: ...].'),
    ('🛍️ 购物', 'You are a shop owner in an English market. Have a shopping conversation one exchange at a time. Correct mistakes in brackets [Correction: ...].'),
  ];
  int _si = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    _initSpeech();
    _start();
  }

  Future<void> _initSpeech() async {
    if ((await Permission.microphone.request()).isGranted) {
      _speechOk = await _speech.initialize(
        onError: (_) => setState(() => _listening = false),
        onStatus: (s) { if (s == 'done' || s == 'notListening') _stopListen(); },
      );
      setState(() {});
    }
  }

  Future<void> _start() async {
    final key = context.read<AppState>().apiKey!;
    setState(() { _msgs.clear(); _loading = true; _waiting = false; });
    try {
      final r = await ZhipuService.chat(apiKey: key, messages: [
        {'role': 'system', 'content': _scenes[_si].$2},
        {'role': 'user', 'content': 'Start the conversation by greeting me and asking your first question.'},
      ]);
      setState(() { _msgs.add(_Msg(r, false)); _waiting = true; });
      _scrollDown();
    } catch (e) {
      setState(() => _msgs.add(_Msg('⚠️ 连接失败: $e', false, err: true)));
    } finally { setState(() => _loading = false); }
  }

  Future<void> _send([String? txt]) async {
    final text = (txt ?? _ctrl.text).trim();
    if (text.isEmpty || _loading) return;
    _ctrl.clear();
    setState(() { _msgs.add(_Msg(text, true)); _loading = true; _waiting = false; _live = ''; });
    _scrollDown();
    final key = context.read<AppState>().apiKey!;
    try {
      final r = await ZhipuService.chat(apiKey: key, messages: [
        {'role': 'system', 'content': _scenes[_si].$2},
        ..._msgs.map((m) => {'role': m.isUser ? 'user' : 'assistant', 'content': m.text}),
      ]);
      setState(() { _msgs.add(_Msg(r, false)); _waiting = true; });
      await context.read<AppState>().recordDialog();
    } catch (e) { setState(() => _msgs.add(_Msg('⚠️ 失败: $e', false, err: true))); }
    finally { setState(() => _loading = false); _scrollDown(); }
  }

  Future<void> _toggleListen() async {
    if (_listening) { _stopListen(); return; }
    if (!_speechOk) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请在系统设置中开启麦克风权限')));
      return;
    }
    setState(() { _listening = true; _live = ''; });
    await _speech.listen(
      onResult: (r) { setState(() { _live = r.recognizedWords; if (r.finalResult && _live.isNotEmpty) { _stopListen(); _send(_live); } }); },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_US',
      listenMode: ListenMode.confirmation,
    );
  }

  void _stopListen() { _speech.stop(); setState(() => _listening = false); }
  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF0F4F8),
    appBar: AppBar(
      title: Text(_scenes[_si].$1),
      backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white,
      actions: [PopupMenuButton<int>(
        icon: const Icon(Icons.swap_horiz),
        onSelected: (i) { setState(() => _si = i); _start(); },
        itemBuilder: (_) => _scenes.asMap().entries.map((e) => PopupMenuItem(value: e.key, child: Text(e.value.$1))).toList(),
      )],
    ),
    body: Column(children: [
      Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: const Color(0xFFE8F5E9),
        child: Text(_waiting ? '💬 轮到你回答！可打字或按麦克风说话' : '⏳ AI思考中...',
          style: TextStyle(fontSize: 12, color: _waiting ? const Color(0xFF2E7D32) : Colors.grey), textAlign: TextAlign.center)),
      Expanded(child: ListView.builder(
        controller: _scroll, padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        itemCount: _msgs.length + (_loading ? 1 : 0),
        itemBuilder: (_, i) => i == _msgs.length ? _typing() : _bubble(_msgs[i]),
      )),
      if (_listening && _live.isNotEmpty)
        Container(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200)),
          child: Row(children: [const Icon(Icons.mic, color: Colors.green, size: 16), const SizedBox(width: 6),
            Expanded(child: Text(_live))])),
      _inputBar(),
    ]),
  );

  Widget _inputBar() => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
    decoration: const BoxDecoration(color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, -2))]),
    child: Row(children: [
      Expanded(child: TextField(
        controller: _ctrl,
        decoration: InputDecoration(
          hintText: _listening ? '正在聆听...' : '用英语回答...',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          filled: true, fillColor: const Color(0xFFF5F5F5),
        ),
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => _send(),
        enabled: !_loading && !_listening,
      )),
      const SizedBox(width: 8),
      AnimatedBuilder(animation: _pulse, builder: (_, __) => Transform.scale(
        scale: _listening ? 1.0 + _pulse.value * 0.15 : 1.0,
        child: GestureDetector(onTap: !_loading ? _toggleListen : null,
          child: Container(width: 48, height: 48,
            decoration: BoxDecoration(color: _listening ? Colors.red : const Color(0xFF4CAF50), shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: (_listening ? Colors.red : const Color(0xFF4CAF50)).withOpacity(0.4), blurRadius: _listening ? 12 : 4)]),
            child: Icon(_listening ? Icons.stop : Icons.mic, color: Colors.white, size: 24))),
      )),
      const SizedBox(width: 8),
      GestureDetector(onTap: (!_loading && !_listening) ? _send : null,
        child: Container(width: 48, height: 48,
          decoration: BoxDecoration(color: (!_loading && !_listening) ? const Color(0xFF2196F3) : Colors.grey.shade300, shape: BoxShape.circle),
          child: const Icon(Icons.send, color: Colors.white, size: 22))),
    ]),
  );

  Widget _bubble(_Msg m) => Align(
    alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: EdgeInsets.only(bottom: 10, left: m.isUser ? 48 : 0, right: m.isUser ? 0 : 48),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: m.err ? Colors.red.shade50 : m.isUser ? const Color(0xFF4CAF50) : Colors.white,
        borderRadius: BorderRadius.circular(18).copyWith(
          bottomRight: m.isUser ? const Radius.circular(4) : null,
          bottomLeft: m.isUser ? null : const Radius.circular(4),
        ),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Text(m.text, style: TextStyle(color: m.isUser ? Colors.white : Colors.black87, fontSize: 15, height: 1.4)),
    ),
  );

  Widget _typing() => Align(alignment: Alignment.centerLeft,
    child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(18).copyWith(bottomLeft: const Radius.circular(4)),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4CAF50))),
        SizedBox(width: 8), Text('AI思考中...', style: TextStyle(color: Colors.grey, fontSize: 13)),
      ])));

  @override
  void dispose() { _ctrl.dispose(); _scroll.dispose(); _pulse.dispose(); _speech.stop(); super.dispose(); }
}

class _Msg {
  final String text; final bool isUser; final bool err;
  _Msg(this.text, this.isUser, {this.err = false});
}

// ─── Listening Screen ─────────────────────────────────────────────────────────

class ListeningScreen extends StatefulWidget {
  const ListeningScreen({Key? key}) : super(key: key);
  @override
  State<ListeningScreen> createState() => _ListeningScreenState();
}

class _ListeningScreenState extends State<ListeningScreen> {
  final FlutterTts _tts = FlutterTts();
  final _ctrl = TextEditingController();

  String _sentence = '';
  String _chineseTip = '';
  bool _loading = false;
  bool _playing = false;
  bool _answered = false;
  bool _correct = false;
  int _score = 0;
  int _round = 0;
  bool _revealed = false;

  static const _levels = ['初级', '中级', '高级'];
  int _level = 0;

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.45);
    _tts.setPitch(1.0);
    _tts.setCompletionHandler(() => setState(() => _playing = false));
    _next();
  }

  Future<void> _next() async {
    setState(() { _loading = true; _answered = false; _revealed = false; _ctrl.clear(); _sentence = ''; _chineseTip = ''; });
    final key = context.read<AppState>().apiKey!;
    final lvl = _levels[_level];
    try {
      final raw = await ZhipuService.chat(apiKey: key, messages: [
        {'role': 'system', 'content': 'You generate English listening dictation sentences. Return ONLY a JSON object like: {"sentence":"...","chinese":"..."} No markdown, no extra text.'},
        {'role': 'user', 'content': '生成一个$lvl难度的英语听写句子，10-20个单词，日常生活场景。JSON格式返回。'},
      ]);
      final cleaned = raw.replaceAll(RegExp(r'```json|```'), '').trim();
      final data = jsonDecode(cleaned);
      setState(() {
        _sentence = data['sentence'] ?? '';
        _chineseTip = data['chinese'] ?? '';
        _round++;
      });
      await _play();
    } catch (e) {
      setState(() => _sentence = '加载失败，请重试');
    } finally { setState(() => _loading = false); }
  }

  Future<void> _play() async {
    if (_sentence.isEmpty) return;
    setState(() => _playing = true);
    await _tts.speak(_sentence);
  }

  void _check() {
    final input = _ctrl.text.trim().toLowerCase();
    final answer = _sentence.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    final inputClean = input.replaceAll(RegExp(r'[^\w\s]'), '');
    final correct = inputClean == answer || _similarity(inputClean, answer) > 0.85;
    setState(() { _answered = true; _correct = correct; if (correct) _score++; });
  }

  double _similarity(String a, String b) {
    final wa = a.split(' ').toSet();
    final wb = b.split(' ').toSet();
    if (wb.isEmpty) return 0;
    return wa.intersection(wb).length / wb.length;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF3E5F5),
    appBar: AppBar(
      title: const Text('听力训练'),
      backgroundColor: const Color(0xFF9C27B0), foregroundColor: Colors.white,
      actions: [
        PopupMenuButton<int>(
          icon: const Icon(Icons.tune),
          onSelected: (i) { setState(() => _level = i); _next(); },
          itemBuilder: (_) => _levels.asMap().entries
              .map((e) => PopupMenuItem(value: e.key, child: Text(e.value))).toList(),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircularProgressIndicator(color: Color(0xFF9C27B0)),
            SizedBox(height: 16), Text('AI正在生成句子...', style: TextStyle(color: Colors.grey)),
          ]))
        : Padding(padding: const EdgeInsets.all(20), child: Column(children: [
            // 分数与关卡
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _chip('第 $_round 题', const Color(0xFF9C27B0)),
              _chip('得分 $_score', const Color(0xFF4CAF50)),
              _chip(_levels[_level], const Color(0xFF2196F3)),
            ]),
            const SizedBox(height: 24),

            // 播放按钮
            Container(
              width: double.infinity, padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)]),
              child: Column(children: [
                const Icon(Icons.hearing, size: 48, color: Color(0xFF9C27B0)),
                const SizedBox(height: 16),
                const Text('仔细聆听，然后写下你听到的句子', style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  ElevatedButton.icon(
                    onPressed: _playing ? null : _play,
                    icon: Icon(_playing ? Icons.volume_up : Icons.play_circle),
                    label: Text(_playing ? '播放中...' : '播放句子'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9C27B0), foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _playing ? null : () async { await _tts.setSpeechRate(0.3); await _play(); await _tts.setSpeechRate(0.45); },
                    icon: const Icon(Icons.slow_motion_video),
                    label: const Text('慢速'),
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF9C27B0)),
                  ),
                ]),
              ]),
            ),

            const SizedBox(height: 20),

            // 提示（中文）
            if (!_answered) GestureDetector(
              onTap: () => setState(() => _revealed = !_revealed),
              child: Container(padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.purple.shade200)),
                child: Row(children: [
                  const Icon(Icons.lightbulb_outline, color: Colors.purple, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_revealed ? '中文提示：$_chineseTip' : '点击查看中文提示',
                      style: TextStyle(color: Colors.purple.shade700, fontSize: 13))),
                ])),
            ),

            const SizedBox(height: 16),

            // 输入框
            TextField(
              controller: _ctrl, enabled: !_answered,
              decoration: InputDecoration(
                hintText: '写下你听到的英文句子...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true, fillColor: Colors.white,
              ),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),

            // 答案反馈
            if (_answered) Container(
              width: double.infinity, padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _correct ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _correct ? Colors.green : Colors.red),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_correct ? '✅ 完全正确！' : '❌ 还差一点', style: TextStyle(
                    fontWeight: FontWeight.bold, color: _correct ? Colors.green : Colors.red, fontSize: 16)),
                if (!_correct) ...[
                  const SizedBox(height: 8),
                  const Text('正确答案：', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text(_sentence, style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ]),
            ),

            const Spacer(),

            // 底部按钮
            Row(children: [
              if (!_answered) Expanded(child: ElevatedButton(
                onPressed: _ctrl.text.isEmpty ? null : _check,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9C27B0),
                    foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('提交答案', style: TextStyle(fontSize: 16)),
              )),
              if (_answered) Expanded(child: ElevatedButton.icon(
                onPressed: _next,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('下一句', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9C27B0),
                    foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              )),
            ]),
          ])),
  );

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
    child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
  );

  @override
  void dispose() { _tts.stop(); _ctrl.dispose(); super.dispose(); }
}

// ─── Speaking Screen ──────────────────────────────────────────────────────────

class SpeakingScreen extends StatefulWidget {
  const SpeakingScreen({Key? key}) : super(key: key);
  @override
  State<SpeakingScreen> createState() => _SpeakingScreenState();
}

class _SpeakingScreenState extends State<SpeakingScreen> with SingleTickerProviderStateMixin {
  final SpeechToText _speech = SpeechToText();
  bool _speechOk = false;
  bool _listening = false;
  bool _loading = false;
  String _live = '';
  String _topic = '';
  String _topicCn = '';
  String _spoken = '';
  String _feedback = '';
  int _score = 0;
  int _round = 0;
  late AnimationController _pulse;

  static const _levels = ['初级', '中级', '高级'];
  int _level = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    _initSpeech();
    _nextTopic();
  }

  Future<void> _initSpeech() async {
    if ((await Permission.microphone.request()).isGranted) {
      _speechOk = await _speech.initialize(
        onError: (_) => setState(() => _listening = false),
        onStatus: (s) { if (s == 'done' || s == 'notListening') _stopListen(); },
      );
      setState(() {});
    }
  }

  Future<void> _nextTopic() async {
    setState(() { _loading = true; _spoken = ''; _feedback = ''; _live = ''; _topic = ''; });
    final key = context.read<AppState>().apiKey!;
    final lvl = _levels[_level];
    try {
      final raw = await ZhipuService.chat(apiKey: key, messages: [
        {'role': 'system', 'content': 'Generate English speaking practice topics. Return ONLY JSON: {"topic":"...","chinese":"..."} No markdown.'},
        {'role': 'user', 'content': '生成一个$lvl难度的英语口语话题，要求用户用2-4句英语回答，话题贴近日常生活。JSON格式返回。'},
      ]);
      final data = jsonDecode(raw.replaceAll(RegExp(r'```json|```'), '').trim());
      setState(() { _topic = data['topic'] ?? ''; _topicCn = data['chinese'] ?? ''; _round++; });
    } catch (e) { setState(() => _topic = '加载失败，请重试'); }
    finally { setState(() => _loading = false); }
  }

  Future<void> _evaluate() async {
    if (_spoken.isEmpty) return;
    setState(() => _loading = true);
    final key = context.read<AppState>().apiKey!;
    try {
      final fb = await ZhipuService.chat(apiKey: key, messages: [
        {'role': 'system', 'content': 'You are an English speaking coach. Evaluate the user\'s spoken English. Give: 1) A score out of 10, 2) What was good, 3) Grammar/vocabulary corrections, 4) A better version of what they said. Be encouraging but honest. Reply in Chinese mixed with English examples.'},
        {'role': 'user', 'content': '话题：$_topic\n\n用户的回答：$_spoken\n\n请评估并给出反馈。'},
      ]);
      setState(() { _feedback = fb; _score++; });
      await context.read<AppState>().recordDialog();
    } catch (e) { setState(() => _feedback = '⚠️ 评估失败: $e'); }
    finally { setState(() => _loading = false); }
  }

  Future<void> _toggleListen() async {
    if (_listening) { _stopListen(); return; }
    if (!_speechOk) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请在系统设置中开启麦克风权限')));
      return;
    }
    setState(() { _listening = true; _live = ''; _spoken = ''; _feedback = ''; });
    await _speech.listen(
      onResult: (r) {
        setState(() {
          _live = r.recognizedWords;
          if (r.finalResult) { _spoken = _live; _stopListen(); }
        });
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 4),
      localeId: 'en_US',
      listenMode: ListenMode.dictation,
    );
  }

  void _stopListen() { _speech.stop(); setState(() => _listening = false); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFFF8E1),
    appBar: AppBar(
      title: const Text('口语练习'),
      backgroundColor: const Color(0xFFFF9800), foregroundColor: Colors.white,
      actions: [
        PopupMenuButton<int>(
          icon: const Icon(Icons.tune),
          onSelected: (i) { setState(() => _level = i); _nextTopic(); },
          itemBuilder: (_) => _levels.asMap().entries
              .map((e) => PopupMenuItem(value: e.key, child: Text(e.value))).toList(),
        ),
      ],
    ),
    body: _loading && _topic.isEmpty
        ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircularProgressIndicator(color: Color(0xFFFF9800)),
            SizedBox(height: 16), Text('AI正在生成话题...', style: TextStyle(color: Colors.grey)),
          ]))
        : SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
            // 头部信息
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _chip('第 $_round 题', const Color(0xFFFF9800)),
              _chip('完成 $_score 题', const Color(0xFF4CAF50)),
              _chip(_levels[_level], const Color(0xFF2196F3)),
            ]),
            const SizedBox(height: 20),

            // 话题卡片
            Container(
              width: double.infinity, padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.record_voice_over, color: Color(0xFFFF9800)),
                  const SizedBox(width: 8),
                  const Text('口语话题', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF9800))),
                ]),
                const SizedBox(height: 12),
                Text(_topic, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.5)),
                const SizedBox(height: 8),
                Text(_topicCn, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 12),
                const Text('请用2-4句英语回答以上话题', style: TextStyle(color: Colors.orange, fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 20),

            // 录音区
            Container(
              width: double.infinity, padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)]),
              child: Column(children: [
                AnimatedBuilder(animation: _pulse, builder: (_, __) => Transform.scale(
                  scale: _listening ? 1.0 + _pulse.value * 0.1 : 1.0,
                  child: GestureDetector(
                    onTap: (!_loading && _feedback.isEmpty) ? _toggleListen : null,
                    child: Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        color: _listening ? Colors.red : (_spoken.isNotEmpty ? Colors.green : const Color(0xFFFF9800)),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                          color: (_listening ? Colors.red : const Color(0xFFFF9800)).withOpacity(0.4),
                          blurRadius: _listening ? 20 : 8,
                        )],
                      ),
                      child: Icon(_listening ? Icons.stop : Icons.mic, color: Colors.white, size: 36),
                    ),
                  ),
                )),
                const SizedBox(height: 12),
                Text(
                  _listening ? '正在录音，说完后停顿即可...' : (_spoken.isNotEmpty ? '录音完成，点击评估' : '点击麦克风开始说话'),
                  style: TextStyle(color: _listening ? Colors.red : Colors.grey, fontSize: 13),
                ),

                // 实时识别
                if (_listening && _live.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.shade200)),
                    child: Text(_live, style: const TextStyle(fontSize: 14))),
                ],

                // 已录制内容
                if (_spoken.isNotEmpty && !_listening) ...[
                  const SizedBox(height: 12),
                  Container(width: double.infinity, padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade200)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('你说的：', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(_spoken, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    ])),
                ],
              ]),
            ),
            const SizedBox(height: 16),

            // AI反馈
            if (_loading && _spoken.isNotEmpty)
              const Center(child: Column(children: [
                CircularProgressIndicator(color: Color(0xFFFF9800)),
                SizedBox(height: 8), Text('AI正在评估你的口语...', style: TextStyle(color: Colors.grey)),
              ])),

            if (_feedback.isNotEmpty) ...[
              Container(width: double.infinity, padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                    border: Border.all(color: Colors.orange.shade200)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.school, color: Color(0xFFFF9800)), SizedBox(width: 8),
                    Text('AI评估报告', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF9800))),
                  ]),
                  const SizedBox(height: 12),
                  Text(_feedback, style: const TextStyle(fontSize: 14, height: 1.6)),
                ])),
              const SizedBox(height: 16),
            ],

            // 按钮
            if (_spoken.isNotEmpty && _feedback.isEmpty && !_loading)
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                onPressed: _evaluate,
                icon: const Icon(Icons.analytics),
                label: const Text('AI评估口语', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9800),
                    foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              )),

            if (_feedback.isNotEmpty)
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                onPressed: _nextTopic,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('下一个话题', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9800),
                    foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              )),
          ])),
  );

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
    child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
  );

  @override
  void dispose() { _pulse.dispose(); _speech.stop(); super.dispose(); }
}

// ─── Stats Screen ─────────────────────────────────────────────────────────────

class StatsScreen extends StatelessWidget {
  const StatsScreen({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('学习统计'), backgroundColor: const Color(0xFF2196F3), foregroundColor: Colors.white),
      body: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        _card('📅 今日练习次数', '${s.todayDialogs} 次', const Color(0xFF4CAF50)),
        const SizedBox(height: 16),
        _card('📊 累计练习次数', '${s.totalDialogs} 次', const Color(0xFF2196F3)),
        const SizedBox(height: 16),
        _card('🔥 连续学习天数', '${s.streak} 天', const Color(0xFFFF5722)),
        const SizedBox(height: 32),
        const Text('坚持每天练习，英语水平会稳步提升！', style: TextStyle(color: Colors.grey, fontSize: 14), textAlign: TextAlign.center),
      ])),
    );
  }

  Widget _card(String label, String value, Color color) => Container(
    width: double.infinity, padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)]),
    child: Row(children: [
      Text(label, style: const TextStyle(fontSize: 16)), const Spacer(),
      Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
    ]),
  );
}