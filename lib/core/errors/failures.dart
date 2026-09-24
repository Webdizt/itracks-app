import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  final String message;
  
  const Failure({required this.message});
  
  @override
  List<Object?> get props => [message];
}


class ServerFailure extends Failure {
  const ServerFailure({required super.message}); // Named parameter
}

class NetworkFailure extends Failure {
  const NetworkFailure({required super.message}); // Named parameter
}

class CacheFailure extends Failure {
  const CacheFailure({required super.message});
}

class NotFoundFailure extends Failure {
  const NotFoundFailure({required String message}) : super(message: message);
}

class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure({required String message}) : super(message: message);
}