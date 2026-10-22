/// Danh sách ứng dụng ngân hàng / ví điện tử được hỗ trợ đọc thông báo.
library;

class BankApp {
  const BankApp(this.key, this.name, this.packages, this.aliases);

  /// Mã nội bộ, vd "mbbank".
  final String key;
  final String name;

  /// Tên gói Android của ứng dụng.
  final List<String> packages;

  /// Từ khoá nhận diện trong nội dung / người gửi SMS (không dấu, chữ thường).
  final List<String> aliases;
}

const List<BankApp> kBankApps = [
  BankApp('mbbank', 'MB Bank', ['com.mbmobile'], ['mbbank', 'mb bank', 'mb ']),
  BankApp('vcb', 'Vietcombank', ['com.VCB'], ['vietcombank', 'vcb']),
  BankApp('tcb', 'Techcombank', [
    'vn.com.techcombank.bb.app',
  ], ['techcombank', 'tcb']),
  BankApp('bidv', 'BIDV', ['com.vnpay.bidv'], ['bidv']),
  BankApp('vietinbank', 'VietinBank', [
    'com.vietinbank.ipay',
  ], ['vietinbank', 'vtb']),
  BankApp('agribank', 'Agribank', ['com.vnpay.Agribank3g'], ['agribank']),
  BankApp('acb', 'ACB', ['mobile.acb.com.vn'], ['acb']),
  BankApp('tpbank', 'TPBank', ['com.tpb.mb.gprsandroid'], ['tpbank']),
  BankApp('vpbank', 'VPBank', ['com.vnpay.vpbankonline'], ['vpbank']),
  BankApp('sacombank', 'Sacombank', [
    'com.sacombank.ewallet',
  ], ['sacombank', 'stb']),
  BankApp('vib', 'VIB', ['com.vib.myvib2'], ['vib']),
  BankApp('hdbank', 'HDBank', ['com.vnpay.hdbank'], ['hdbank']),
  BankApp('msb', 'MSB', ['vn.com.msb.smartBanking'], ['msb']),
  BankApp('shb', 'SHB', ['vn.shb.mbanking'], ['shb']),
  BankApp('seabank', 'SeABank', ['vn.com.seabank.mb1'], ['seabank']),
  BankApp('ocb', 'OCB', ['vn.com.ocb.awe'], ['ocb']),
  BankApp('lpbank', 'LPBank', ['vn.com.lpb.lienviet24h'], ['lpbank', 'lienvietpostbank']),
  BankApp('timo', 'Timo', ['io.lifestyle.plus'], ['timo']),
  BankApp('cake', 'Cake', ['xyz.be.cake'], ['cake']),
  BankApp('momo', 'MoMo', ['com.mservice.momotransfer'], ['momo']),
  BankApp('zalopay', 'ZaloPay', ['vn.com.vng.zalopay'], ['zalopay']),
  BankApp('viettelmoney', 'Viettel Money', ['com.bplus.vtpay'], [
    'viettel money',
    'viettelpay',
  ]),
];

/// Ứng dụng tin nhắn (đọc SMS biến động số dư).
const List<String> kSmsPackages = [
  'com.google.android.apps.messaging',
  'com.samsung.android.messaging',
  'com.android.mms',
  'com.android.messaging',
  'com.oneplus.mms',
  'com.coloros.mms',
  'com.vivo.message',
];

BankApp? bankByKey(String? key) {
  if (key == null) return null;
  for (final b in kBankApps) {
    if (b.key == key) return b;
  }
  return null;
}

BankApp? bankByPackage(String? package) {
  if (package == null) return null;
  for (final b in kBankApps) {
    if (b.packages.contains(package)) return b;
  }
  return null;
}
