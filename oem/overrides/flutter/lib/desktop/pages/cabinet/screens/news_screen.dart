import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_theme.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/click_sound.dart';
import 'package:http/http.dart' as http;

const _kNewsUrl = 'https://deskforce.dr6ter.ru/downloads/news.json';

class CabinetNewsScreen extends StatefulWidget {
  const CabinetNewsScreen({Key? key}) : super(key: key);

  @override
  State<CabinetNewsScreen> createState() => _CabinetNewsScreenState();
}

class _CabinetNewsScreenState extends State<CabinetNewsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _error = '';
  String? _expandedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = await http
          .get(Uri.parse(_kNewsUrl))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      final list = <Map<String, dynamic>>[];
      if (json is Map && json['items'] is List) {
        for (final e in json['items'] as List) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      } else if (json is List) {
        for (final e in json) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить новости. Проверьте сеть.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Row(
            children: [
              Expanded(
                child: DfCabinetTheme.heading('Новости',
                    subtitle: 'Анонсы и новости программы DeskForce.'),
              ),
              IconButton(
                tooltip: 'Обновить',
                onPressed: _loading ? null : dfClickWrap(_load),
                icon: const Icon(Icons.refresh, color: DfCabinetTheme.brass),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: DfCabinetTheme.brass))
              : _error.isNotEmpty && _items.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error,
                            style:
                                const TextStyle(color: DfCabinetTheme.danger)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          style: DfCabinetTheme.primaryButton(),
                          onPressed: dfClickWrap(_load),
                          child: const Text('Повторить'),
                        ),
                      ]),
                    )
                  : _items.isEmpty
                      ? Center(
                          child: Text('Пока нет новостей',
                              style: TextStyle(
                                  color:
                                      DfCabinetTheme.ink.withOpacity(0.5))))
                      : RefreshIndicator(
                          color: DfCabinetTheme.brass,
                          onRefresh: _load,
                          child: ListView.separated(
                            padding:
                                const EdgeInsets.fromLTRB(28, 0, 28, 32),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final n = _items[i];
                              final id = (n['id'] ?? '$i').toString();
                              final expanded = _expandedId == id;
                              final tag = (n['tag'] ?? '').toString();
                              final date = (n['date'] ?? '').toString();
                              final title = (n['title'] ?? '').toString();
                              final summary =
                                  (n['summary'] ?? '').toString();
                              final body = (n['body'] ?? summary).toString();
                              return DfCabinetTheme.panel(
                                child: InkWell(
                                  onTap: dfClickWrap(() {
                                    setState(() {
                                      _expandedId = expanded ? null : id;
                                    });
                                  }),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          if (tag.isNotEmpty)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                              decoration: BoxDecoration(
                                                color: const Color(0x262DD4BF),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                tag.toUpperCase(),
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    letterSpacing: 0.8,
                                                    color: DfCabinetTheme
                                                        .brassDeep),
                                              ),
                                            ),
                                          if (tag.isNotEmpty)
                                            const SizedBox(width: 8),
                                          Text(
                                            date,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: DfCabinetTheme.ink
                                                    .withOpacity(0.45)),
                                          ),
                                          const Spacer(),
                                          Icon(
                                            expanded
                                                ? Icons.expand_less
                                                : Icons.expand_more,
                                            color: DfCabinetTheme.ink
                                                .withOpacity(0.45),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        title,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                            color: DfCabinetTheme.ink),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        expanded ? body : summary,
                                        style: TextStyle(
                                            fontSize: 14,
                                            height: 1.35,
                                            color: DfCabinetTheme.ink
                                                .withOpacity(0.7)),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}
