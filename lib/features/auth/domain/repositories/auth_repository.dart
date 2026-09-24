import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/user.dart';

abstract class AuthRepository {
  Future<Either<Failure, User>> login(String username, String password);
  Future<Either<Failure, void>> logout();
  Future<Either<Failure, User?>> checkAuthStatus();
  Future<Either<Failure, void>> forgotPassword(String email);
  Future<Either<Failure, void>> changePassword(
      String token, String oldPassword, String newPassword);
  Future<Either<Failure, bool>> validateToken(String token);
}
