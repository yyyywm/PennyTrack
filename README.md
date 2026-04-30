# PennyTrack

一个基于 Flutter + FastAPI 的个人记账本应用。

## 功能

- **记账管理**：记录收入与支出，支持自定义日期、分类和备注
- **智能输入**：支持自然语言输入（如"打车26"、"工资8500"），1秒防抖后自动解析金额、收支类型、分类和备注
- **日期筛选**：支持今日、本月、自定义日期范围查看
- **分类管理**：用户注册时自动创建收入/支出默认分类（工资、餐饮、交通、购物等）
- **数据同步**：登录后自动将本地离线记录同步到云端，带互斥锁防止重复上传
- **统计图表**：月度收支汇总、分类饼图、每日收支趋势柱状图，支持环比变化展示
- **持久化认证**：JWT Token 本地存储，自动恢复登录状态（Token 有效期 7 天）
- **离线支持**：未登录时数据存储在本地，登录后自动批量上传

## 技术栈

### 前端
- **Flutter** — 跨平台 UI 框架（Android）
- **Dio** — HTTP 客户端，支持自动 URL 探测与 Token 注入
- **SharedPreferences** — 本地键值存储与认证状态持久化
- **Provider** — 全局认证状态管理（`AuthService` 单例）

### 后端
- **FastAPI** — Python Web 框架
- **SQLAlchemy + PyMySQL** — 同步 ORM + MySQL 驱动
- **Passlib + python-jose** — 密码哈希 + JWT 签发与验证

## 项目结构

```
.
├── lib/                   # Flutter 前端源码
│   ├── main.dart          # 应用入口、主题配置
│   ├── config/            # 配置文件（后端地址，不提交到 Git）
│   ├── models/            # 数据模型（Transaction、Category）
│   ├── pages/             # 页面（首页、统计、登录/注册、导航）
│   ├── services/          # 业务服务（API、认证、存储、同步）
│   ├── utils/             # 工具函数（智能文本解析、图标映射、Toast）
│   └── widgets/           # 可复用组件（交易卡片、添加弹窗）
├── backend/                 # FastAPI 后端源码
│   ├── main.py              # 单文件应用：模型、路由、认证、统计
│   ├── requirements.txt     # Python 依赖
│   ├── Dockerfile           # 多阶段镜像构建（builder + runtime）
│   ├── docker-compose.yml   # 单容器编排（仅后端，连接外部 MySQL）
│   ├── .dockerignore
│   ├── .env.example         # 环境变量模板
│   └── .env                 # 本地环境变量（已 gitignore）
├── assets/images/           # 应用图片资源
├── test/                  # Flutter 测试
├── pubspec.yaml
├── analysis_options.yaml  # Dart 静态分析配置
└── README.md
```

## 环境要求

| 组件 | 最低版本 | 说明 |
|---|---|---|
| Flutter | 3.19+ | 前端框架 |
| Dart | 3.3+ | Flutter 内置 |
| Python | 3.10+ | 后端运行环境 |
| MySQL | 5.7+ 或 8.0+ | 数据持久化（**不支持 SQLite**） |
| Docker | 24.0+ | 可选，用于容器化部署 |
| Docker Compose | 2.20+ | 可选，用于容器化部署 |

## 从零开始部署

### 第一步：准备 MySQL 数据库

本项目**不提供内置数据库**，你需要提前准备好一个 MySQL 实例。

**1. 创建数据库和用户**

```sql
-- 以 root 身份登录 MySQL
mysql -u root -p

-- 创建数据库（使用 utf8mb4 支持 emoji 等字符）
CREATE DATABASE bookkeeping CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 创建专用用户（建议不要用 root）
CREATE USER 'bookkeeping'@'%' IDENTIFIED BY '你的强密码';

-- 授予权限
GRANT ALL PRIVILEGES ON bookkeeping.* TO 'bookkeeping'@'%';
FLUSH PRIVILEGES;
```

