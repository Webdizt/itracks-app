import '../../domain/entities/user.dart';

class UserModel extends User {
  const UserModel({
    required super.id,
    required super.uuid,
    required super.username,
    required super.name,
    required super.role,
    super.foto,
    super.lang,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      uuid: json['uuid'],
      username: json['username'],
      name: json['name'],
      role: json['role'],
      foto: json['foto'],
      lang: json['lang'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'username': username,
      'name': name,
      'role': role,
      'foto': foto,
      'lang': lang,
    };
  }
}
