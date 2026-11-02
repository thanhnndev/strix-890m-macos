# strix-890m-macos

Radeon 890M (iGPU AMD Strix Point, `1002:150e`) trên macOS, cho **ASUS ROG Zephyrus G14 (GA403WM)**: ghi chép nghiên cứu, các
kext màn hình khởi động, công cụ và log trace của nỗ lực đưa WindowServer lên iGPU.

> **Nghiên cứu, chưa phải driver hoàn chỉnh.** Repo này không cho bạn một 890M có tăng tốc. Màn hình OLED của laptop nối vào
> 890M, RTX 5060 chạy bằng driver NVIDIA của bên thứ ba, và macOS không có thiết bị Metal cho phía AMD. Công việc là một chuỗi
> dài các bước đánh số (`Step01` ... `Step72`) trong [docs/890M-TRACE.md](docs/890M-TRACE.md) và
> [docs/890M-SESSION-HANDOFF.md](docs/890M-SESSION-HANDOFF.md). Kext chạy trong kernel: đọc mã trước khi cài và luôn giữ cách
> khởi động không có chúng.

Là một phần của dự án [GA403WM Hackintosh](https://github.com/thanhnndev/ga403wm-hackintosh) (EFI OpenCore và mục lục các phần).
Repo anh em: [mt7925-macos](https://github.com/thanhnndev/mt7925-macos) (Wi-Fi, Bluetooth),
[rog-control-macos](https://github.com/thanhnndev/rog-control-macos) (profile, quạt, đèn).

## Mục tiêu và hiện trạng

Mục tiêu của chủ máy (từ [docs/890M-ROADMAP.md](docs/890M-ROADMAP.md), 2026-10-18): port đầy đủ 890M trên macOS Tahoe, không phụ
thuộc NullMoth, với WindowServer được vẽ trên iGPU. Đó là thứ loại bỏ mức 500-900 % CPU của WindowServer
([docs/WINDOWSERVER-CPU.md](docs/WINDOWSERVER-CPU.md)), vốn đến từ bộ rasteriser phần mềm của CoreAnimation khi không có thiết bị
Metal. Các mốc trong roadmap, tại thời điểm kiểm tra đó:

| # | Mốc | Trạng thái lúc đó |
|---|---|---|
| M1 | Driver kernel riêng khởi động 890M, DRM node, chạy IB, compute | xong |
| M2 | Graphics job ổn định (gfx ring, VM, fence) | đang làm |
| M3 | Accelerator không headless để WindowServer có thiết bị Metal và present | đã kiểm tra |
| M4 | Userland riêng (libdrm, RADV, rồi driver Metal) | chưa bắt đầu |
| M5 | Bỏ các binary kernel của NullMoth | sau M3 và M4 |

Các bước sau nằm trong tài liệu handoff và trace; commit cuối của lịch sử này (Step72, 2026-10-26) nói về việc WindowServer đọc
`debug.nvaccelfb` của NVIDIA và một plugin mang các bản sửa AMD 780M. Xem mục "Latest override" mới nhất của handoff để biết
hiện trạng; README này không cập nhật theo từng bước.

## Gồm những gì

| Phần | Ở đâu | Làm gì |
|---|---|---|
| `StrixGOP.kext` | `kexts/StrixGOP` | Framebuffer nhận raster GOP lúc khởi động, thêm độ sáng OLED qua DPCD trên engine DPAUX của DCN35 |
| `StrixAccel.kext` | `kexts/StrixAccel` | Accelerator chỉ hiển thị (IOAccelerator / display pipe) để CoreDisplay gắn được framebuffer |
| `StrixMetalGate.kext` | `kexts/StrixMetalGate` | Cho WindowServer thiết bị Metal khi màn hình duy nhất không nằm trên GPU NVIDIA |
| `StrixHeadroom.kext` | `kexts/StrixHeadroom` | Plugin Lilu bỏ tranh chấp khóa trong `CoreDisplay::Display::CurrentHeadroom()` |
| `StrixProbe.kext` | `kexts/StrixProbe` | Dịch vụ chẩn đoán tùy chọn, không bao giờ là driver GPU |
| Dữ liệu ABI | `abi/strix`, `include/StrixNativeABI.h` | Profile IOAccelerator của macOS 24H32 và header ABI native |
| Patch | `patches/nmx` | Patch cho mã nguồn NullMoth (xem giấy phép ở [NOTICE.md](NOTICE.md)) |
| Công cụ | `tools/`, `scripts/` | Probe Metal/Vulkan (`tools/890m`), trace phía Linux, script cài và thu thập, test máy chủ ở `test/` |

## Build

Trên macOS có Xcode command line tools (không build kext được trên Linux):

```bash
bash scripts/build.sh                 # cả năm kext vào build/
bash scripts/build.sh StrixGOP        # một kext
```

StrixHeadroom tự clone header Lilu vào `build/Lilu` lần đầu. CI build tương tự trên `macos-14`.
Script cài là `scripts/macos-strix-*-install.sh`; đa số cần ESP của OpenCore và khởi động lại.

## Nhánh

* `main`: dòng nghiên cứu 890M (trước là `research/890m-cobalt64` ở repo EFI).
* `dev/tahoe-igpu`: dòng iGPU trước là `awdl/tahoe-igpu` ở repo EFI, đã lọc theo các đường dẫn này.

Lịch sử các file này được tách từ `thanhnndev/ga403wm-hackintosh` bằng `git filter-repo`; commit giữ nguyên ngày và tác giả. Các
file không thuộc việc 890M (Wi-Fi, Bluetooth, ROG Control) không có ở đây.

## Giấy phép

[Clear BSD](LICENSE) cho mã viết trong repo này. Xem [NOTICE.md](NOTICE.md) cho các phần không thuộc giấy phép đó.
