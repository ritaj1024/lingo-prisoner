import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'app_state.dart';

class TranslationScreen extends StatefulWidget {
  const TranslationScreen({Key? key}) : super(key: key);
  @override
  State<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends State<TranslationScreen>
    with SingleTickerProviderStateMixin {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final _textCtrl = TextEditingController();

  bool _speechOk = false;
  bool _listening = false;
  bool _translating = false;
  bool _playing = false;
  String _live = '';
  String _original = '';
  String _translated = '';
  String _detectedLang = '';
  String _targetLang = '';
  final List<_TransRecord> _history = [];
  late AnimationController _pulse;

  // 系统提示：自动检测语言并翻译
  static const _sysPrompt =
      'You are a professional translation engine. '
      'Detect the language of the input. '
      'If Chinese -> translate to English. '
      'If any other language (English, Japanese, Korean, French, Spanish, etc.) -> translate to Chinese. '
      'Return ONLY valid JSON, no markdown, no explanation: '
      '{"detected_lang":"<语言名称，用中文，如：中文/英文/日文/韩文/法文>","target_lang":"<中文 or 英文>","translation":"<translated text>"}';

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _tts.setCompletionHandler(() => setState(() => _playing = false));
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    if ((await Permission.microphone.request()).isGranted) {
      _speechOk = await _speech.initialize(
        onError: (_) => setState(() => _listening = false),
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') _onDone();
        },
      );
      setState(() {});
    }
  }

  Future<void> _toggleListen() async {
    if (_listening) {
      _stopListen();
      return;
    }
    if (!_speechOk) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请在系统设置中开启麦克风权限')));
      return;
    }
    setState(() {
      _listening = true;
      _live = '';
      _original = '';
      _translated = '';
      _detectedLang = '';
    });
    await _speech.listen(
      onResult: (r) {
        setState(() {
          _live = r.recognizedWords;
          if (r.finalResult && _live.isNotEmpty) {
            _original = _live;
            _stopListen();
            _translate(_original);
          }
        });
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 2),
      listenMode: ListenMode.dictation,
    );
  }

  void _stopListen() {
    _speech.stop();
    setState(() => _listening = false);
  }

  void _onDone() {
    if (_listening) {
      _stopListen();
      if (_live.isNotEmpty && _original.isEmpty) {
        _original = _live;
        _translate(_original);
      }
    }
  }

  Future<void> _translate(String text) async {
    if (text.trim().isEmpty) return;
    final apiKey = context.read<AppState>().apiKey!;
    setState(() {
      _translating = true;
      _translated = '';
      _detectedLang = '';
    });
    try {
      final raw = await ZhipuService.chat(apiKey: apiKey, messages: [
        {'role': 'system', 'content': _sysPrompt},
        {'role': 'user', 'content': text},
      ]);
      final cleaned = raw.replaceAll(RegExp(r'```json|```'), '').trim();
      final data = jsonDecode(cleaned);
      final record = _TransRecord(
        original: text,
        translated: data['translation'] ?? '',
        detectedLang: data['detected_lang'] ?? '',
        targetLang: data['target_lang'] ?? '',
      );
      setState(() {
        _translated = record.translated;
        _detectedLang = record.detectedLang;
        _targetLang = record.targetLang;
        _history.insert(0, record);
        if (_history.length > 20) _history.removeLast();
      });
    } catch (e) {
      setState(() => _translated = '⚠️ 翻译失败: $e');
    } finally {
      setState(() => _translating = false);
    }
  }

  Future<void> _translateText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _original = text);
    _textCtrl.clear();
    await _translate(text);
  }

  Future<void> _speak(String text, String lang) async {
    setState(() => _playing = true);
    await _tts.setLanguage(
        (lang.contains('英') || lang == 'English') ? 'en-US' : 'zh-CN');
    await _tts.setSpeechRate(0.5);
    await _tts.speak(text);
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFE0F7FA),
        appBar: AppBar(
          title: const Text('语音翻译'),
          backgroundColor: const Color(0xFF00BCD4),
          foregroundColor: Colors.white,
          actions: [
            if (_history.isNotEmpty)
              IconButton(
                  icon: const Icon(Icons.history),
                  tooltip: '历史记录',
                  onPressed: () => _showHistory(context)),
          ],
        ),
        body: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFFB2EBF2),
            child: const Text(
                '自动检测语言 · 中文→英文 · 其他语言→中文',
                style: TextStyle(fontSize: 12, color: Color(0xFF00838F)),
                textAlign: TextAlign.center),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _micButton(),
                const SizedBox(height: 20),
                if (_listening && _live.isNotEmpty) _liveCard(),
                if (_original.isNotEmpty && !_listening) _originalCard(),
                if (_translating)
                  const Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(children: [
                        CircularProgressIndicator(color: Color(0xFF00BCD4)),
                        SizedBox(height: 8),
                        Text('正在翻译...', style: TextStyle(color: Colors.grey)),
                      ])),
                if (_translated.isNotEmpty && !_translating) _translatedCard(),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('或者直接输入文字翻译',
                        style: TextStyle(color: Colors.grey, fontSize: 13))),
                const SizedBox(height: 10),
                _textInputArea(),
              ]),
            ),
          ),
        ]),
      );

  Widget _micButton() => AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) => Transform.scale(
          scale: _listening ? 1.0 + _pulse.value * 0.08 : 1.0,
          child: GestureDetector(
            onTap: !_translating ? _toggleListen : null,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _listening ? Colors.red : const Color(0xFF00BCD4),
                boxShadow: [
                  BoxShadow(
                    color: (_listening ? Colors.red : const Color(0xFF00BCD4))
                        .withOpacity(0.4),
                    blurRadius: _listening ? 24 : 10,
                    spreadRadius: _listening ? 4 : 0,
                  )
                ],
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_listening ? Icons.stop : Icons.mic,
                        color: Colors.white, size: 44),
                    const SizedBox(height: 4),
                    Text(_listening ? '停止' : '说话',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12)),
                  ]),
            ),
          ),
        ),
      );

  Widget _liveCard() => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF00BCD4), width: 2)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.mic, color: Color(0xFF00BCD4), size: 16),
            SizedBox(width: 6),
            Text('正在识别...',
                style: TextStyle(
                    color: Color(0xFF00BCD4),
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          Text(_live, style: const TextStyle(fontSize: 16, height: 1.5)),
        ]),
      );

  Widget _originalCard() => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              const Icon(Icons.record_voice_over, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                  _detectedLang.isNotEmpty ? '原文（$_detectedLang）' : '原文',
                  style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ]),
            Row(children: [
              IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => _copy(_original),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints()),
              const SizedBox(width: 8),
              IconButton(
                  icon: Icon(
                      _playing ? Icons.volume_up : Icons.play_circle_outline,
                      size: 18,
                      color: const Color(0xFF00BCD4)),
                  onPressed:
                      _playing ? null : () => _speak(_original, _detectedLang),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints()),
            ]),
          ]),
          const SizedBox(height: 8),
          Text(_original, style: const TextStyle(fontSize: 16, height: 1.5)),
        ]),
      );

  Widget _translatedCard() => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF00BCD4), Color(0xFF0097A7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              const Icon(Icons.translate, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Text('翻译结果（$_targetLang）',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ]),
            Row(children: [
              IconButton(
                  icon: const Icon(Icons.copy, size: 18, color: Colors.white),
                  onPressed: () => _copy(_translated),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints()),
              const SizedBox(width: 8),
              IconButton(
                  icon: Icon(
                      _playing ? Icons.volume_up : Icons.play_circle_outline,
                      size: 18,
                      color: Colors.white),
                  onPressed:
                      _playing ? null : () => _speak(_translated, _targetLang),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints()),
            ]),
          ]),
          const SizedBox(height: 8),
          Text(_translated,
              style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  height: 1.5,
                  fontWeight: FontWeight.w500)),
        ]),
      );

  Widget _textInputArea() => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _textCtrl,
              decoration: InputDecoration(
                hintText: '输入任意语言文字进行翻译...',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.all(14),
              ),
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _translateText(),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _translating ? null : _translateText,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _translating
                    ? Colors.grey.shade300
                    : const Color(0xFF00BCD4),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 22),
            ),
          ),
        ],
      );

  void _showHistory(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (_, ctrl) => Column(children: [
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text('翻译历史',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          Expanded(
            child: ListView.separated(
              controller: ctrl,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _history.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = _history[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  title: Text(r.original,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(r.translated,
                      style: const TextStyle(
                          color: Color(0xFF00BCD4), fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  trailing: Text('${r.detectedLang}→${r.targetLang}',
                      style:
                          const TextStyle(fontSize: 10, color: Colors.grey)),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _original = r.original;
                      _translated = r.translated;
                      _detectedLang = r.detectedLang;
                      _targetLang = r.targetLang;
                    });
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    _speech.stop();
    _tts.stop();
    _textCtrl.dispose();
    super.dispose();
  }
}

class _TransRecord {
  final String original, translated, detectedLang, targetLang;
  _TransRecord(
      {required this.original,
      required this.translated,
      required this.detectedLang,
      required this.targetLang});
}
