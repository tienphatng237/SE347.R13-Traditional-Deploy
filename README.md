# Triển khai truyền thống cho Roadmap Maker

Repository này chứa hạ tầng và cấu hình máy chủ để triển khai repository `application-web` trên một EC2 Ubuntu. Repository này cố ý không chứa mã nguồn ứng dụng hoặc thông tin bí mật.

## Kiến trúc triển khai

```mermaid
flowchart LR
    Browser[Trình duyệt] -->|HTTP :80| Nginx[Nginx]
    Nginx -->|Phục vụ static files| Frontend[React build<br/>/var/www/roadmap-maker]
    Nginx -->|/api/*| Express[Express API<br/>127.0.0.1:3000]
    Express -->|Prisma| Database[(PostgreSQL<br/>127.0.0.1:5432)]
```

Chỉ Nginx được truy cập từ Internet. Security group chỉ mở HTTP/HTTPS công khai và chỉ cho phép SSH từ `ssh_allowed_cidr`; Express cùng PostgreSQL không có cổng public.

## Terraform sẽ tạo gì?

- Một VPC riêng, một public subnet, route table và internet gateway.
- Một EC2 chạy Ubuntu 22.04, ổ đĩa gốc mã hoá dung lượng 20 GB.
- Security group: HTTP (80) và HTTPS (443) mở cho Internet; SSH (22) chỉ cho phép IP tại `ssh_allowed_cidr`.
- Cài sẵn Nginx, PostgreSQL, Node.js 20, Git và rsync khi máy EC2 khởi tạo.

Terraform không tự triển khai ứng dụng hoặc tạo tài khoản/mật khẩu cơ sở dữ liệu. Cách này giúp không ghi secret vào Terraform state.

## 1. Tạo hạ tầng EC2

Cần có Terraform và AWS CLI trên máy local. AWS CLI phải được cấu hình bằng một IAM user/role có quyền tạo EC2, VPC, subnet, route table và security group. Kiểm tra xác thực trước:

```powershell
aws sts get-caller-identity
```

Nếu lệnh trả về `Account`, `UserId` và `Arn` thì tiếp tục. Các lệnh dưới đây dùng region `ap-southeast-1`, giống cấu hình mặc định trong Terraform.

### 1.1. Tạo SSH key cục bộ

Cặp SSH key được tạo và giữ ở máy local, không dùng lệnh AWS CLI để tạo key pair. Terraform sẽ đọc **public key** `.pub` và tạo key pair tương ứng trên AWS khi chạy `terraform apply`. Private key luôn ở máy local.

Lệnh dưới đây cần được chạy từ thư mục gốc `traditional-deploy`. Key sẽ nằm tại `key_pair/`, thư mục này đã được đưa vào `.gitignore`.

#### Windows PowerShell

```powershell
New-Item -ItemType Directory -Force key_pair | Out-Null
ssh-keygen -t ed25519 -f .\key_pair\roadmap-maker-key -N '""' -C "roadmap-maker-ec2"
```

#### Linux hoặc macOS

```bash
mkdir -p key_pair
ssh-keygen -t ed25519 -f ./key_pair/roadmap-maker-key -N "" -C "roadmap-maker-ec2"
chmod 600 ./key_pair/roadmap-maker-key
```

Các file tạo ra là `key_pair/roadmap-maker-key` (private key) và `key_pair/roadmap-maker-key.pub` (public key). Không chia sẻ hoặc commit private key. Với repository này, `key_name` trong `terraform.tfvars` phải là `roadmap-maker-key` để Terraform đọc đúng public key.

### 1.2. Lấy public IP để chỉ cho phép SSH từ máy của bạn

`ssh_allowed_cidr` cần public IPv4 theo định dạng `/32`. Nếu dùng Wi-Fi/VPN/IP động, giá trị này có thể thay đổi và bạn sẽ cần cập nhật Terraform trước khi SSH lại.

#### Windows PowerShell

```powershell
$myIp = (Invoke-RestMethod -Uri "https://checkip.amazonaws.com").Trim(); "$myIp/32"
```

#### Linux hoặc macOS

```bash
printf "%s/32\n" "$(curl -4 -s https://checkip.amazonaws.com | tr -d '\n')"
```

### 1.3. Tạo `terraform.tfvars`

Tại thư mục `infra/terraform`, tạo file `terraform.tfvars` từ file mẫu, sau đó điền tên key pair và public IP vừa lấy được.

#### Windows PowerShell

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars
```

#### Linux hoặc macOS

```bash
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

