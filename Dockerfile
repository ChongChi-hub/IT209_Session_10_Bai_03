# ==========================================
# GIAI ĐOẠN 1: Builder (Xây dựng & Chuẩn bị phụ thuộc)
# ==========================================
FROM node:18-alpine AS builder

WORKDIR /app

# Tận dụng Docker Layer Caching: chỉ copy file khai báo phụ thuộc trước
COPY package*.json ./

# Cài đặt toàn bộ dependencies (bao gồm devDependencies để test/lint/build)
RUN npm install

# Sao chép mã nguồn ứng dụng
COPY . .

# Loại bỏ devDependencies để dọn dẹp node_modules chỉ giữ lại các gói production
RUN npm prune --production

# ==========================================
# GIAI ĐOẠN 2: Runtime (Môi trường vận hành Production siêu nhẹ)
# ==========================================
FROM node:18-alpine AS runner

WORKDIR /app

# Thiết lập môi trường Production và cổng ứng dụng
ENV NODE_ENV=production
ENV PORT=3000

# Chỉ trích xuất các sản phẩm cần thiết từ builder stage, loại bỏ layer thừa
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/server.js ./

# Khai báo cổng lắng nghe
EXPOSE 3000

# Chạy ứng dụng dạng exec form
CMD ["node", "server.js"]