**2. 开放防火墙端口**

确保服务器防火墙允许后端应用访问 MySQL（默认 3306 端口）。如果你在同一台机器上部署，通常不需要额外配置；如果是云数据库，需要在云平台安全组中放行。

**3. 测试连接**

```bash
mysql -u bookkeeping -p -h 你的MySQL地址 -P 3306 -D bookkeeping
```

---

### 第二步：部署后端

#### 方式 A：Docker Compose 部署（推荐）

**1. 克隆项目并进入后端目录**

```bash
git clone https://github.com/yyyywm/PennyTrack.git
cd PennyTrack/backend
```

**2. 配置环境变量**

```bash
# 复制模板
cp .env.example .env

# 编辑 .env，填入以下内容：
```

`.env` 文件内容：

```bash
# ========== 必填项 ==========

# JWT 签名密钥（生产环境必须修改！）
# 生成强随机密钥的方法：
#   python -c "import secrets; print(secrets.token_urlsafe(48))"
BOOKKEEPING_SECRET_KEY=your-super-secret-key-here

# MySQL 连接串（格式：mysql+pymysql://用户名:密码@地址:端口/数据库名）
# 示例：
#   - 远端云数据库：mysql+pymysql://bookkeeping:密码@1.2.3.4:3306/bookkeeping
#   - 本机 MySQL（Linux/Mac）：mysql+pymysql://bookkeeping:密码@host.docker.internal:3306/bookkeeping
#   - 同机部署：mysql+pymysql://bookkeeping:密码@127.0.0.1:3306/bookkeeping
BOOKKEEPING_DATABASE_URL=mysql+pymysql://bookkeeping:你的密码@你的MySQL地址:3306/bookkeeping
```

**⚠️ 安全警告：**
- `BOOKKEEPING_SECRET_KEY` 必须使用强随机字符串，泄漏会导致所有用户 Token 可被伪造
- `.env` 文件已被 `.gitignore` 忽略，**切勿手动将其加入版本控制**

**3. 启动服务**

```bash
# 构建并启动（后台运行）
docker compose up -d --build

# 查看启动日志（首次启动需要等待 MySQL 连接验证）
docker compose logs -f backend
```

看到以下日志表示启动成功：
```
[version] main.py checksum: xxxxxxxx
Database connection verified successfully
Uvicorn running on http://0.0.0.0:5300
```

**4. 开放后端端口**

确保服务器防火墙放行 5300 端口（或你自定义的端口）。如果你使用云服务器，还需要在云平台安全组中添加规则。

**5. 验证服务**

```bash
# 健康检查
curl http://你的服务器IP:5300/healthz

# 根端点（返回数据库版本）
curl http://你的服务器IP:5300/
```

**6. 常用运维命令**

```bash
# 查看日志
docker compose logs -f backend

# 重启服务（代码更新后只需 restart，无需 rebuild）
docker compose restart

# 停止服务
docker compose down

# 更新代码后重新加载
git pull
docker compose restart
```

---

#### 方式 B：裸机部署（不依赖 Docker）

适合开发调试或已有 Python 环境的机器。

```bash
cd backend

# 创建虚拟环境
python -m venv venv

# 激活虚拟环境（Windows）
venv\Scripts\activate
# 激活虚拟环境（macOS/Linux）
# source venv/bin/activate

# 安装依赖
pip install -r requirements.txt

# 设置环境变量（Linux/macOS）
export BOOKKEEPING_SECRET_KEY="你的强随机密钥"
export BOOKKEEPING_DATABASE_URL="mysql+pymysql://bookkeeping:密码@地址:3306/bookkeeping"

# 启动开发服务器（热重载，仅开发用）
uvicorn main:app --reload --port 8000

# 生产模式
uvicorn main:app --host 0.0.0.0 --port 5300
```

---

### 第三步：配置前端并构建 APK

