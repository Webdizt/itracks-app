import 'package:equatable/equatable.dart';

class Inventory extends Equatable {
  final String id;
  final String assetCode;
  final String? brand;
  final String? model;
  final String? sn;
  final String? group;
  final String? department;
  final String? condition;
  final String? location;
  final int statusCode;
  final String? photo;
  final String? createdDate;

  const Inventory({
    required this.id,
    required this.assetCode,
    this.brand,
    this.model,
    this.sn,
    this.group,
    this.department,
    this.condition,
    this.location,
    required this.statusCode,
    this.photo,
    this.createdDate,
  });

  @override
  List<Object?> get props => [
        id,
        assetCode,
        brand,
        model,
        sn,
        group,
        department,
        condition,
        location,
        statusCode,
        photo,
        createdDate
      ];
}
