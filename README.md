# Báo cáo Thực hành DevOps - Session 10: Bài 3
## Tối ưu hóa Dung lượng Image & Layer Caching với Multi-stage Build

- **Học viên:** Đào Trọng Trí
- **Mã sinh viên:** PTIT062
- **Lớp:** DevOps / Cloud Native Engineering
- **Bài tập:** Tối ưu hóa Dockerfile sang chuẩn Multi-stage Build cho môi trường Production

---

## 1. Mục tiêu và Bối cảnh
- Ứng dụng công nghệ **Multi-stage Build** nhằm phân tách môi trường phát triển (build/test tools, devDependencies) khỏi môi trường vận hành thực tế (runtime environment).
- Tận dụng cơ chế **Layer Caching** của Docker để tăng tốc độ build lặp lại khi chỉ mã nguồn thay đổi mà dependencies giữ nguyên.
- Giảm thiểu dung lượng Docker Image xuống mức tối thiểu (dưới 100MB), loại bỏ nguy cơ lộ mã nguồn không cần thiết và bề mặt tấn công an ninh (attack surface).
- Xây dựng 2 image để đo lường và so sánh:
  - `hw-backend:single`: Single-stage build chứa toàn bộ công cụ dev và cache.
  - `hw-backend:multistage`: Multi-stage build chỉ giữ lại runtime artifact.

---

## 2. Cấu trúc thư mục
```text
SS10_HW03_DaoTrongTri_PTIT062/
├── Dockerfile              # Multi-stage Dockerfile tối ưu hóa Production
├── Dockerfile.single       # Single-stage Dockerfile chưa tối ưu
├── .dockerignore           # Loại bỏ files thừa khi build context
├── package.json            # Khai báo dependencies và devDependencies (Jest, Supertest, Nodemon)
├── server.js               # Mã nguồn REST API Node.js/Express
└── README.md               # Báo cáo kỹ thuật phân tích so sánh chi tiết
```

---

## 3. So sánh Cấu hình Dockerfile

### 3.1. Phiên bản Single-stage (`Dockerfile.single`)
```dockerfile
FROM node:18-alpine
WORKDIR /app
ENV PORT=3000
ENV NODE_ENV=development
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
```
*Nhược điểm:* Quá trình `RUN npm install` kéo theo toàn bộ các gói kiểm thử nặng nề (`jest`, `supertest`, `nodemon`), các tệp cache của npm và lưu vĩnh viễn vào layer của Image cuối cùng.

### 3.2. Phiên bản Multi-stage (`Dockerfile`)
```dockerfile
# STAGE 1: Builder (Cài đặt dependencies và chuẩn bị sản phẩm)
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
# Dọn dẹp devDependencies trước khi sang stage runtime
RUN npm prune --production

# STAGE 2: Runtime (Image tối ưu chỉ chứa production dependencies)
FROM node:18-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/server.js ./
EXPOSE 3000
CMD ["node", "server.js"]
```
*Ưu điểm:*
1. **Layer Caching:** `COPY package*.json ./` được đặt trước `RUN npm install`. Nếu code thay đổi, bước cài dependencies sẽ được dùng lại từ cache mà không cần tải lại internet.
2. **Loại bỏ rác:** Lệnh `npm prune --production` dọn sạch devDependencies.
3. **Môi trường độc lập:** Chỉ sử dụng lệnh `COPY --from=builder` để sao chép đúng 3 tệp/thư mục: `package.json`, `node_modules` (chỉ gồm prod packages), và `server.js`. Toàn bộ file build tạm thời, npm cache ở Stage 1 bị hủy hoàn toàn.

---

## 4. Bảng So sánh Chi tiết: Single-stage vs Multi-stage

| Tiêu chí so sánh | Single-stage (`hw-backend:single`) | Multi-stage (`hw-backend:multistage`) | Đánh giá / Tỷ lệ tối ưu |
| :--- | :--- | :--- | :--- |
| **Dung lượng đĩa (Disk Usage)** | `398 MB` | `187 MB` | **Giảm 53.0%** dung lượng đĩa |
| **Dung lượng nén tải (Content Size)** | `81.5 MB` | `45.7 MB` | **Giảm 43.9%** (Đạt chuẩn < 100MB) |
| **Dung lượng Layer dependencies** | `180 MB` (chứa toàn bộ dev deps) | `4.71 MB` (chỉ runtime `node_modules`) | **Tối ưu hơn 97.3%** cho dependencies |
| **Số lượng Layer ứng dụng** | 5 layers | 4 layers tách biệt từ base | Gọn gàng, giảm thiểu metadata thừa |
| **Mức độ an ninh (Security)** | Thấp (chứa dev tool, có thể có lỗ hổng CVE) | Cao (chỉ chứa tệp tối thiểu cần để chạy) | Giảm thiểu tối đa bề mặt tấn công |
| **Tận dụng Docker Layer Cache** | Khá | Cực tốt (phân tầng builder/runtime rõ ràng) | Build tốc độ cao |

