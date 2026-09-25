class Measurement {
  int? id;
  String name, phone, address;
  String createdAt;

  Measurement({
    this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'createdAt': createdAt,
    };
  }
}
