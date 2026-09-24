import 'package:dartz/dartz.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/network_info.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_local_datasource.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/user_model.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;
  final AuthLocalDataSource localDataSource;
  final NetworkInfo networkInfo;

  AuthRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.networkInfo,
  });

  @override
  Future<Either<Failure, User>> login(String username, String password) async {
    if (await networkInfo.isConnected) {
      try {
        final user = await remoteDataSource.login(username, password);
        await localDataSource.cacheUser(user);
        // Assuming token is returned in response, cache it
        // await localDataSource.cacheToken(user.token);
        return Right(user);
      } on ServerException catch (e) {
        return Left(ServerFailure(message: e.message)); 
      }
    } else {
      return const Left(NetworkFailure(message: 'No internet connection'));
    }
  }

  @override
  Future<Either<Failure, void>> logout() async {
    try {
      await remoteDataSource.logout();
      await localDataSource.clearCache();
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(message: 'Unable to log out from the application session'));
    }
  }

  @override
  Future<Either<Failure, User?>> checkAuthStatus() async {
    try {
      final user = await localDataSource.getLastUser();
      return Right(user);
    } on CacheException catch (e) {
      return Left(CacheFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, void>> forgotPassword(String email) async {
    if (await networkInfo.isConnected) {
      try {
        await remoteDataSource.forgotPassword(email);
        return const Right(null);
      } on ServerException catch (e) {
        return Left(ServerFailure(message: e.message)); 
      }
    } else {
      return const Left(NetworkFailure(message: 'No internet connection'));
    }
  }

  @override
  Future<Either<Failure, void>> changePassword(
    String token,
    String oldPassword,
    String newPassword,
  ) async {
    if (await networkInfo.isConnected) {
      try {
        await remoteDataSource.changePassword(token, oldPassword, newPassword);
        return const Right(null);
      } on ServerException catch (e) {
        return Left(ServerFailure(message: e.message)); 
      }
    } else {
      return const Left(NetworkFailure(message: 'No internet connection'));
    }
  }

  @override
  Future<Either<Failure, bool>> validateToken(String token) async {
    if (await networkInfo.isConnected) {
      try {
        final isValid = await remoteDataSource.validateToken(token);
        return Right(isValid);
      } on ServerException catch (e) {
        return Left(ServerFailure(message: e.message)); 
      }
    } else {
      return const Left(NetworkFailure(message: 'No internet connection'));
    }
  }
}
