class ServerException implements Exception {
  final String message;
  ServerException({this.message = 'Server error'});

  @override
  String toString() => message;
}

class CacheException implements Exception {
  final String message;
  CacheException({this.message = 'Cache error'});

  @override
  String toString() => message;
}

class NetworkException implements Exception {
  final String message;

  NetworkException({this.message = 'Network error'});

  @override
  String toString() => message;
}

class UnauthorizedException implements Exception {
  final String message;

  UnauthorizedException({this.message = 'Unauthorized'});

  @override
  String toString() => message;
}
