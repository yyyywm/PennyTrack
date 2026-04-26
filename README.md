# PennyTrack

一个基于 Flutter + FastAPI 的个人记账本应用。

## 功能

- **记账管理**：记录收入与支出，支持自定义日期、分类和备注
- **日期筛选**：支持今日、本月、自定义日期范围查看
- **分类管理**：用户注册时自动创建收入/支出默认分类（工资、餐饮、交通、购物等）
- **数据同步**：登录后自动将本地离线记录同步到云端
- **统计图表**：月度收支汇总、分类饼图、每日收支趋势柱状图
- **持久化认证**：JWT Token 本地存储，自动恢复登录状态
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
│   ├── models/            # 数据模型（Transaction、Category）
│   ├── pages/             # 页面（首页、统计、登录/注册、导航）
│   ├── services/          # 业务服务（API、认证、存储、同步）
│   ├── utils/             # 工具函数（图标映射、Toast）
│   └── widgets/           # 可复用组件（交易卡片、添加弹窗）
├── backend/               # FastAPI 后端源码
│   ├── main.py            # 单文件应用：模型、路由、认证、统计
│   ├── requirements.txt   # Python 依赖
│   ├── Dockerfile         # Docker 镜像构建
│   └── .env               # 本地环境变量（已 gitignore）
├── docker-compose.yml     # 一键启动后端 + MySQL
├── assets/images/         # 应用图片资源
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

项目已包含 `Dockerfile` 和 `docker-compose.yml`，支持一键启动后端 + MySQL。

**1. 配置环境变量**

```bash
cp backend/.env.example backend/.env
# 编辑 backend/.env，修改 BOOKKEEPING_SECRET_KEY
```

**2. 使用 Docker Compose 启动（推荐）**

```bash
# 一键启动后端 + MySQL
docker-compose up -d

# 查看日志
docker-compose logs -f app

# 停止服务
docker-compose down

# 停止并删除数据卷（谨慎使用）
docker-compose down -v
```

Compose 会启动两个容器：
- `bookkeeping-db` — MySQL 8.0，数据持久化到 `mysql_data` 卷
- `bookkeeping-api` — FastAPI 应用，端口 `5300`

**3. 仅构建/运行后端镜像（已有外部 MySQL）**

```bash
cd backend

# 构建镜像
docker build -t bookkeeping-api .

# 运行容器
docker run -d \
  -p 5300:5300 \
  -e PORT=5300 \
  -e BOOKKEEPING_SECRET_KEY="your-secret-key" \
  -e BOOKKEEPING_DATABASE_URL="mysql+pymysql://user:pass@host:3306/db" \
  --name bookkeeping-api \
  bookkeeping-api
```

**4. 健康检查**

```bash
# 检查后端是否正常运行
curl http://localhost:5300/
```

## 构建

```bash
# Android APK
flutter build apk

# Android App Bundle
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

- 后端地址配置在 `lib/services/api_service.dart` 中，支持自动探测模拟器/生产环境
- 未登录时数据仅保存在本地，跨天自动清空；登录后数据持久化到云端
- 后端强制使用 MySQL，启动时若未配置 `BOOKKEEPING_DATABASE_URL` 或连接失败会直接报错退出
- CORS 在生产环境应指定具体域名，禁止通配符
