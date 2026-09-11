# Phát hành mod

## Cấu hình cục bộ

`.env` chứa API path, API key, user ID, client name, client ID, game ID và mod ID. File này đã được Git ignore; không commit, gửi hoặc dán nội dung `.env` vào issue/chat. `.env.example` chỉ là mẫu không có bí mật.

OAuth token ghi dữ liệu không nằm trong repo. Script lấy token đăng nhập mà Core Keeper đã lưu tại `%LOCALAPPDATA%\mod.io\05289\Steam705408214\user.json`.

## Đóng gói và tải bản cập nhật

Từ PowerShell tại thư mục repo:

```powershell
.\tools\Package.ps1 -Version 1.0.1
.\tools\Publish-ModIo.ps1 -Version 1.0.1 -Changelog 'Sửa lỗi dấu tiếng Việt.'
```

Nếu chưa có script đóng gói, tạo ZIP đúng ba file runtime: `ModManifest.json`, `Localization/Localization.csv` và `Scripts/VietnameseFontFix.cs`, đặt tại `releases\vietnamese-core-keeper-<version>.zip`.

Sau khi tải, kiểm tra mod `6372484` có file mới, đúng version và `virus_status=1`, `virus_positive=0`. Không dùng API key để thay thế OAuth token khi upload.

## Kiểm tra Subscribe

1. Đăng nhập mod.io trong Core Keeper bằng tài khoản `40831167`.
2. Subscribe [Vietnamese Core Keeper](https://mod.io/g/corekeeper/m/vietnamese-core-keeper).
3. Chờ file xuất hiện trong `%PUBLIC%\mod.io\5289\mods` rồi khởi động lại game.
4. Xác nhận log có `Loading extra localization` và `Installed ... Vietnamese glyphs`, không có `Font8L missing glyph`, `CompileFailed` hoặc `load error`.

## GitHub

```powershell
git add .
git commit -m 'chore: prepare mod.io publishing config'
git remote add origin <github-repository-url>
git push -u origin main
```

Không đưa `.env`, backup, log, ZIP phát hành hoặc thư mục game vào GitHub.
