import 'models.dart';

/// Hạng mục mặc định (tham khảo bộ hạng mục của các app sổ thu chi phổ biến).
const List<Category> kDefaultExpenseCategories = [
  Category(name: 'Ăn uống', kind: CategoryKind.expense, icon: 'food', color: 0xFFFB8C00),
  Category(name: 'Cà phê, đồ uống', kind: CategoryKind.expense, icon: 'coffee', color: 0xFF6D4C41),
  Category(name: 'Đi chợ, siêu thị', kind: CategoryKind.expense, icon: 'market', color: 0xFF7CB342),
  Category(name: 'Di chuyển', kind: CategoryKind.expense, icon: 'transport', color: 0xFF1E88E5),
  Category(name: 'Xăng xe', kind: CategoryKind.expense, icon: 'fuel', color: 0xFF546E7A),
  Category(name: 'Mua sắm', kind: CategoryKind.expense, icon: 'shopping', color: 0xFFD81B60),
  Category(name: 'Hoá đơn, tiện ích', kind: CategoryKind.expense, icon: 'bill', color: 0xFF00ACC1),
  Category(name: 'Điện thoại, Internet', kind: CategoryKind.expense, icon: 'internet', color: 0xFF039BE5),
  Category(name: 'Nhà cửa', kind: CategoryKind.expense, icon: 'home', color: 0xFF8E24AA),
  Category(name: 'Sức khoẻ', kind: CategoryKind.expense, icon: 'health', color: 0xFFE53935),
  Category(name: 'Học tập', kind: CategoryKind.expense, icon: 'education', color: 0xFF3949AB),
  Category(name: 'Giải trí', kind: CategoryKind.expense, icon: 'entertainment', color: 0xFF5E35B1),
  Category(name: 'Du lịch', kind: CategoryKind.expense, icon: 'travel', color: 0xFF00897B),
  Category(name: 'Hiếu hỉ, quà tặng', kind: CategoryKind.expense, icon: 'gift', color: 0xFFF4511E),
  Category(name: 'Gia đình, con cái', kind: CategoryKind.expense, icon: 'family', color: 0xFFFFB300),
  Category(name: 'Làm đẹp', kind: CategoryKind.expense, icon: 'beauty', color: 0xFFEC407A),
  Category(name: 'Thể thao', kind: CategoryKind.expense, icon: 'sport', color: 0xFF43A047),
  Category(name: 'Bảo hiểm', kind: CategoryKind.expense, icon: 'insurance', color: 0xFF26A69A),
  Category(name: 'Cho vay, trả nợ', kind: CategoryKind.expense, icon: 'loan', color: 0xFF757575),
  Category(name: 'Chuyển tiền', kind: CategoryKind.expense, icon: 'transfer', color: 0xFF0277BD),
  Category(name: 'Chi khác', kind: CategoryKind.expense, icon: 'other', color: 0xFF78909C),
];

const List<Category> kDefaultIncomeCategories = [
  Category(name: 'Lương', kind: CategoryKind.income, icon: 'salary', color: 0xFF43A047),
  Category(name: 'Thưởng', kind: CategoryKind.income, icon: 'bonus', color: 0xFFFFB300),
  Category(name: 'Được tặng, biếu', kind: CategoryKind.income, icon: 'gift', color: 0xFFF4511E),
  Category(name: 'Tiền lãi', kind: CategoryKind.income, icon: 'interest', color: 0xFF00897B),
  Category(name: 'Bán hàng', kind: CategoryKind.income, icon: 'sell', color: 0xFF1E88E5),
  Category(name: 'Thu nợ, đi vay', kind: CategoryKind.income, icon: 'loan', color: 0xFF757575),
  Category(name: 'Nhận chuyển khoản', kind: CategoryKind.income, icon: 'transfer', color: 0xFF0277BD),
  Category(name: 'Hoàn tiền', kind: CategoryKind.income, icon: 'refund', color: 0xFF8E24AA),
  Category(name: 'Thu khác', kind: CategoryKind.income, icon: 'other', color: 0xFF78909C),
];

const List<Account> kDefaultAccounts = [
  Account(name: 'Ví tiền mặt', type: AccountType.cash, color: 0xFF43A047),
  Account(
    name: 'MB Bank',
    type: AccountType.bank,
    bankKey: 'mbbank',
    color: 0xFF1E3A8A,
  ),
];
