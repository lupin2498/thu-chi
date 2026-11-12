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

## Android – hai bản cài

| Bản | Tệp | Ghi giao dịch sau chuyển khoản | Cài đặt |
|---|---|---|---|
| **Tiêu chuẩn** (khuyên dùng) | `SoThuChi-x.y.z.apk` | Ở màn "Chuyển khoản thành công" bấm **Chia sẻ** biên lai → **Ghi vào Sổ Thu Chi**: app đọc số tiền trên biên lai (OCR trên máy), cửa sổ ghi nhanh hiện ngay với micro chờ sẵn | Cài bình thường |
| **Đầy đủ** | `SoThuChi-x.y.z-full.apk` | Tự đọc thông báo biến động số dư, cửa sổ tự bật không cần bấm gì | Play Protect chặn khi mở tệp từ trình duyệt/Zalo/trình quản lý tệp (quyền đọc thông báo) → cài bằng `adb install` hoặc tạm tắt "Quét ứng dụng bằng Play Protect" |

Hai bản cùng mã ứng dụng và khoá ký nên cài đè qua lại vẫn giữ dữ liệu.

Bản đầy đủ – trong app: **Khác → Tự động ghi chép**, bật:
- *Đọc thông báo* (Notification access),
- *Hiển thị trên ứng dụng khác* (để cửa sổ hiện trên app ngân hàng),
- *Micro*, *Gửi thông báo*.
- Máy Xiaomi/Oppo/Vivo: bật thêm "Hiển thị cửa sổ bật lên khi chạy nền".
- Android 13+ cài từ file APK: nếu nút "Đọc thông báo" bị mờ, vào *Thông tin ứng dụng → ⋮ →
  Cho phép cài đặt bị hạn chế* rồi bật lại.

Có nút **Giả lập thông báo** để thử toàn bộ luồng mà không cần chuyển khoản thật.
Mọi xử lý diễn ra trên máy, không gửi dữ liệu ra ngoài.

### Lọc thông báo trùng

Một giao dịch thường được báo nhiều lần: app ngân hàng báo xong, Gmail / SMS báo lại. Bản đầy đủ chỉ ghi nhận
lần đầu, các lần báo lại bị lọc bỏ (bật/tắt ở **Tự động ghi chép → Tuỳ chọn → Lọc thông báo trùng**):

- So theo **số tiền + nội dung chuyển khoản**; khi thông báo có thì dùng thêm **số dư sau giao dịch** và **giờ giao dịch**
  (trong 12 giờ). Nội dung không cần giống hệt: bỏ dấu, bỏ mã tham chiếu, chấp nhận trích đoạn email bị cắt.
- Thiếu cả nội dung, số dư, giờ: chỉ coi là trùng khi kênh khác báo cùng số tiền sát nhau (10 phút nếu cùng ngân hàng, 2 phút nếu không rõ).
- Mỗi kênh chỉ báo một giao dịch một lần, nên **hai lần chuyển cùng số tiền, cùng nội dung trên cùng một app vẫn được ghi đủ**;
  hai chân của một lần chuyển giữa hai tài khoản của mình (một trừ, một cộng) cũng không bị gộp.
- Thông báo đã lọc nằm ở mục **Thông báo trùng đã lọc** kèm lý do; bấm **Vẫn ghi** nếu lọc nhầm.

## iPhone

iOS không cho đọc thông báo của app khác. Dùng **Phím tắt → Tự động hoá → Tin nhắn** (SMS từ ngân hàng)
→ *Mã hoá URL* nội dung → *Mở URL* `sothuchi://app/add?text=<nội dung>`: app mở cửa sổ ghi nhanh với số tiền sẵn
và micro chờ. Ngoài ra có thể dán nội dung thông báo hoặc nói để ghi.

## Build

```bash
flutter pub get
flutter test
flutter build apk --release --flavor standard   # hoặc --flavor full
flutter build ios --release --no-codesign   # trên macOS
```

GitHub Actions (`.github/workflows/build.yml`) tự build APK + IPA chưa ký và đăng lên mục **Releases** mỗi lần push.
Để APK luôn cùng chữ ký giữa các bản, có thể đặt secret `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`; nếu không đặt, workflow tự tạo khoá và giữ trong bản nháp Release
`signing-key` (chỉ người có quyền ghi repo thấy; đừng xoá). Mỗi bản phát hành ghi chứng chỉ SHA-256 của APK.

IPA chưa ký: cài bằng Sideloadly / AltStore / TrollStore (ký bằng Apple ID).

## Cấu trúc

- `lib/capture/bank_parser.dart` + `android/.../capture/BankParser.kt`: bộ phân tích thông báo (2 bản dùng chung
  mẫu thử `test/fixtures/bank_notifications.json`).
- `android/app/src/full/.../BankNotificationListener.kt` (chỉ bản đầy đủ): đọc thông báo; `CapturePresenter.kt`: thẻ nổi + mở cửa sổ;
- `CaptureDedupe.kt`: lọc thông báo trùng (thuần Kotlin, test trong `CaptureDedupeTest.kt`);
- `ReceiptParser.kt` / `ReceiptOcr.kt`: đọc số tiền trên ảnh biên lai được chia sẻ;
  `QuickAddActivity.kt`: cửa sổ Flutter trong suốt (điểm vào `quickAddMain`).
- `lib/ui/quick_add/`: giao diện ghi nhanh + giọng nói.
