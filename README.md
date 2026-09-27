# Vietnamese Core Keeper

Việt hóa phía client cho Core Keeper 1.3.x, kèm font pixel khớp PugFonts gốc.

Gói gồm `Localization/Localization.csv` và script font. Cài đặt qua mod.io; nên hủy đăng ký các gói Việt hóa/font cũ trước khi dùng.

Các mod có key Việt hóa trong gói hiện tại:

- Item Browser
- CoreEnhance
- Placement Plus
- GeneralConfigMenu
- Health Bars
- Stream Integration
- StoragePlus

Placement Plus bao gồm cả trang `Mod Config Settings`: tiêu đề, mục General, Max Brush Size, Exclude Items, Min Hold Time và mô tả tương ứng.

## Tương thích phiên bản game

Mod bị game từ chối **trước khi đọc bất kỳ file nào** nếu tag `Game Version` trên
mod.io không khớp phiên bản game đang chạy. Khi đó `Player.log` sẽ có:

```
mod Vietnamese Core Keeper is not compatible with current version
not loading incompatible mod VietnameseCoreKeeper
```

Dấu hiệu là toàn bộ chữ tiếng Việt hiện ô vuông và **không có** dòng
`[VietnameseFontFix]` nào, vì script chưa từng được biên dịch.

Mỗi lần game cập nhật, cần đổi tag `Game Version` của mod trên mod.io sang
phiên bản mới (hiện là `1.3.0`). Ngoài ra xoá cache cũ tại
`C:\Users\Public\mod.io\5289\state.json` nếu tag trong game vẫn là bản cũ.

Kiểm tra bằng `tests/Test-VietnameseFontRuntime.ps1`, test này bắt được cả
lỗi load mod, lỗi compile script, lỗi Harmony, và glyph tiếng Việt bị thiếu.
