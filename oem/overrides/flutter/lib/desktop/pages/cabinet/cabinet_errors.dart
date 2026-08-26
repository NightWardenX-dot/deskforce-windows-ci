/// Centralized Russian messages for cabinet API / network / auth failures.
String dfCabinetError(Object? err, {String fallback = 'Ошибка запроса'}) {
  final raw = err?.toString() ?? '';
  final key = raw.trim();
  if (key.isEmpty) return fallback;
  return kDfCabinetErrors[key] ??
      kDfCabinetErrors[_normalize(key)] ??
      (key.startsWith('SocketException') ||
              key.contains('Failed host lookup') ||
              key.contains('Network is unreachable') ||
              key.contains('Connection refused') ||
              key.contains('ClientException')
          ? kDfCabinetErrors['NetworkError']!
          : (key.startsWith('Timeout') || key.contains('TimeoutException')
              ? kDfCabinetErrors['Timeout']!
              : (key.length < 120 ? key : fallback)));
}

String _normalize(String s) {
  // Strip Exception prefixes like "CabinetApiException: CaptchaError"
  final i = s.lastIndexOf(':');
  if (i >= 0 && i < s.length - 1) {
    return s.substring(i + 1).trim();
  }
  return s;
}

const Map<String, String> kDfCabinetErrors = {
  'NetworkError': 'Нет связи с сервером. Проверьте интернет и повторите.',
  'Timeout': 'Сервер не ответил вовремя. Попробуйте ещё раз.',
  'Unauthorized': 'Сессия истекла. Войдите снова.',
  'CaptchaError': 'Проверка безопасности не пройдена. Обновите форму.',
  'BotGuardError': 'Проверка «я не робот» не пройдена. Подождите пару секунд и повторите.',
  'UsernameOrPasswordError': 'Неверный логин или пароль',
  'TfaCodeError': 'Неверный код 2FA',
  'Force2FAEnabled': 'Администратор запретил отключение 2FA',
  'TfaRequired': 'Введите код двухфакторной аутентификации',
  'EmailNotVerified': 'Подтвердите email — введите код из письма',
  'UserExists': 'Пользователь уже существует',
  'EmailExists': 'Email уже используется',
  'PasswordTooShort': 'Пароль не короче 8 символов',
  'InvalidEmail': 'Некорректный email',
  'DataError': 'Заполните обязательные поля',
  'RegisteredMailPending':
      'Аккаунт создан, но письмо не отправилось. Запросите код ещё раз.',
  'PasswordError': 'Неверный текущий пароль',
  'OldPasswordError': 'Неверный текущий пароль',
  'SamePassword': 'Новый пароль совпадает со старым',
  'CodeError': 'Неверный или просроченный код',
  'TokenError': 'Неверный или просроченный код',
  'ThreadClosed': 'Обращение закрыто',
  'NotFound': 'Не найдено',
  'LicenseError': 'Ошибка лицензии',
  'PaymentError': 'Ошибка оплаты',
  'OrderError': 'Не удалось создать заказ',
  'Error': 'Ошибка запроса',
};
