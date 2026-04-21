import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

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
      await chat(
        apiKey: apiKey,
        messages: [{'role': 'user', 'content': 'Hi'}],
      );
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
            // API Key 提示
            if (state.apiKey == null || state.apiKey!.isEmpty)
              _buildApiKeyBanner(context),

            // 统计卡片
            _buildStatsRow(state),
            const SizedBox(height: 20),

            const Text('学习功能', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            // 功能卡片
            _buildFeatureCard(
              context,
              icon: Icons.chat_bubble_outline,
              title: '情景对话',
              subtitle: '与AI进行英语对话练习',
              color: const Color(0xFF4CAF50),
              progress: 0.9,
              onTap: state.apiKey?.isNotEmpty == true
                  ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DialogScreen()))
                  : () => _showNeedApiKey(context),
            ),
            const SizedBox(height: 12),
            _buildFeatureCard(
              context,
              icon: Icons.hearing,
              title: '听力训练',
              subtitle: '听AI朗读，训练英语听力',
              color: const Color(0xFF9C27B0),
              progress: 0.8,
              badge: '开发中',
              onTap: () => _showComingSoon(context, '听力训练'),
            ),
            const SizedBox(height: 12),
            _buildFeatureCard(
              context,
              icon: Icons.mic,
              title: '口语练习',
              subtitle: '开口说英语，AI纠正发音',
              color: const Color(0xFFFF9800),
              progress: 0.7,
              badge: '开发中',
              onTap: () => _showComingSoon(context, '口语练习'),
            ),
            const SizedBox(height: 20),
            const Text('工具', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildFeatureCard(
              context,
              icon: Icons.lock,
              title: '监狱模式',
              subtitle: '完成学习目标才能解锁手机',
              color: const Color(0xFFF44336),
              progress: 0.6,
              badge: '开发中',
              onTap: () => _showComingSoon(context, '监狱模式'),
            ),
            const SizedBox(height: 12),
            _buildFeatureCard(
              context,
              icon: Icons.bar_chart,
              title: '学习统计',
              subtitle: '查看学习进度和数据',
              color: const Color(0xFF2196F3),
              progress: 1.0,
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const StatsScreen())),
            ),
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
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
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
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
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
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required double progress,
    required VoidCallback onTap,
    String? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: const Offset(0, 2))],
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
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
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
                    color: color,
                    minHeight: 4,
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('请先在设置中填写智谱AI API Key'),
        action: SnackBarAction(
          label: '去设置',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
      ),
    );
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
    if (apiKey.isEmpty) {
      _snack('请输入API Key', isError: true);
      return;
    }

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
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
      ),
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
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                          SizedBox(width: 10),
                          Text('正在验证...'),
                        ],
                      )
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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

// ─── Dialog Screen ────────────────────────────────────────────────────────────

class DialogScreen extends StatefulWidget {
  const DialogScreen({Key? key}) : super(key: key);

  @override
  State<DialogScreen> createState() => _DialogScreenState();
}

class _DialogScreenState extends State<DialogScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_Message> _messages = [];
  bool _isLoading = false;

  static const _scenarios = [
    ('咖啡厅点单', '你是咖啡厅服务员，用英文接待顾客点单，保持友好自然，偶尔纠正用户英语错误并给出正确用法。'),
    ('面试对话', '你是HR面试官，用英文进行求职面试，问一些常见问题，保持专业，纠正用户英语表达。'),
    ('问路指路', '你是路人，用英文帮助问路，场景在英语国家，自然对话，纠正用户英语错误。'),
    ('购物还价', '你是商店店员，用英文接待顾客，涉及商品询问和价格，保持真实自然的购物场景。'),
  ];

  String _currentScenario = _scenarios[0].$1;
  String _currentPrompt = _scenarios[0].$2;
  bool _scenarioStarted = false;

  @override
  void initState() {
    super.initState();
    _startScenario();
  }

  Future<void> _startScenario() async {
    final apiKey = context.read<AppState>().apiKey!;
    setState(() {
      _messages.clear();
      _isLoading = true;
      _scenarioStarted = false;
    });

    try {
      final reply = await ZhipuService.chat(
        apiKey: apiKey,
        messages: [
          {'role': 'system', 'content': _currentPrompt + '用英文开始对话，中文注释关键词。'},
          {'role': 'user', 'content': 'Start the conversation.'},
        ],
      );
      setState(() {
        _messages.add(_Message(text: reply, isUser: false));
        _scenarioStarted = true;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() => _messages.add(_Message(text: '⚠️ 连接失败: $e\n请检查网络和API Key', isUser: false, isError: true)));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    _controller.clear();
    setState(() {
      _messages.add(_Message(text: text, isUser: true));
      _isLoading = true;
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
          {'role': 'system', 'content': _currentPrompt + '如果用户英语有错误，先自然回应，再用括号【纠正：正确用法】指出。'},
          ...history,
        ],
      );
      setState(() => _messages.add(_Message(text: reply, isUser: false)));
      await context.read<AppState>().recordDialog();
    } catch (e) {
      setState(() => _messages.add(_Message(text: '⚠️ 发送失败: $e', isUser: false, isError: true)));
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
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
      appBar: AppBar(
        title: Text(_currentScenario),
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.swap_horiz),
            tooltip: '切换场景',
            onSelected: (i) {
              setState(() {
                _currentScenario = _scenarios[i].$1;
                _currentPrompt = _scenarios[i].$2;
              });
              _startScenario();
            },
            itemBuilder: (_) => _scenarios
                .asMap()
                .entries
                .map((e) => PopupMenuItem(value: e.key, child: Text(e.value.$1)))
                .toList(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 场景说明
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFFE8F5E9),
            child: Text('场景：$_currentScenario  |  右上角可切换场景',
                style: const TextStyle(fontSize: 12, color: Color(0xFF388E3C))),
          ),
          // 消息列表
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _messages.length) return _buildTyping();
                return _buildBubble(_messages[i]);
              },
            ),
          ),
          // 输入框
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: '用英语回复...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    enabled: !_isLoading,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isLoading ? null : _send,
                  icon: const Icon(Icons.send),
                  color: const Color(0xFF4CAF50),
                  iconSize: 28,
                ),
              ],
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
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: msg.isError
              ? Colors.red.shade50
              : msg.isUser
                  ? const Color(0xFF4CAF50)
                  : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            color: msg.isUser ? Colors.white : Colors.black87,
            fontSize: 15,
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 6, height: 6, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('AI正在回复...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
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
      appBar: AppBar(
        title: const Text('学习统计'),
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
      ),
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
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
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