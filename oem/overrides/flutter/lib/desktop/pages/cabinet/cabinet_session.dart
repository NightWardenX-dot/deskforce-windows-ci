import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_api.dart';
import 'package:flutter_hbb/models/model.dart';
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
  final localIdLinked = false.obs;
  final localDeviceId = ''.obs;
  final devices = <Map<String, dynamic>>[].obs;
  final lastError = ''.obs;

  @override
  void onInit() {
    super.onInit();
    refresh();
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
    return '$p · ${concurrentUsed.value}/${concurrentLimit.value} сессий';
  }

  Future<void> refresh() async {
    if (!CabinetApi.instance.isLoggedIn) {
      _clear();
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
      final linked = localId.isNotEmpty &&
          list.any((d) => (d['device_id'] ?? '').toString() == localId);

      loggedIn.value = true;
      username.value = (me['username'] ?? '').toString();
      displayName.value = (me['name'] ?? '').toString();
      email.value = (me['email'] ?? '').toString();
      licensedDevices.value = (me['licensed_devices'] is num)
          ? (me['licensed_devices'] as num).toInt()
          : 0;
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
      devices.assignAll(list);
      deviceCount.value = list.length;
      onlineDevices.value =
          list.where((d) => d['is_online'] == true).length;
      openTickets.value = tickets;
      localDeviceId.value = localId;
      localIdLinked.value = linked;
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
  Future<bool> claimLocalDevice() async {
    if (!CabinetApi.instance.isLoggedIn) return false;
    final id = _readLocalId();
    if (id.isEmpty) return false;
    try {
      await CabinetApi.instance.post('/devices/claim', body: {
        'device_id': id,
        'hostname': Platform.localHostname,
        'os': Platform.operatingSystem,
        'version': '',
        'note': 'DeskForce клиент',
      });
      localIdLinked.value = true;
      localDeviceId.value = id;
      return true;
    } catch (e) {
      debugPrint('claimLocalDevice: $e');
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

  void _clear() {
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
    localIdLinked.value = false;
    localDeviceId.value = '';
    devices.clear();
    lastError.value = '';
    loading.value = false;
  }
}
