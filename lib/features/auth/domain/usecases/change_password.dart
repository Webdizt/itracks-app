import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/auth_repository.dart';

class ChangePassword implements UseCase<void, ChangePasswordParams> {
  final AuthRepository repository;

  ChangePassword(this.repository);

  @override
  Future<Either<Failure, void>> call(ChangePasswordParams params) async {
    return await repository.changePassword(
      params.token,
      params.oldPassword,
      params.newPassword,
    );
  }
}

class ChangePasswordParams {
  final String token;
  final String oldPassword;
  final String newPassword;

  ChangePasswordParams({
    required this.token,
    required this.oldPassword,
    required this.newPassword,
  });
}