**1. 复制前端配置模板**

```bash
# 回到项目根目录
cd ..

# 复制配置文件
cp lib/config/api_config.template.dart lib/config/api_config.dart
```

**2. 编辑 `lib/config/api_config.dart`**

```dart
class ApiConfig {
  // 填你部署后端的公网 IP 或域名
  static const String productionUrl = 'http://你的服务器IP:5300';

  // 本地开发用，一般不用改
  static const String emulatorUrl = 'http://10.0.2.2:5300';
}
```

**3. 安装 Flutter 依赖**

```bash
flutter pub get
```

**4. 构建 APK**

```bash
# 推荐：使用自动注入脚本（自动处理 network_security_config.xml）
dart run scripts/build_apk.dart --release

# 构建完成后 APK 位于：
# build/app/outputs/flutter-apk/app-release.apk
```

**脚本工作原理：**
1. 从 `api_config.dart` 读取 `productionUrl` 中的 IP
2. 自动替换 `android/app/src/main/res/xml/network_security_config.xml` 中的 `YOUR_SERVER_IP`
3. 运行 `flutter build apk`
4. 无论构建成败，自动恢复 XML 中的占位符，防止 IP 泄露到 Git

---

### 第四步：运行和调试前端

```bash
# 连接真机或启动模拟器后运行
flutter run

# 运行测试
flutter test

# 静态分析
flutter analyze

# 格式化代码
dart format .
```

---

## Docker 部署详解

`backend/` 目录下提供 `Dockerfile` 和 `docker-compose.yml`，部署形态为 **单容器**：只构建并运行 FastAPI 后端，**不会**启动任何数据库容器，应用通过 `BOOKKEEPING_DATABASE_URL` 连接你已有的外部 MySQL。

**Docker Compose 特性：**
- **Volume 挂载**：`docker-compose.yml` 将主机的 `./main.py` 以只读方式挂载到容器中，代码变更后只需 `docker compose restart` 即可生效，无需重新构建镜像
- **启动版本校验**：容器启动时会打印 `main.py` 的 MD5 校验码前 8 位，便于确认代码更新是否生效
- **无缓存模式**：`PYTHONDONTWRITEBYTECODE=1` 防止 `.pyc` 缓存导致旧代码被加载
- **资源限制**：内存上限 512MB、CPU 上限 1.0 核，防止异常拖垮宿主
- **健康检查**：每 30 秒检查一次 `/healthz`，连续 3 次失败自动重启容器
- **日志轮转**：单个日志文件最大 10MB，保留 3 个文件

## 构建（仅前端 APK）

### 配置后端地址

首次克隆或首次构建前，需要配置你自己的后端地址：

```bash
# 1. 复制配置文件模板
cp lib/config/api_config.template.dart lib/config/api_config.dart

# 2. 编辑 lib/config/api_config.dart，填入你的服务器 IP
```

`lib/config/api_config.dart` 示例：

```dart
class ApiConfig {
  // 生产环境：填你部署后端的公网 IP 或域名
  static const String productionUrl = 'http://1.2.3.4:5300';

  // Android 模拟器访问宿主机 localhost 的地址（本地开发用，一般不用改）
  static const String emulatorUrl = 'http://10.0.2.2:5300';
}
```

**⚠️ 该文件已被 `.gitignore` 忽略，不会提交到 Git。**

### Android APK

项目提供了自动注入脚本，构建前会将 `api_config.dart` 中的真实 IP 自动写入 `network_security_config.xml`（ColorOS/MIUI 等 ROM 必需），构建完成后自动恢复占位符，避免 IP 意外提交到 Git。

```bash
# 推荐：使用包装脚本（自动注入 + 构建 + 恢复）
dart run scripts/build_apk.dart

# 构建 Release 版
dart run scripts/build_apk.dart --release

# 构建 Debug 版
dart run scripts/build_apk.dart --debug
```