---

## 5. Nhật ký Lệnh Thực thi từ Terminal Thực tế

### 5.1. So sánh dung lượng hai Image (`docker images | grep -E "hw-backend|REPOSITORY"`)
```text
$ docker images | grep -E "hw-backend|REPOSITORY"
REPOSITORY                         IMAGE ID       DISK USAGE   CONTENT SIZE   EXTRA
hw-backend:multistage              b284c40e3469        187MB         45.7MB        
hw-backend:single                  dbf0d0223b44        398MB         81.5MB        
hw-backend:v1                      ee6487d7c3bb        196MB         47.4MB        
```

### 5.2. So sánh lịch sử Layer (`docker history`)

#### Single-stage (`hw-backend:single`):
```text
$ docker history hw-backend:single
IMAGE          CREATED         CREATED BY                                      SIZE      COMMENT
dbf0d0223b44   2 minutes ago   CMD ["node" "server.js"]                        0B        buildkit.dockerfile.v0
<missing>      2 minutes ago   EXPOSE [3000/tcp]                               0B        buildkit.dockerfile.v0
<missing>      2 minutes ago   COPY . . # buildkit                             41kB      buildkit.dockerfile.v0
<missing>      2 minutes ago   RUN /bin/sh -c npm install # buildkit           180MB     buildkit.dockerfile.v0
<missing>      3 minutes ago   COPY package*.json ./ # buildkit                12.3kB    buildkit.dockerfile.v0
<missing>      3 minutes ago   ENV NODE_ENV=development                        0B        buildkit.dockerfile.v0
<missing>      3 minutes ago   ENV PORT=3000                                   0B        buildkit.dockerfile.v0
<missing>      5 minutes ago   WORKDIR /app                                    8.19kB    buildkit.dockerfile.v0
...
```
*(Chú ý: Layer `RUN npm install` chiếm tới **180 MB** do cài đặt các gói dev).*

#### Multi-stage (`hw-backend:multistage`):
```text
$ docker history hw-backend:multistage
IMAGE          CREATED         CREATED BY                                      SIZE      COMMENT
b284c40e3469   1 minute ago    CMD ["node" "server.js"]                        0B        buildkit.dockerfile.v0
<missing>      1 minute ago    EXPOSE [3000/tcp]                               0B        buildkit.dockerfile.v0
<missing>      1 minute ago    COPY /app/server.js ./ # buildkit               12.3kB    buildkit.dockerfile.v0
<missing>      1 minute ago    COPY /app/node_modules ./node_modules # buil…   4.71MB    buildkit.dockerfile.v0
<missing>      1 minute ago    COPY /app/package*.json ./ # buildkit           197kB     buildkit.dockerfile.v0
<missing>      1 minute ago    ENV PORT=3000                                   0B        buildkit.dockerfile.v0
<missing>      1 minute ago    ENV NODE_ENV=production                         0B        buildkit.dockerfile.v0
<missing>      5 minutes ago   WORKDIR /app                                    8.19kB    buildkit.dockerfile.v0
...
```
*(Toàn bộ 180MB dev dependencies biến mất, layer `node_modules` chỉ còn **4.71 MB**).*

### 5.3. Kiểm tra hoạt động container Multi-stage (`docker run` & `curl`)
```text
$ docker run -d --name app-multistage-test -p 8080:3000 hw-backend:multistage
6b072f0d78d7a8222d8435614ad826c802f56fb70a4d346bd77f05f0e43a948c

$ curl -i http://localhost:8080/
HTTP/1.1 200 OK
X-Powered-By: Express
Content-Type: application/json; charset=utf-8
Content-Length: 136
ETag: W/"88-5xtbKkCaskaxRtn81zMCq8Pdiys"
Date: Tue, 13 Oct 2026 17:00:46 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{"status":"success","message":"Hello from Docker Multi-stage Optimized Backend!","version":"2.0.0-optimized","environment":"production"}
```

---

## 6. Hướng dẫn Chụp ảnh Minh chứng (Evidence Collection)

> **Hướng dẫn cho sinh viên:**
> 1. Mở Terminal và kết nối SSH vào máy chủ Linux:
>    ```bash
>    ssh devopsg5@103.72.57.148
>    ```
> 2. Chạy lệnh so sánh dung lượng hai image:
>    ```bash
>    docker images | grep hw-backend
>    ```
> 3. Chụp ảnh màn hình hiển thị cả `hw-backend:single` và `hw-backend:multistage` để làm rõ dung lượng chênh lệch (đặc biệt Content Size 45.7MB < 100MB).
> 4. Dán ảnh vào vị trí placeholder bên dưới.

### Minh chứng ảnh chụp:
`ImgEx: [Dán ảnh chụp màn hình so sánh dung lượng docker images của hw-backend:single và hw-backend:multistage tại đây]`
