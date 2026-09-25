import 'dart:convert';

class ReceiptItem {
  int id;
  String name;
  String originalUnit;
  String currentUnit;
  double qty;
  double prePriceQty;
  double rate;
  double totalPrice;
  String history;
  String status; // "rough" or "billed"

  ReceiptItem({
    required this.id,
    required this.name,
    required this.originalUnit,
    required this.currentUnit,
    required this.qty,
    required this.prePriceQty,
    required this.rate,
    required this.totalPrice,
    required this.history,
    required this.status,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'originalUnit': originalUnit,
      'currentUnit': currentUnit,
      'qty': qty,
      'prePriceQty': prePriceQty,
      'rate': rate,
      'totalPrice': totalPrice,
      'history': history,
      'status': status,
    };
  }

  factory ReceiptItem.fromMap(Map<String, dynamic> map) {
    return ReceiptItem(
      id: map['id'],
      name: map['name'],
      originalUnit: map['originalUnit'],
      currentUnit: map['currentUnit'],
      qty: (map['qty'] as num).toDouble(),
      prePriceQty: (map['prePriceQty'] as num).toDouble(),
      rate: (map['rate'] as num).toDouble(),
      totalPrice: (map['totalPrice'] as num).toDouble(),
      history: map['history'],
      status: map['status'],
    );
  }
}
