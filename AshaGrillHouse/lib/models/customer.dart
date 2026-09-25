class Customer {
  int? id;
  String name, phone, address, due;
  String images; // comma separated paths
  String createdAt;

  Customer({
    this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.due,
    required this.images,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'due': due,
      'images': images,
      'createdAt': createdAt,
    };
  }
}
