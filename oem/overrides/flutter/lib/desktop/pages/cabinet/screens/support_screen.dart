import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_api.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_errors.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_theme.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/click_sound.dart';

class CabinetSupportScreen extends StatefulWidget {
  const CabinetSupportScreen({Key? key}) : super(key: key);

  @override
  State<CabinetSupportScreen> createState() => _CabinetSupportScreenState();
}

class _CabinetSupportScreenState extends State<CabinetSupportScreen> {
  List<Map<String, dynamic>> _threads = [];
  List<Map<String, dynamic>> _messages = [];
  int? _threadId;
  String _email = '';
  String _telegram = '';
  String _welcome = '';
  final _body = TextEditingController();
  final _subject = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _body.dispose();
    _subject.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final data = await CabinetApi.instance.get('/support');
      final map = Map<String, dynamic>.from(data as Map);
      final threads = <Map<String, dynamic>>[];
      if (map['threads'] is List) {
        for (final t in map['threads']) {
          if (t is Map) threads.add(Map<String, dynamic>.from(t));
        }
      }
      int? tid;
      if (map['thread'] is Map) {
        tid = (map['thread']['id'] as num?)?.toInt();
      } else if (threads.isNotEmpty) {
        tid = (threads.first['id'] as num?)?.toInt();
      }
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _threadId = tid;
        _email = (map['email'] ?? '').toString();
        _telegram = (map['telegram'] ?? '').toString();
        _welcome = (map['welcome'] ?? '').toString();
        _loading = false;
      });
      if (tid != null) await _loadMessages(tid);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = dfCabinetError(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadMessages(int threadId) async {
    try {
      final data = await CabinetApi.instance.get('/support/messages', query: {
        'thread_id': '$threadId',
      });
      final list = <Map<String, dynamic>>[];
      if (data is Map && data['records'] is List) {
        for (final m in data['records']) {
          if (m is Map) list.add(Map<String, dynamic>.from(m));
        }
      }
      if (!mounted) return;
      setState(() {
        _threadId = threadId;
        _messages = list;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = dfCabinetError(e));
    }
  }

  Future<void> _send() async {
    final text = _body.text.trim();
    if (text.isEmpty) return;
    await dfPlayClickSound();
    setState(() {
      _sending = true;
      _error = '';
    });
    try {
      final api = CabinetApi.instance;
      if (_threadId == null) {
        final res = await api.post('/support/threads', body: {
          'subject': _subject.text.trim().isEmpty ? text : _subject.text.trim(),
          'body': text,
        });
        final th = res is Map ? res['thread'] : null;
        final tid = th is Map ? (th['id'] as num?)?.toInt() : null;
        _body.clear();
        _subject.clear();
        await _load();
        if (tid != null) await _loadMessages(tid);
      } else {
        await api.post('/support/messages', body: {
          'thread_id': _threadId,
          'body': text,
        });
        _body.clear();
        await _loadMessages(_threadId!);
      }
    } catch (e) {
      setState(() => _error = dfCabinetError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: DfCabinetTheme.brass));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
          child: Row(
            children: [
              Expanded(
                child: DfCabinetTheme.heading('Поддержка',
                    subtitle: _welcome.isNotEmpty
                        ? _welcome
                        : 'Чат со специалистами DeskForce УД.'),
              ),
              IconButton(
                onPressed: dfClickWrap(_load),
                icon: const Icon(Icons.refresh, color: DfCabinetTheme.brass),
              ),
            ],
          ),
        ),
        if (_email.isNotEmpty || _telegram.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              [
                if (_email.isNotEmpty) _email,
                if (_telegram.isNotEmpty) _telegram,
              ].join(' · '),
              style: TextStyle(
                  fontSize: 12, color: DfCabinetTheme.ink.withOpacity(0.5)),
            ),
          ),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
            child: Text(_error,
                style: const TextStyle(color: DfCabinetTheme.danger)),
          ),
        if (_threads.length > 1)
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(28, 10, 28, 0),
              itemCount: _threads.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final t = _threads[i];
                final id = (t['id'] as num?)?.toInt();
                final selected = id == _threadId;
                return ChoiceChip(
                  label: Text((t['subject'] ?? '#$id').toString(),
                      style: TextStyle(
                          fontSize: 12,
                          color: selected
                              ? Colors.white
                              : DfCabinetTheme.ink)),
                  selected: selected,
                  selectedColor: DfCabinetTheme.brass,
                  onSelected: (_) {
                    if (id != null) _loadMessages(id);
                  },
                );
              },
            ),
          ),
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Text(
                    _threadId == null
                        ? 'Напишите первое сообщение — создадим обращение.'
                        : 'Пока нет сообщений',
                    style: TextStyle(
                        color: DfCabinetTheme.ink.withOpacity(0.5)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
                  itemCount: _messages.length,
                  itemBuilder: (context, i) {
                    final m = _messages[i];
                    final role = (m['author_role'] ?? m['role'] ?? '').toString();
                    final mine = role == 'user' ||
                        m['from_user'] == true ||
                        m['is_user'] == true;
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        constraints: const BoxConstraints(maxWidth: 480),
                        decoration: BoxDecoration(
                          color: mine
                              ? const Color(0xFFE8D7A8)
                              : DfCabinetTheme.card,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: DfCabinetTheme.border),
                        ),
                        child: Text(
                          (m['body'] ?? m['message'] ?? '').toString(),
                          style: const TextStyle(
                              color: DfCabinetTheme.ink, height: 1.35),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          decoration: const BoxDecoration(
            color: DfCabinetTheme.bar,
            border: Border(top: BorderSide(color: DfCabinetTheme.border)),
          ),
          child: Column(
            children: [
              if (_threadId == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    style: DfCabinetTheme.inputStyle,
                    cursorColor: DfCabinetTheme.brass,
                    controller: _subject,
                    decoration: DfCabinetTheme.field('Тема (необязательно)'),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                    style: DfCabinetTheme.inputStyle,
                    cursorColor: DfCabinetTheme.brass,
                      controller: _body,
                      minLines: 1,
                      maxLines: 4,
                      decoration: DfCabinetTheme.field('Сообщение'),
                      onSubmitted: (_) => _sending ? null : _send(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: DfCabinetTheme.primaryButton(),
                    onPressed: _sending ? null : _send,
                    child: Text(_sending ? '…' : 'Отправить',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
