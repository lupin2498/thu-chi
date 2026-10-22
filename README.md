# Sổ Thu Chi

Ứng dụng ghi chép thu chi cá nhân (Flutter, Android + iOS), bố cục tham khảo các app sổ thu chi phổ biến
(Tổng quan · Sổ giao dịch · Ghi chép · Báo cáo · Khác), bổ sung **tự động ghi chép sau khi chuyển khoản**:

1. Chuyển khoản xong trên MB Bank (hoặc VCB, Techcombank, BIDV, VietinBank, ACB, TPBank, MoMo, ZaloPay…).
2. Ngân hàng gửi thông báo biến động số dư → app đọc thông báo, **trích xuất số tiền, chiều thu/chi, nội dung CK**.
3. Cửa sổ ghi nhanh hiện ngay trên màn hình ngân hàng, **micro bật sẵn** để nói tên khoản (vd "ăn trưa").
   Hạng mục được gợi ý theo lời nói, bấm **Lưu** là xong.

## Tính năng

- Tài khoản/ví (tiền mặt, ngân hàng, ví điện tử…), số dư, chuyển khoản nội bộ, điều chỉnh số dư.
- Hạng mục thu/chi tuỳ biến (biểu tượng, màu), gợi ý hạng mục theo nội dung và theo thói quen.
- Sổ giao dịch theo tháng, nhóm theo ngày, tìm kiếm không dấu, lọc theo loại/tài khoản, vuốt để xoá (hoàn tác).
- Báo cáo: biểu đồ tròn chi/thu theo hạng mục (tháng/năm), biểu đồ cột thu chi 12 tháng.
- Hạn mức chi tháng, ẩn số dư, xuất CSV (Excel), sao lưu/khôi phục JSON.
- Ghi nhanh bằng giọng nói kèm số tiền: "ăn trưa 50 nghìn", "đổ xăng 1tr2", "tiền điện 1 triệu 250 nghìn".
- Dán SMS/thông báo ngân hàng để ghi.

## Android – tự động ghi chép

Trong app: **Khác → Tự động ghi chép**, bật:
- *Đọc thông báo* (Notification access),
- *Hiển thị trên ứng dụng khác* (để cửa sổ hiện trên app ngân hàng),
- *Micro*, *Gửi thông báo*.
- Máy Xiaomi/Oppo/Vivo: bật thêm "Hiển thị cửa sổ bật lên khi chạy nền".
- Android 13+ cài từ file APK: nếu nút "Đọc thông báo" bị mờ, vào *Thông tin ứng dụng → ⋮ →
  Cho phép cài đặt bị hạn chế* rồi bật lại.

Có nút **Giả lập thông báo** để thử toàn bộ luồng mà không cần chuyển khoản thật.
Mọi xử lý diễn ra trên máy, không gửi dữ liệu ra ngoài.

## iPhone

iOS không cho đọc thông báo của app khác. Dùng **Phím tắt → Tự động hoá → Tin nhắn** (SMS từ ngân hàng)
→ *Mã hoá URL* nội dung → *Mở URL* `sothuchi://app/add?text=<nội dung>`: app mở cửa sổ ghi nhanh với số tiền sẵn
và micro chờ. Ngoài ra có thể dán nội dung thông báo hoặc nói để ghi.

## Build

```bash
flutter pub get
flutter test
flutter build apk --release
flutter build ios --release --no-codesign   # trên macOS
```

GitHub Actions (`.github/workflows/build.yml`) tự build APK + IPA chưa ký và đăng lên mục **Releases** mỗi lần push.
Để APK luôn cùng chữ ký giữa các bản, có thể đặt secret `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`; nếu không đặt, workflow tự tạo khoá và giữ trong cache.

IPA chưa ký: cài bằng Sideloadly / AltStore / TrollStore (ký bằng Apple ID).

## Cấu trúc

- `lib/capture/bank_parser.dart` + `android/.../capture/BankParser.kt`: bộ phân tích thông báo (2 bản dùng chung
  mẫu thử `test/fixtures/bank_notifications.json`).
- `android/.../capture/BankNotificationListener.kt`: đọc thông báo; `CapturePresenter.kt`: thẻ nổi + mở cửa sổ;
  `QuickAddActivity.kt`: cửa sổ Flutter trong suốt (điểm vào `quickAddMain`).
- `lib/ui/quick_add/`: giao diện ghi nhanh + giọng nói.
