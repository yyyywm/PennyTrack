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

## 运行前端

```bash
# 安装依赖
flutter pub get

# 运行调试（Android）
flutter run

# 运行测试
flutter test

# 静态分析
flutter analyze

# 格式化代码
dart format .
```

## 运行后端

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

# 配置环境变量（或创建 .env 文件）
export BOOKKEEPING_DATABASE_URL="mysql+pymysql://user:pass@host:3306/db"
export BOOKKEEPING_SECRET_KEY="your-strong-secret-key"

# 启动开发服务器
uvicorn main:app --reload --port 8000

# 生产模式
uvicorn main:app --host 0.0.0.0 --port 5300
```

### Docker 部署

`backend/` 目录下提供 `Dockerfile` 和 `docker-compose.yml`，部署形态为 **单容器**：只构建并运行 FastAPI 后端，**不会**启动任何数据库容器，应用通过 `BOOKKEEPING_DATABASE_URL` 连接你已有的外部 MySQL。

**特性：**
- **Volume 挂载**：`docker-compose.yml` 将主机的 `./main.py` 以只读方式挂载到容器中，代码变更后只需 `docker compose restart` 即可生效，无需重新构建镜像
- **启动版本校验**：容器启动时会打印 `main.py` 的 MD5 校验码前 8 位，便于确认代码更新是否生效
- **无缓存模式**：`PYTHONDONTWRITEBYTECODE=1` 防止 `.pyc` 缓存导致旧代码被加载

**1. 配置环境变量**

```bash
cp backend/.env.example backend/.env
# 编辑 backend/.env：
#   BOOKKEEPING_SECRET_KEY     生产环境必须改成强随机字符串
#   BOOKKEEPING_DATABASE_URL   填你已有的外部 MySQL，例如：
#                              mysql+pymysql://user:pass@1.2.3.4:3306/bookkeeping
```

**2. 使用 Docker Compose 启动（推荐）**

```bash
cd backend

# 构建并启动后端容器（仅一个容器）
docker compose up -d --build

# 查看日志（首次启动应看到 "Database connection verified successfully"）
docker compose logs -f backend

# 停止服务
docker compose down
```

启动后只会出现 **一个** 容器：
- `pennytrack-backend` — FastAPI 应用，镜像 `pennytrack-backend:latest`，宿主端口 `5300`

启动时容器会做：①以指数退避方式 `SELECT 1` 验证外部 MySQL 连通性；②对缺失的表执行 `CREATE TABLE IF NOT EXISTS`（已存在则跳过，不破坏数据）。整个过程**不会创建新的 MySQL 容器**。

**3. 仅用 `docker build` 手动构建（不走 compose）**

```bash
cd backend

# 必须用 -t 显式打标签，否则会得到无名镜像
docker build -t pennytrack-backend:latest .

# 运行容器（环境变量与外部 MySQL 同上）
docker run -d \
  -p 5300:5300 \
  -e PORT=5300 \
  -e BOOKKEEPING_SECRET_KEY="your-secret-key" \
  -e BOOKKEEPING_DATABASE_URL="mysql+pymysql://user:pass@host:3306/db" \
  --name pennytrack-backend \
  pennytrack-backend:latest
```

**4. 健康检查**

```bash
# 轻量健康端点（compose healthcheck 也用此端点）
curl http://localhost:5300/healthz

# 包含数据库版本的根端点
curl http://localhost:5300/
```

## 构建

### 配置后端地址

首次克隆或首次构建前，需要配置你自己的后端地址：

```bash
# 1. 复制配置文件模板
cp lib/config/api_config.template.dart lib/config/api_config.dart

# 2. 编辑 lib/config/api_config.dart，填入你的服务器 IP
```

### Android APK

项目提供了自动注入脚本，构建前会将 `api_config.dart` 中的真实 IP 自动写入 `network_security_config.xml`（ColorOS/MIUI 等 ROM 必需），构建完成后自动恢复占位符，避免 IP 意外提交到 Git。

```bash
# 推荐：使用包装脚本（自动注入 + 构建 + 恢复）
dart run scripts/build_apk.dart

# 构建 Release 版
dart run scripts/build_apk.dart --release

# 或直接运行 flutter build（需手动确保 XML 中 IP 正确）
flutter build apk
```

### Android App Bundle

```bash
flutter build appbundle
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

## 注意事项

- 后端地址配置在 `lib/config/api_config.dart` 中（需从 `api_config.template.dart` 复制并填写自己的地址），支持自动探测模拟器/生产环境
- 未登录时数据仅保存在本地，跨天自动清空；登录后数据持久化到云端
- 后端强制使用 MySQL，启动时若未配置 `BOOKKEEPING_DATABASE_URL` 或连接失败会直接报错退出
- CORS 在生产环境应指定具体域名，禁止通配符
- Android 网络适配：针对 ColorOS、MIUI 等国产 ROM 做了明文传输白名单配置，确保 HTTP 后端可正常连接
