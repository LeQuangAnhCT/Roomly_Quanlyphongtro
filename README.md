# ROOMLY — Quản lý việc nhà trọ

Ứng dụng Vue 3 + Vite + Supabase dành cho **một nhóm trọ mỗi tài khoản**. Giao diện mobile-first đen/trắng, tách biệt Shiftly.

## Production
- Vercel project: `roomly`
- Supabase project: `lupzssthgyfppmsrollr`
- Không dùng chung bất cứ bảng nào với Shiftly.

## Chức năng
- Google OAuth đăng nhập/đăng xuất, đồng bộ phiên.
- Tạo nhóm; mã mời 10 ký tự; tham gia nhóm; trưởng nhóm có thể đổi tên, xóa thành viên, giải tán nhóm; thành viên rời nhóm.
- Danh mục việc có giờ, thời lượng, số điểm và ngày lặp (1–7).
- Lịch 7 ngày thứ Hai–Chủ Nhật; phân công thủ công hoặc tự động; kiểm tra ngày rảnh, chồng giờ và tổng điểm công việc.
- Xác nhận hoàn thành/hoàn tác bởi người thực hiện.
- Đề nghị đổi việc, chấp nhận/từ chối; thông báo lưu trong DB.
- Thống kê điểm việc và lượt hoàn thành.
- RLS cho từng nhóm và tài khoản; các hành động nhạy cảm qua hàm Supabase RPC.

## Cài đặt cục bộ
1. `npm install`
2. Sao chép `.env.example` thành `.env`, điền **Supabase publishable key**, không bao giờ nhập service role key vào `VITE_*`.
3. `npm run dev`
4. `npm test` và `npm run build`

## Cấu hình OAuth bắt buộc
Trong Supabase Dashboard của **Roomly**: Authentication → Providers → Google, bật provider và cấu hình Google OAuth Client ID/Secret. Google Cloud OAuth redirect URI: `https://lupzssthgyfppmsrollr.supabase.co/auth/v1/callback`.
Trong Supabase Authentication → URL Configuration, thêm **Site URL** `https://roomly-eight-gamma.vercel.app` và `Redirect URLs` gồm `https://roomly-eight-gamma.vercel.app/**` và localhost cho dev.

Nếu Google OAuth chưa được bật, màn hình đăng nhập sẽ hiển thị nhưng người dùng không thể xác thực. Cần hoàn tất việc này trong Supabase/Google Cloud.

## Dữ liệu & phân quyền
- SQL nguồn `supabase/schema.sql`: **chỉ chạy một lần trên database mới, trống**. Dữ liệu Roomly production đã được tạo qua 3 migrations Supabase; không cần chạy lại file này.
- Chỉ trưởng nhóm phân lịch, sửa/xóa công việc; người được giao chỉ tự xác nhận hoàn thành; thành viên chỉ đọc dữ liệu nhóm mình.
- Chỉ những người trong nhóm biết mã mời mới có thể gia nhập.
- Không nhập token bí mật vào code frontend.

## Lưu ý nghiệp vụ
- Thuật toán phân lịch cân đối tổng điểm trong 4 tuần gần nhất và tránh trùng giờ trong cùng ngày, nhưng có thể thông báo khi không tìm thấy thành viên phù hợp; trưởng nhóm nên xem cảnh báo sau khi tạo lịch.
- Để tránh lộ thông tin nhạy cảm hoặc thao tác sai, lịch đã có công việc hoàn thành không thể tạo lại tự động.
- Thông báo đổi việc lưu trong ứng dụng; **chưa tích hợp Web Push nền** hoặc nhắc theo giờ OS. Đây là phần có thể triển khai tiếp nếu cần.
- Hiện chưa có hệ thống cho phép chuyển quyền trưởng nhóm; trưởng nhóm có thể giải tán nhóm để tạo lại.

## Đăng nhập email dự phòng
Nếu chưa thiết lập Google OAuth, người dùng có thể dùng **Gửi liên kết** (Supabase Email OTP/Magic Link), với điều kiện Supabase Authentication → Providers → Email được bật. Thêm production URL vào Authentication → URL Configuration để link đưa người dùng về đúng website.


## Khắc phục lỗi đăng nhập
- Đảm bảo Supabase Roomly (không phải Shiftly) → Authentication → Providers → Google đã bật, có đúng Client ID và Client Secret.
- Trong Google Cloud OAuth client, Authorized redirect URI là `https://lupzssthgyfppmsrollr.supabase.co/auth/v1/callback`.
- Trong Supabase Authentication → URL Configuration: Site URL `https://roomly-eight-gamma.vercel.app`, Redirect URLs cho phép `https://roomly-eight-gamma.vercel.app/**`.
- Nếu không dùng Google, bật Email provider trong Supabase; sử dụng nút Gửi liên kết trên giao diện đăng nhập. Email provider có thể hạn chế số lượng email gửi mặc định.
- Frontend hiện có xử lý lỗi OAuth và không kẹt loading nếu khôi phục phiên thất bại. Trường hợp OAuth nhà cung cấp chưa bật phải cấu hình qua dashboard, không thể bật bằng biến môi trường frontend.