Nội dung cần có dạng sau:

```hcl
key_name         = "roadmap-maker-key"
ssh_allowed_cidr = "YOUR_PUBLIC_IP/32"
instance_type    = "t3.micro"
```

### 1.4. Khởi tạo và tạo hạ tầng bằng Terraform

```bash
cd infra/terraform
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Lưu lại output `public_ip`. Khi hoàn thành phần demo và không còn dùng AWS, huỷ toàn bộ tài nguyên để tránh phát sinh chi phí:

```bash
terraform destroy
```

## 2. Cấu hình máy chủ

SSH theo lệnh `ssh_command` mà Terraform output. Clone cả repository ứng dụng và repository triển khai:

```bash
sudo git clone <APPLICATION_WEB_GIT_URL> /opt/application-web
sudo chown -R deploy:deploy /opt/application-web
git clone <TRADITIONAL_DEPLOY_GIT_URL> ~/traditional-deploy
cd ~/traditional-deploy
```

### 2.1. Cấu hình database và biến môi trường backend

Tạo database PostgreSQL cùng tài khoản có quyền tối thiểu. Chọn mật khẩu mạnh và thay `CHANGE_THIS_PASSWORD`:

```bash
sudo -u postgres psql
CREATE USER roadmap_app WITH PASSWORD 'CHANGE_THIS_PASSWORD';
CREATE DATABASE roadmap_maker OWNER roadmap_app;
\q
```

Tạo file môi trường chỉ dành cho backend. Password database nằm trong `DATABASE_URL` của file này; không commit file đã điền password.

```bash
sudo install -m 0640 -o root -g deploy .env.production.example /etc/roadmap-maker/backend.env
sudoedit /etc/roadmap-maker/backend.env
```

Nội dung sau là ví dụ:

```env
NODE_ENV=production
PORT=3000
DATABASE_URL="postgresql://roadmap_app:CHANGE_THIS_PASSWORD@127.0.0.1:5432/roadmap_maker?schema=public"
```

### 2.2. Cấu hình Nginx bằng public IP

Public IP **không cần** đặt trong `backend.env`: frontend gọi API cùng origin qua `/api`, còn Nginx chuyển tiếp request đến Express nội bộ tại `127.0.0.1:3000`.

Lấy public IP của EC2 từ máy local:

```powershell
terraform output -raw public_ip
```

Khi đang SSH trên EC2, thay `YOUR_EC2_PUBLIC_IP` trong lệnh dưới đây bằng IP đó. Cài systemd service và Nginx site:

```bash
sudo install -m 0644 config/systemd/roadmap-maker-backend.service /etc/systemd/system/roadmap-maker-backend.service
sed 's/__SERVER_NAME__/YOUR_EC2_PUBLIC_IP/' config/nginx/roadmap-maker.conf | sudo tee /etc/nginx/sites-available/roadmap-maker >/dev/null
sudo ln -s /etc/nginx/sites-available/roadmap-maker /etc/nginx/sites-enabled/roadmap-maker
sudo rm -f /etc/nginx/sites-enabled/default
sudo systemctl daemon-reload
sudo systemctl enable roadmap-maker-backend
sudo nginx -t
sudo systemctl reload nginx
```

## 3. Triển khai ứng dụng

Repository `traditional-deploy` đã được clone ở bước 2, chạy script từ thư mục đó:

```bash
sudo bash scripts/deploy.sh /opt/application-web
```

Frontend được build với `VITE_API_BASE_URL=/api`. Vì vậy, Nginx sẽ chuyển `/api/boards` thành `/boards` trên Express, khớp với các backend route hiện tại và không cần mở cổng 3000 ra Internet.

## 4. Bật HTTPS

Nếu chỉ dùng public IP EC2, bỏ qua bước này và truy cập ứng dụng bằng `http://YOUR_EC2_PUBLIC_IP`. Let's Encrypt không cấp chứng chỉ HTTPS hợp lệ cho public IP.

Chỉ thực hiện bước này khi bạn có domain và DNS domain đã trỏ đến public IP của EC2:

```bash
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
sudo certbot --nginx -d YOUR_DOMAIN
```

Trước khi nộp bài, kiểm tra website, các thao tác tạo/sửa/xoá, kéo-thả card, `http://YOUR_EC2_PUBLIC_IP/api-docs` (hoặc `https://YOUR_DOMAIN/api-docs` khi có domain) và việc ứng dụng tự chạy lại sau reboot (`sudo reboot`).