构建完成后 APK 位于：`build/app/outputs/flutter-apk/app-release.apk`

**注意事项：**
- 脚本会自动处理 `network_security_config.xml`，你不需要手动修改 XML
- 如果脚本运行失败，可以手动注入：`dart run scripts/inject_network_config.dart`
- 直接运行 `flutter build apk` 不会自动注入 IP，可能导致 ColorOS/MIUI 设备无法连接后端

### Android App Bundle

```bash
# 需要先注入 IP（因为 ABB 构建不走 build_apk.dart 脚本）
dart run scripts/inject_network_config.dart
flutter build appbundle
# 构建完成后建议恢复占位符：git checkout android/app/src/main/res/xml/network_security_config.xml
```

## API 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/` | 健康检查 + 数据库版本 |
| POST | `/token` | 登录（OAuth2 Password） |
| POST | `/users/` | 用户注册（自动创建默认分类） |
| GET | `/users/me/` | 获取当前用户信息 |
| GET | `/categories/` | 获取分类列表（支持按 type 筛选） |
| POST | `/categories/` | 创建新分类 |
| GET | `/transactions/` | 查询交易记录（支持日期/分类/类型筛选） |
| POST | `/transactions/` | 创建交易记录 |
| GET | `/transactions/{id}` | 获取单条交易记录 |
| PUT | `/transactions/{id}` | 更新交易记录 |
| DELETE | `/transactions/{id}` | 删除交易记录 |
| GET | `/summary/` | 财务摘要（收入/支出/结余 + 环比） |
| GET | `/category-stats/` | 支出分类统计（饼图数据） |
| GET | `/trends/` | 收支趋势（日/月/季/年 聚合） |

## 安全建议

- **JWT Secret**：`BOOKKEEPING_SECRET_KEY` 必须使用强随机字符串（建议使用 `python -c "import secrets; print(secrets.token_urlsafe(48))"` 生成），泄漏会导致所有用户 Token 可被伪造
- **数据库密码**：MySQL 用户密码建议使用 16 位以上随机字符串，不要用简单密码
- **公网部署**：建议在后端前加反向代理（Nginx/Caddy）并配置 HTTPS，不要直接暴露 HTTP 端口到公网
- **端口安全**：如果不需要公网直接访问后端，可以将 docker-compose.yml 中的端口映射改为 `127.0.0.1:5300:5300`，只允许本机或反向代理访问
- **CORS**：`main.py` 中 CORS 配置允许所有来源（`*`），生产环境应修改为只允许你的前端域名
- **敏感文件保护**：`.env` 和 `lib/config/api_config.dart` 都已被 `.gitignore` 忽略，**切勿手动将其加入版本控制**

## 常见问题

**Q1: 后端启动报错 "Can't connect to MySQL server"**

- 检查 `BOOKKEEPING_DATABASE_URL` 中的 IP、端口、用户名、密码是否正确
- 检查 MySQL 是否允许远程连接（`bind-address` 配置）
- 检查服务器防火墙和云平台安全组是否放行 3306 端口
- 在容器内测试：`docker compose exec backend python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:5300/').read())"`

**Q2: Android 真机无法连接后端**

- 确认 `lib/config/api_config.dart` 中的 `productionUrl` 填的是公网 IP
- 确认服务器防火墙和云平台安全组放行 5300 端口
- ColorOS/MIUI 设备必须使用 `dart run scripts/build_apk.dart` 构建，确保 XML 白名单被正确注入
- 测试：在真机浏览器中访问 `http://你的IP:5300/` 看是否能打开

**Q3: 如何更新后端代码？**

```bash
cd backend
git pull          # 拉取最新代码
docker compose restart  # 重启容器（无需 rebuild）
```

**Q4: 数据库表会自动创建吗？**

会。后端启动时会执行 `CREATE TABLE IF NOT EXISTS`，首次启动会自动创建所有表，已有数据不会丢失。
