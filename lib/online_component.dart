/// Online account, catalogue and reading are provided by Wenku8Client and
/// LegacyWenkuRepository; this remains only for optional review/illustration
/// boundaries that a host may not install.
class OnlineComponentUnavailable implements Exception {
  const OnlineComponentUnavailable();
  static const message = '该在线功能暂未开放，可继续使用本地导入与阅读';
  @override
  String toString() => message;
}

class OnlineAuthenticationRequired implements Exception {
  const OnlineAuthenticationRequired();
  @override
  String toString() => '请先登录账号';
}

Future<T> unavailableOnline<T>() =>
    Future<T>.error(const OnlineComponentUnavailable());
