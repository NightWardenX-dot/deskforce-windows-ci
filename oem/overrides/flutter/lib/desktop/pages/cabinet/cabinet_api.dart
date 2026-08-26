import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:flutter_hbb/desktop/pages/cabinet/cabinet_errors.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:http/http.dart' as http;

const kDfCabinetToken = 'deskforce-cabinet-token';
const kDfCabinetApiBase = 'https://deskforce.dr6ter.ru/cabinet-api';

class CabinetApiException implements Exception {
  final String message;
  final dynamic data;
  final int? httpStatus;
  CabinetApiException(this.message, {this.data, this.httpStatus});
  @override
  String toString() => message;
  String get ru => dfCabinetError(message);
}

class CabinetApi {
  CabinetApi({this.baseUrl = kDfCabinetApiBase});

  final String baseUrl;
  static final CabinetApi instance = CabinetApi();

  String get token => bind.mainGetLocalOption(key: kDfCabinetToken);

  Future<void> setToken(String value) async {
    await bind.mainSetLocalOption(key: kDfCabinetToken, value: value);
  }

  Future<void> clearToken() => setToken('');

  bool get isLoggedIn => token.isNotEmpty;

  Map<String, String> _headers({bool auth = true}) {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (auth) {
      final t = token;
      if (t.isNotEmpty) h['Authorization'] = t;
    }
    return h;
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool auth = true,
    Map<String, String>? query,
  }) async {
    var uri = Uri.parse('$baseUrl$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }
    final client = http.Client();
    try {
      late http.Response res;
      final headers = _headers(auth: auth);
      final encoded = body == null ? null : jsonEncode(body);
      switch (method.toUpperCase()) {
        case 'POST':
          res = await client
              .post(uri, headers: headers, body: encoded)
              .timeout(const Duration(seconds: 30));
          break;
        case 'PUT':
          res = await client
              .put(uri, headers: headers, body: encoded)
              .timeout(const Duration(seconds: 30));
          break;
        case 'DELETE':
          res = await client
              .delete(uri, headers: headers, body: encoded)
              .timeout(const Duration(seconds: 30));
          break;
        default:
          res = await client
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 30));
      }
      if (res.statusCode == 401 || res.statusCode == 406) {
        await clearToken();
        throw CabinetApiException('Unauthorized', httpStatus: res.statusCode);
      }
      dynamic json;
      try {
        json = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        throw CabinetApiException('NetworkError', httpStatus: res.statusCode);
      }
      if (json is! Map) {
        throw CabinetApiException('Error', httpStatus: res.statusCode);
      }
      final code = json['code'];
      final message = (json['message'] ?? 'Error').toString();
      if (code != 200) {
        throw CabinetApiException(message, data: json['data'], httpStatus: res.statusCode);
      }
      return json['data'];
    } on CabinetApiException {
      rethrow;
    } on TimeoutException {
      throw CabinetApiException('Timeout');
    } catch (e) {
      if (e is CabinetApiException) rethrow;
      throw CabinetApiException('NetworkError');
    } finally {
      client.close();
    }
  }

  Future<dynamic> get(String path, {Map<String, String>? query, bool auth = true}) =>
      request(path, query: query, auth: auth);

  Future<dynamic> post(String path, {Map<String, dynamic>? body, bool auth = true}) =>
      request(path, method: 'POST', body: body, auth: auth);

  /// Bot-protection payload for login/register/forgot/resend.
  static Map<String, dynamic> botFields({
    required int formOpenedAt,
    String captchaId = '',
    String code = '',
    String powNonce = '',
    int pointerEvents = 1,
  }) =>
      {
        'notRobot': true,
        'honeypot': '',
        'honeypot2': '',
        'formOpenedAt': formOpenedAt,
        'captchaId': captchaId,
        'code': code,
        'powNonce': powNonce,
        'pointerEvents': pointerEvents,
      };

  /// Solve SHA-256 PoW issued by /auth/challenge (native clients have no slider).
  static String solvePow(String prefix, int bits) {
    if (prefix.isEmpty || bits < 1) return '0';
    for (var i = 0; i < 5000000; i++) {
      final nonce = '$i';
      final digest = sha256.convert(utf8.encode('$prefix:$nonce'));
      if (_leadingZeroBits(digest.bytes) >= bits) return nonce;
    }
    return '0';
  }

  static int _leadingZeroBits(List<int> bytes) {
    var n = 0;
    for (final b in bytes) {
      for (var i = 7; i >= 0; i--) {
        if ((b & (1 << i)) == 0) {
          n++;
        } else {
          return n;
        }
      }
    }
    return n;
  }

  /// Fetch challenge and return bot fields ready for auth POST.
  Future<Map<String, dynamic>> prepareBotFields(int formOpenedAt) async {
    final ch = await fetchChallenge();
    final captchaId = (ch?['id'] ?? '').toString();
    final bits = (ch?['powBits'] is num) ? (ch!['powBits'] as num).toInt() : 16;
    final prefix = (ch?['powPrefix'] ?? '').toString();
    final nonce = solvePow(prefix, bits);
    return botFields(
      formOpenedAt: formOpenedAt,
      captchaId: captchaId,
      powNonce: nonce,
      pointerEvents: 3,
    );
  }

  Future<Map<String, dynamic>?> fetchChallenge() async {
    try {
      final data = await get('/auth/challenge', auth: false);
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (_) {
      try {
        final data = await get('/auth/captcha', auth: false);
        if (data is Map) return Map<String, dynamic>.from(data);
      } catch (_) {}
    }
    return null;
  }

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    required int formOpenedAt,
    String tfaCode = '',
    bool rememberMe = true,
    String captchaId = '',
    String powNonce = '',
  }) async {
    Map<String, dynamic> bot;
    if (powNonce.isNotEmpty && captchaId.isNotEmpty) {
      bot = botFields(
        formOpenedAt: formOpenedAt,
        captchaId: captchaId,
        powNonce: powNonce,
        pointerEvents: 3,
      );
    } else {
      bot = await prepareBotFields(formOpenedAt);
    }
    final data = await post('/auth/login', auth: false, body: {
      'username': username,
      'password': password,
      'tfaCode': tfaCode,
      'rememberMe': rememberMe,
      ...bot,
    });
    final map = Map<String, dynamic>.from(data as Map);
    final token = (map['token'] ?? '').toString();
    if (token.isNotEmpty) await setToken(token);
    return map;
  }

  Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String email,
    required int formOpenedAt,
    String name = '',
    String captchaId = '',
  }) async {
    final bot = await prepareBotFields(formOpenedAt);
    final data = await post('/auth/register', auth: false, body: {
      'username': username,
      'password': password,
      'email': email,
      'name': name,
      ...bot,
    });
    return Map<String, dynamic>.from(data as Map? ?? {});
  }

  Future<void> logout() async {
    try {
      await post('/auth/logout', body: {});
    } catch (_) {}
    await clearToken();
  }
}
