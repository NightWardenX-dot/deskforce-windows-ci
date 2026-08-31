import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_api.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';

/// Shared cabinet session — surfaces license, devices, tickets on the main UI.
class DfCabinetSession extends GetxController {
  static DfCabinetSession get to {
    if (!Get.isRegistered<DfCabinetSession>()) {
      Get.put(DfCabinetSession(), permanent: true);
    }
    return Get.find<DfCabinetSession>();
  }

  static void ensure() {
    if (!Get.isRegistered<DfCabinetSession>()) {
      Get.put(DfCabinetSession(), permanent: true);
    }
  }

  static const _presenceInterval = Duration(seconds: 90);

  final loggedIn = false.obs;
  final loading = false.obs;
  final username = ''.obs;
  final displayName = ''.obs;
  final email = ''.obs;
  final plan = ''.obs;
  final licenseActive = false.obs;
  final concurrentLimit = 0.obs;
  final concurrentUsed = 0.obs;
  final overLimit = false.obs;
  final deviceCount = 0.obs;
  final onlineDevices = 0.obs;
  final openTickets = 0.obs;
  final licensedDevices = 0.obs;
  final chatCallsEnabled = false.obs;
  final localIdLinked = false.obs;
  final localDeviceId = ''.obs;
  final devices = <Map<String, dynamic>>[].obs;
  final lastError = ''.obs;

  Timer? _presenceTimer;

  @override
  void onInit() {
    super.onInit();
    refresh();
    _schedulePresenceSync();
  }

  @override
  void onClose() {
    _presenceTimer?.cancel();
    super.onClose();
  }

  String get chipLabel {
    if (!loggedIn.value) return 'Войти в кабинет';
    final name = displayName.value.isNotEmpty
        ? displayName.value
        : username.value;
    if (name.isEmpty) return 'Кабинет';
    return name;
  }

  String get licenseLabel {
    if (!loggedIn.value) return '';
    if (!licenseActive.value) return 'Лицензия не активна';
    final p = plan.value.isEmpty ? 'тариф' : plan.value;
    return '$p · ${concurrentUsed.value}/${concurrentLimit.value} удал. сессий';
  }

  /// User-facing hint for concurrent remote sessions (not cabinet logins).
  String get sessionsHint {
    if (!loggedIn.value || !licenseActive.value) return '';
    final limit = concurrentLimit.value;
    final used = concurrentUsed.value;
    if (limit <= 0) return '';
    return 'Сессия — одно одновременное удалённое подключение к любому ПК в сети DeskForce '
        '(не вход в кабинет). Сейчас занято: $used из $limit.';
  }

  /// Online devices that currently hold remote sessions (conns > 0 when known).
  List<Map<String, dynamic>> get sessionDevices {
    final out = <Map<String, dynamic>>[];
    for (final d in devices) {
      if (d['is_online'] != true) continue;
      final conns = d['conns'];
      if (conns is num && conns <= 0) continue;
      out.add(d);
    }
    if (out.isNotEmpty) return out;
    return devices.where((d) => d['is_online'] == true).toList();
  }

  void _schedulePresenceSync() {
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(_presenceInterval, (_) {
      if (CabinetApi.instance.isLoggedIn) {
        // ignore: unawaited_futures
        _syncPresence();
      }
    });
  }

  Future<void> _syncPresence() async {
    if (!CabinetApi.instance.isLoggedIn) return;
    final id = _readLocalId();
    if (id.isEmpty) return;
    await claimLocalDevice(quiet: true);
    await refresh();
  }

  bool get _localServiceOnline {
    try {
      return stateGlobal.svcStatus.value == SvcStatus.ready;
    } catch (_) {
      return true;
    }
  }

  List<Map<String, dynamic>> _normalizeDevices(
      List<Map<String, dynamic>> list, String localId) {
    if (localId.isEmpty) return list;
    return list.map((d) {
      if ((d['device_id'] ?? '').toString() != localId) return d;
      final copy = Map<String, dynamic>.from(d);
      copy['is_local'] = true;
      // Prefer live service state for «этот ПК»; server heartbeat may lag.
      if (_localServiceOnline) {
        copy['is_online'] = true;
      }
      return copy;
    }).toList();
  }

