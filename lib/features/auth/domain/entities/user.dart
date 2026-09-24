class User {
  final int id;
  final String uuid;
  final String username;
  final String name;
  final String role;
  final String? foto;
  final String? lang;

  const User({
    required this.id,
    required this.uuid,
    required this.username,
    required this.name,
    required this.role,
    this.foto,
    this.lang,
  });
}
