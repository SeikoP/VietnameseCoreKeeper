# AGENTS.md

## Phạm vi

Đây là repo Việt hóa phía client cho Core Keeper. File runtime được đóng gói
là `ModManifest.json`, `Localization/Localization.csv` và
`Scripts/VietnameseFontFix.cs`.

## Nguồn cần rà và so sánh

Luôn đọc theo thứ tự này trước khi sửa localization:

1. File localization game sau khi reload Core Keeper:
   `E:\SteamLibrary\steamapps\common\Core Keeper\localization\Localization.csv`
   Đây là nguồn chuẩn để phát hiện key của game và các mod đã load. Chỉ đọc,
   không sửa file này.
2. File đích trong repo: `Localization/Localization.csv`.
3. File localization của bản mod đã cài từ mod.io:
   `C:\Users\Public\mod.io\5289\mods\<mod_id>_<file_id>\Localization\Localization.csv`.
   `<file_id>` phải lấy từ bản mod.io hiện tại, không đoán theo thư mục cũ.
4. Log runtime:
   `C:\Users\bungm\AppData\LocalLow\Pugstorm\Core Keeper\Player.log`.
   Dùng log để xác nhận mod nào đã load, file localization nào được nạp và
   font fix có chạy hay không.
5. `git` và `Backups/` để so sánh với bản trước và bảo toàn thay đổi cũ.

Khi cần hiểu nghĩa một key mới, đọc source/script hoặc asset của mod tương
ứng trong thư mục mod.io. Không dịch chỉ dựa vào tên key nếu ngữ cảnh sử dụng
không rõ.

## Luồng xử lý key mới

1. Kiểm tra `git status` và giữ nguyên thay đổi không thuộc task.
2. Reload game để mod mới được nạp. Xác nhận `Player.log` có các dòng
   `loaded mod`, `Loading localization` và `Loading extra localization`.
3. Đọc hai file game và repo bằng TSV, dùng cột `Key` làm khóa so sánh.
4. Liệt kê các key có trong file game nhưng chưa có trong repo.
5. Với mỗi key mới, dịch cột `Tiếng Việt [c0]`; giữ nguyên `Key`, `Type`,
   `Desc`, tab, thứ tự và placeholder như `{0}`, `{1}`.
6. Kiểm tra không còn ô tiếng Việt trống, key trùng hoặc placeholder bị mất.
7. Chỉ sửa `Localization/Localization.csv`; không ghi ngược vào file game.

Key mới cần được xác định bằng dữ liệu sau reload, không chỉ bằng danh sách
mod trong README. Các key `[new]` cũng phải được kiểm tra ô tiếng Việt.

## Validate trước khi phát hành

Chạy từ PowerShell tại thư mục repo:

```powershell
& powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProjectSources.ps1
& powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProjectConfig.ps1
& powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-NativeGlyphMarks.ps1
git diff --check
```

Ngoài test có sẵn, phải kiểm tra bằng `Import-Csv -Delimiter ([char]9)`:

- số dòng repo khớp số dòng nguồn game sau reload;
- không có key chỉ xuất hiện ở nguồn game;
- `blank_vn = 0`;
- `duplicate_keys = 0`.

## Đóng gói và publish mod.io

1. Lấy version mới nhất của mod `6372484` qua API mod.io. Tăng version, không
   upload lại version đã tồn tại.
2. Đóng gói:

   ```powershell
   .\tools\Package.ps1 -Version <version>
   ```

3. Kiểm tra ZIP chỉ có ba file runtime và localization trong ZIP có cùng số
   dòng, key và số ô trống với repo.
4. Publish bằng script có sẵn:

   ```powershell
   .\tools\Publish-ModIo.ps1 `
     -Version <version> `
     -ZipPath .\releases\vietnamese-core-keeper-<version>.zip `
     -Changelog '<mô tả thay đổi>'
   ```

5. Sau upload, xác nhận file mod.io có version đúng, `virus_status=1` và
   `virus_positive=0`.
6. Description là metadata riêng, không nằm trong ZIP. Nếu cần sửa nội dung
   trang mod.io, cập nhật metadata qua endpoint edit mod hoặc giao diện web;
   upload modfile không tự thay đổi Description, Discussion hay Dependencies.
7. Reload game sau khi mod.io tải bản mới. Xác nhận log có `Loading extra
   localization` và dòng cài glyph, không có `Font8L missing glyph`,
   `CompileFailed` hoặc `load error`.

Không in `.env`, OAuth token, API key hoặc nội dung bí mật ra terminal/chat.
Không gọi publish là hoàn tất nếu chưa kiểm tra file mod.io và log runtime.

## Git và CodeGraph

- Chỉ stage/commit file thuộc task; không xóa backup, log hoặc thay đổi không
  liên quan.
- Repo hiện có thể chưa cấu hình Git remote. Không tự tạo remote khi chưa có
  URL; phân biệt rõ commit local với push thành công.
- Nếu repo có thư mục `.codegraph/`, chạy `codegraph explore` trước `rg` hoặc
  đọc file để tìm hiểu code. Nếu không có `.codegraph/`, bỏ qua CodeGraph.
