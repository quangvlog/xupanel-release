# xupanel

Panel quản lý server cho Ubuntu 20.04 trở lên (amd64, arm64).

## Cài đặt

Chạy trên VPS bằng quyền root:

```bash
curl -fsSL https://raw.githubusercontent.com/quangvlog/xupanel-release/main/install.sh | sudo bash
```

Cài xong, màn hình hiện địa chỉ đăng nhập, tên đăng nhập và mật khẩu. Mở port panel trên tường lửa của nhà cung cấp VPS.

- Xem lại địa chỉ: `sudo xupanel info`
- Quên mật khẩu: `sudo xupanel reset-password`