  Future<void> refresh() async {
    if (!CabinetApi.instance.isLoggedIn) {
      // Soft clear only — never call mainClearAb / wipe access_token on cold start
      // when the user simply is not in the cabinet (beta.13 reset-ab-on-boot).
      _clearUiState();
      return;
    }
    loading.value = true;
    lastError.value = '';
    try {
      final api = CabinetApi.instance;
      final meRaw = await api.get('/me');
      final me = Map<String, dynamic>.from(meRaw as Map);
      Map<String, dynamic>? lic;
      try {
        final l = await api.get('/billing/license');
        if (l is Map) lic = Map<String, dynamic>.from(l);
      } catch (_) {}

      final list = <Map<String, dynamic>>[];
      try {
        final d = await api.get('/devices', query: {'current': '1', 'size': '50'});
        if (d is Map) {
          final records = d['records'] ?? d['list'];
          if (records is List) {
            for (final r in records) {
              if (r is Map) list.add(Map<String, dynamic>.from(r));
            }
          }
        }
      } catch (_) {}

      var tickets = 0;
      try {
        final s = await api.get('/support');
        if (s is Map) {
          final threads = s['threads'] ?? s['list'] ?? s['records'];
          if (threads is List) {
            for (final th in threads) {
              if (th is Map) {
                final st = (th['status'] ?? '').toString().toLowerCase();
                if (st != 'closed' && st != 'done' && st != 'resolved') {
                  tickets++;
                }
              }
            }
          } else if (s['open_count'] is num) {
            tickets = (s['open_count'] as num).toInt();
          }
        }
      } catch (_) {}

      final localId = _readLocalId();
      final normalized = _normalizeDevices(list, localId);
      final linked = localId.isNotEmpty &&
          normalized.any((d) => (d['device_id'] ?? '').toString() == localId);

      loggedIn.value = true;
      username.value = (me['username'] ?? '').toString();
      displayName.value = (me['name'] ?? '').toString();
      email.value = (me['email'] ?? '').toString();
      licensedDevices.value = (me['licensed_devices'] is num)
          ? (me['licensed_devices'] as num).toInt()
          : 0;
      chatCallsEnabled.value = me['chat_calls_enabled'] == true;
      if (lic != null) {
        licenseActive.value = lic['active'] == true;
        plan.value = (lic['plan'] ?? '').toString();
        concurrentLimit.value = (lic['concurrent_limit'] is num)
            ? (lic['concurrent_limit'] as num).toInt()
            : 0;
        concurrentUsed.value = (lic['concurrent_used'] is num)
            ? (lic['concurrent_used'] as num).toInt()
            : 0;
        overLimit.value = lic['over_limit'] == true;
      } else {
        licenseActive.value = false;
        plan.value = '';
        concurrentLimit.value = 0;
        concurrentUsed.value = 0;
        overLimit.value = false;
      }
      devices.assignAll(normalized);
      deviceCount.value = normalized.length;
      onlineDevices.value =
          normalized.where((d) => d['is_online'] == true).length;
      openTickets.value = tickets;
      localDeviceId.value = localId;
      localIdLinked.value = linked;
      if (!linked && localId.isNotEmpty) {
        // ignore: unawaited_futures
        claimLocalDevice(quiet: true);
      }
      await _syncRustdeskAbAuth(active: true);
    } catch (e) {
      debugPrint('DfCabinetSession.refresh: $e');
      lastError.value = e.toString();
      if (e is CabinetApiException &&
          (e.httpStatus == 401 || e.httpStatus == 406)) {
        _clear();
      }
    } finally {
      loading.value = false;
    }
  }

  Future<void> onLoggedIn() async {
    await claimLocalDevice();
    await refresh();
  }

  Future<void> logout() async {
    await CabinetApi.instance.logout();
    _clear();
  }

  /// Bind this PC's RustDesk ID to the cabinet account.
  Future<bool> claimLocalDevice({bool quiet = false}) async {
    if (!CabinetApi.instance.isLoggedIn) return false;
    final id = _readLocalId();
    if (id.isEmpty) return false;
    var version = '';
    try {
      version = (await bind.mainGetVersion()).trim();
    } catch (_) {}
    try {
      await CabinetApi.instance.post('/devices/claim', body: {
        'device_id': id,
        'hostname': Platform.localHostname,
        'os': Platform.operatingSystem,
        'version': version,
        'note': 'DeskForce клиент',
      });
      localIdLinked.value = true;
      localDeviceId.value = id;
      return true;
    } catch (e) {
      if (!quiet) debugPrint('claimLocalDevice: $e');
      return false;
    }
  }

  String _readLocalId() {
    try {
      final id = gFFI.serverModel.serverId.text.trim();
      if (id.isNotEmpty && id != '-' && id.toLowerCase() != 'null') {
        return id;
      }
    } catch (_) {}
    return '';
  }


  /// Sync cabinet JWT into RustDesk `access_token` / `user_info` so /api/ab works
  /// while stock Account UI stays disabled (disable-account).
  Future<void> _syncRustdeskAbAuth({required bool active}) async {
    try {
      if (!active) {
        await bind.mainSetLocalOption(key: 'access_token', value: '');
        await bind.mainSetLocalOption(key: 'user_info', value: '');
        try {
          gFFI.userModel.userName.value = '';
          gFFI.userModel.displayName.value = '';
        } catch (_) {}
        try {
          await gFFI.abModel.reset();
        } catch (_) {}
        return;
      }
      final token = CabinetApi.instance.token;
      if (token.isEmpty) return;
      final name = username.value.isNotEmpty
          ? username.value
          : (displayName.value.isNotEmpty ? displayName.value : 'user');
      final info = {
        'name': name,
        'display_name':
            displayName.value.isNotEmpty ? displayName.value : name,
        'email': email.value,
        'status': 1,
        'is_admin': false,
      };
      await bind.mainSetLocalOption(key: 'access_token', value: token);
      await bind.mainSetLocalOption(key: 'user_info', value: jsonEncode(info));
      try {
        gFFI.userModel.userName.value = name;
        gFFI.userModel.displayName.value =
            displayName.value.isNotEmpty ? displayName.value : name;
      } catch (_) {}
      try {
        await gFFI.abModel
            .pullAb(force: ForcePullAb.listAndCurrent, quiet: true);
      } catch (e) {
        debugPrint('ab pull after cabinet login: $e');
      }
    } catch (e) {
      debugPrint('_syncRustdeskAbAuth: $e');
    }
  }

  void _clearUiState() {
    loggedIn.value = false;
    username.value = '';
    displayName.value = '';
    email.value = '';
    plan.value = '';
    licenseActive.value = false;
    concurrentLimit.value = 0;
    concurrentUsed.value = 0;
    overLimit.value = false;
    deviceCount.value = 0;
    onlineDevices.value = 0;
    openTickets.value = 0;
    licensedDevices.value = 0;
    chatCallsEnabled.value = false;
    localIdLinked.value = false;
    localDeviceId.value = '';
    devices.clear();
    lastError.value = '';
    loading.value = false;
  }

  void _clear() {
    // Full logout: drop AB bridge + UI. Used by logout / 401 only.
    // ignore: unawaited_futures
    _syncRustdeskAbAuth(active: false);
    _clearUiState();
  }
}
