from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, field_serializer
from datetime import datetime, timedelta, timezone
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, ForeignKey, Enum
from sqlalchemy.orm import declarative_base
from sqlalchemy.orm import sessionmaker, Session, relationship
import calendar
import enum
import os
import uvicorn
from dotenv import load_dotenv
from sqlalchemy import text
from typing import List, Optional, Dict, Any
import re

# 自动加载同目录下的 .env 文件（仅本地开发使用，生产环境通过系统环境变量注入）
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

# 配置（生产环境必须通过环境变量设置，避免敏感信息泄露到版本控制）
SECRET_KEY = os.environ.get("BOOKKEEPING_SECRET_KEY")
if not SECRET_KEY:
    print("WARNING: BOOKKEEPING_SECRET_KEY not set. Using insecure development fallback.")
    print("         NEVER deploy to production without setting this environment variable!")
    SECRET_KEY = "dev-insecure-secret-do-not-use-in-production"

ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

# 数据库配置（强制使用 MySQL，不再回退到 SQLite）
SQLALCHEMY_DATABASE_URL = os.environ.get("BOOKKEEPING_DATABASE_URL")
if not SQLALCHEMY_DATABASE_URL:
    print("ERROR: BOOKKEEPING_DATABASE_URL environment variable is not set.")
    print("       This application requires a MySQL database connection.")
    print("       Example: mysql+pymysql://user:password@host:port/dbname")
    raise RuntimeError("BOOKKEEPING_DATABASE_URL is required")

engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True,
    pool_recycle=3600,
)

# 启动时立即验证数据库连通性，避免在请求时才暴露连接问题
try:
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    print("Database connection verified successfully.")
except Exception as e:
    print(f"ERROR: Failed to connect to MySQL database: {e}")
    raise RuntimeError(f"Database connection failed: {e}")

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# 密码加密
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# OAuth2
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")


# 枚举类型
class TransactionType(str, enum.Enum):
    income = "income"
    expense = "expense"


# 数据模型
class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, index=True)
    email = Column(String(100), unique=True, index=True)
    hashed_password = Column(String(255))
    transactions = relationship("Transaction", back_populates="owner")


class Category(Base):
    __tablename__ = "categories"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(50), index=True)
    type = Column(Enum(TransactionType))
    icon = Column(String(50), nullable=True)
    color = Column(String(20), nullable=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)

    transactions = relationship("Transaction", back_populates="category")


class Transaction(Base):
    __tablename__ = "transactions"

    id = Column(Integer, primary_key=True, index=True)
    # 直接使用 Float（Python float），避免 asdecimal 转换引入的额外精度损失
    amount = Column(Float, nullable=False)
    type = Column(Enum(TransactionType))
    description = Column(String(500), index=True, nullable=True)
    # 约定：date 始终以 UTC 存储（前端发送 toUtc 后的 ISO 字符串）
    date = Column(DateTime)
    category_id = Column(Integer, ForeignKey("categories.id"))
    owner_id = Column(Integer, ForeignKey("users.id"))

    owner = relationship("User", back_populates="transactions")
    category = relationship("Category", back_populates="transactions")


# 创建数据库表(自动创建，如果表已存在则忽略)
Base.metadata.create_all(bind=engine)


# Pydantic模型
class UserBase(BaseModel):
    username: str
    email: str


class UserCreate(UserBase):
    password: str


class UserResponse(UserBase):
    id: int

    class Config:
        from_attributes = True


class CategoryBase(BaseModel):
    name: str
    type: TransactionType
    icon: Optional[str] = None
    color: Optional[str] = None


class CategoryCreate(CategoryBase):
    pass


class CategoryResponse(CategoryBase):
    id: int
    user_id: Optional[int]

    class Config:
        from_attributes = True


class TransactionBase(BaseModel):
    amount: float
    type: TransactionType
    description: Optional[str] = None
    date: datetime
    category_id: int


class TransactionCreate(TransactionBase):
    pass


class TransactionResponse(TransactionBase):
    id: int
    owner_id: int

    @field_serializer("date")
    def serialize_date(self, dt: datetime) -> str:
        """强制以 UTC ISO 字符串返回（带 Z 后缀）。
        数据库 DateTime 列不存时区信息，但前端约定发送的就是 UTC，
        因此读取出的 naive datetime 等价于 UTC，给它附上 tzinfo 即可。"""
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")

    class Config:
        from_attributes = True


class Token(BaseModel):
    access_token: str
    token_type: str


class TokenData(BaseModel):
    username: Optional[str] = None


# 数据库依赖
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def month_end(year: int, month: int) -> datetime:
    """返回指定年月最后一天的 23:59:59.999999，避免 datetime(year, 13, 1) 越界。"""
    last_day = calendar.monthrange(year, month)[1]
    return datetime(year, month, last_day, 23, 59, 59, 999999)


def subtract_months(dt: datetime, months: int) -> datetime:
    """将日期减去指定月数，自动处理月末边界（如 3月31日 -> 2月28日）。"""
    month = dt.month - months
    year = dt.year
    while month <= 0:
        month += 12
        year -= 1
    try:
        return dt.replace(year=year, month=month)
    except ValueError:
        # 目标月份没有该日期（如 3月31日 -> 2月），取该月最后一天
        last_day = calendar.monthrange(year, month)[1]
        return dt.replace(year=year, month=month, day=last_day)


def to_utc_naive(dt: datetime) -> datetime:
    """统一转换为 UTC naive datetime 用于 MySQL DateTime 列存储。

    - 若已带时区：转换到 UTC 后去掉 tzinfo。
    - 若是 naive：假定调用方已传入 UTC，直接返回。
    """
    if dt.tzinfo is not None:
        return dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt


def utc_now() -> datetime:
    """返回当前 UTC naive datetime（与数据库列匹配）。"""
    return datetime.now(timezone.utc).replace(tzinfo=None)


# 工具函数
def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password):
    return pwd_context.hash(password)


def get_user(db: Session, username: str):
    return db.query(User).filter(User.username == username).first()


def get_user_by_email(db: Session, email: str):
    return db.query(User).filter(User.email == email).first()


def create_user(db: Session, user: UserCreate):
    db_user = User(
        username=user.username,
        email=user.email,
        hashed_password=get_password_hash(user.password)
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)

    # 创建默认分类
    default_categories = [
        # 收入分类
        {"name": "工资", "type": "income", "icon": "fa-money", "color": "green"},
        {"name": "兼职", "type": "income", "icon": "fa-briefcase", "color": "teal"},
        {"name": "投资", "type": "income", "icon": "fa-line-chart", "color": "emerald"},
        {"name": "礼金", "type": "income", "icon": "fa-gift", "color": "lime"},
        {"name": "其他", "type": "income", "icon": "fa-ellipsis-h", "color": "cyan"},

        # 支出分类
        {"name": "餐饮", "type": "expense", "icon": "fa-cutlery", "color": "blue"},
        {"name": "交通", "type": "expense", "icon": "fa-car", "color": "green"},
        {"name": "购物", "type": "expense", "icon": "fa-shopping-bag", "color": "yellow"},
        {"name": "住房", "type": "expense", "icon": "fa-home", "color": "purple"},
        {"name": "娱乐", "type": "expense", "icon": "fa-film", "color": "red"},
        {"name": "医疗", "type": "expense", "icon": "fa-medkit", "color": "indigo"},
        {"name": "教育", "type": "expense", "icon": "fa-book", "color": "pink"},
        {"name": "其他", "type": "expense", "icon": "fa-ellipsis-h", "color": "gray"},
    ]

    for cat in default_categories:
        db_category = Category(
            name=cat["name"],
            type=cat["type"],
            icon=cat["icon"],
            color=cat["color"],
            user_id=db_user.id
        )
        db.add(db_category)

    db.commit()
    return db_user


def authenticate_user(db: Session, username: str, password: str):
    user = get_user(db, username)
    if not user:
        return False
    if not verify_password(password, user.hashed_password):
        return False
    return user


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


async def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="无法验证凭据",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
        token_data = TokenData(username=username)
    except JWTError:
        raise credentials_exception
    user = get_user(db, username=token_data.username)
    if user is None:
        raise credentials_exception
    return user


# 创建FastAPI应用
app = FastAPI(title="PennyTrack API", description="PennyTrack 后端 API 服务")

# 配置CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # TODO: 生产环境中必须指定具体的前端域名，禁止使用通配符
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


# API端点
@app.post("/token", response_model=Token)
async def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = authenticate_user(db, form_data.username, form_data.password)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="用户名或密码不正确",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user.username}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}


@app.post("/users/", response_model=UserResponse)
def create_new_user(user: UserCreate, db: Session = Depends(get_db)):
    # 输入校验
    if not user.username or len(user.username) < 3 or len(user.username) > 50:
        raise HTTPException(status_code=400, detail="用户名长度应为3-50个字符")
    if not re.match(r"^[a-zA-Z0-9_]+$", user.username):
        raise HTTPException(status_code=400, detail="用户名只能包含字母、数字和下划线")
    if not user.email or "@" not in user.email:
        raise HTTPException(status_code=400, detail="请输入有效的邮箱地址")
    if not user.password or len(user.password) < 6:
        raise HTTPException(status_code=400, detail="密码长度至少为6位")

    db_user = get_user(db, username=user.username)
    if db_user:
        raise HTTPException(status_code=400, detail="用户名已被注册")

    db_email = get_user_by_email(db, email=user.email)
    if db_email:
        raise HTTPException(status_code=400, detail="邮箱已被注册")

    return create_user(db=db, user=user)


@app.get("/users/me/", response_model=UserResponse)
async def read_users_me(current_user: User = Depends(get_current_user)):
    return current_user


# 分类相关API
@app.get("/categories/", response_model=List[CategoryResponse])
def read_categories(
        type: Optional[TransactionType] = None,
        db: Session = Depends(get_db),
        current_user: User = Depends(get_current_user)
):
    """获取当前用户的所有分类，可按类型筛选"""
    # 每个用户都有自己的默认分类副本，因此只需匹配当前用户
    query = db.query(Category).filter(Category.user_id == current_user.id)
    if type:
        query = query.filter(Category.type == type)
    return query.all()


@app.post("/categories/", response_model=CategoryResponse)
def create_category(
        category: CategoryCreate,
        db: Session = Depends(get_db),
        current_user: User = Depends(get_current_user)
):
    """创建新的分类"""
    db_category = Category(
        **category.model_dump(),
        user_id=current_user.id
    )
    db.add(db_category)
    db.commit()
    db.refresh(db_category)
    return db_category


# 交易记录相关API
@app.get("/transactions/", response_model=List[TransactionResponse])
def read_transactions(
        skip: int = 0,
        limit: int = 100,
        type: Optional[TransactionType] = None,
        category_id: Optional[int] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        db: Session = Depends(get_db),
        current_user: User = Depends(get_current_user)
):
    """获取交易记录，支持多条件筛选"""
    query = db.query(Transaction).filter(Transaction.owner_id == current_user.id)

    if type:
        query = query.filter(Transaction.type == type)
    if category_id:
        query = query.filter(Transaction.category_id == category_id)
    # 数据库 date 列存储的是 UTC naive，前端可能传入带时区的 ISO，统一转换
    if start_date:
        query = query.filter(Transaction.date >= to_utc_naive(start_date))
    if end_date:
        query = query.filter(Transaction.date <= to_utc_naive(end_date))

    return query.offset(skip).limit(limit).all()


@app.post("/transactions/", response_model=TransactionResponse)
def create_transaction(
        transaction: TransactionCreate,
        db: Session = Depends(get_db),
        current_user: User = Depends(get_current_user)
):
    """创建新的交易记录"""
    # 验证分类是否属于当前用户（每个用户拥有自己的默认分类副本）
    category = db.query(Category).filter(
        Category.id == transaction.category_id,
        Category.user_id == current_user.id,
    ).first()

    if not category:
        raise HTTPException(status_code=400, detail="无效的分类")

    payload = transaction.model_dump()
    payload["date"] = to_utc_naive(payload["date"])

    db_transaction = Transaction(
        **payload,
        owner_id=current_user.id,
    )
    db.add(db_transaction)
    db.commit()
    db.refresh(db_transaction)
    return db_transaction


@app.get("/transactions/{transaction_id}", response_model=TransactionResponse)
def read_transaction(
        transaction_id: int,
        db: Session = Depends(get_db),
        current_user: User = Depends(get_current_user)
):
    """获取单个交易记录详情"""
    transaction = db.query(Transaction).filter(
        Transaction.id == transaction_id,
        Transaction.owner_id == current_user.id
    ).first()

    if transaction is None:
        raise HTTPException(status_code=404, detail="交易记录不存在")

    return transaction


@app.put("/transactions/{transaction_id}", response_model=TransactionResponse)
def update_transaction(
        transaction_id: int,
        transaction: TransactionCreate,
        db: Session = Depends(get_db),
        current_user: User = Depends(get_current_user)
):
    """更新交易记录"""
    # 验证交易是否存在
    db_transaction = db.query(Transaction).filter(
        Transaction.id == transaction_id,
        Transaction.owner_id == current_user.id
    ).first()

    if db_transaction is None:
        raise HTTPException(status_code=404, detail="交易记录不存在")

    # 验证分类是否属于当前用户
    category = db.query(Category).filter(
        Category.id == transaction.category_id,
        Category.user_id == current_user.id,
    ).first()

    if not category:
        raise HTTPException(status_code=400, detail="无效的分类")

    # 更新交易（统一把日期转换为 UTC naive 存储）
    payload = transaction.model_dump()
    payload["date"] = to_utc_naive(payload["date"])
    for key, value in payload.items():
        setattr(db_transaction, key, value)

    db.commit()
    db.refresh(db_transaction)
    return db_transaction


@app.delete("/transactions/{transaction_id}")
def delete_transaction(
        transaction_id: int,
        db: Session = Depends(get_db),
        current_user: User = Depends(get_current_user)
):
    """删除交易记录"""
    transaction = db.query(Transaction).filter(
        Transaction.id == transaction_id,
        Transaction.owner_id == current_user.id
    ).first()

    if transaction is None:
        raise HTTPException(status_code=404, detail="交易记录不存在")

    db.delete(transaction)
    db.commit()
    return {"detail": "交易记录已成功删除"}


# 统计分析相关API
@app.get("/summary/")
def get_financial_summary(
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        db: Session = Depends(get_db),
        current_user: User = Depends(get_current_user)
) -> Dict[str, Any]:
    """获取财务摘要信息，包括收入、支出、结余及与上期对比"""
    # 如果没有指定日期范围，默认使用本月（UTC 基准与数据库列对齐）
    if not start_date or not end_date:
        today = utc_now()
        start_date = datetime(today.year, today.month, 1)
        end_date = month_end(today.year, today.month)
    else:
        start_date = to_utc_naive(start_date)
        end_date = to_utc_naive(end_date)

    # 获取当前周期数据
    transactions = db.query(Transaction).filter(
        Transaction.owner_id == current_user.id,
        Transaction.date >= start_date,
        Transaction.date <= end_date
    ).all()

    # 计算上月同期（准确减去一个月，自动处理月末边界）
    last_month_start = subtract_months(start_date, 1)
    last_month_end = subtract_months(end_date, 1)

    # 获取上月数据
    last_month_transactions = db.query(Transaction).filter(
        Transaction.owner_id == current_user.id,
        Transaction.date >= last_month_start,
        Transaction.date <= last_month_end
    ).all()

    # 计算当前周期收支
    current_income = sum(t.amount for t in transactions if t.type == TransactionType.income)
    current_expense = sum(t.amount for t in transactions if t.type == TransactionType.expense)
    current_balance = current_income - current_expense

    # 计算上月收支
    last_income = sum(t.amount for t in last_month_transactions if t.type == TransactionType.income)
    last_expense = sum(t.amount for t in last_month_transactions if t.type == TransactionType.expense)
    last_balance = last_income - last_expense

    # 计算增长率
    income_change = ((current_income - last_income) / last_income * 100) if last_income > 0 else 0
    expense_change = ((current_expense - last_expense) / last_expense * 100) if last_expense > 0 else 0
    balance_change = ((current_balance - last_balance) / last_balance * 100) if last_balance > 0 else 0

    return {
        "income": round(current_income, 2),
        "expense": round(current_expense, 2),
        "balance": round(current_balance, 2),
        "income_change": round(income_change, 1),
        "expense_change": round(expense_change, 1),
        "balance_change": round(balance_change, 1),
        "period": {
            "start": start_date,
            "end": end_date
        }
    }


@app.get("/category-stats/")
def get_category_stats(
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        db: Session = Depends(get_db),
        current_user: User = Depends(get_current_user)
) -> Dict[str, Any]:
    """获取支出分类统计数据"""
    # 如果没有指定日期范围，默认使用本月（UTC 基准与数据库列对齐）
    if not start_date or not end_date:
        today = utc_now()
        start_date = datetime(today.year, today.month, 1)
        end_date = month_end(today.year, today.month)
    else:
        start_date = to_utc_naive(start_date)
        end_date = to_utc_naive(end_date)

    # 获取该时间段内的支出交易
    transactions = db.query(Transaction).filter(
        Transaction.owner_id == current_user.id,
        Transaction.type == TransactionType.expense,
        Transaction.date >= start_date,
        Transaction.date <= end_date
    ).all()

    # 按分类统计
    category_totals = {}
    for t in transactions:
        if t.category_id not in category_totals:
            category_totals[t.category_id] = 0
        category_totals[t.category_id] += t.amount

    # 获取分类名称
    category_ids = list(category_totals.keys())
    categories = db.query(Category).filter(Category.id.in_(category_ids)).all()
    category_map = {c.id: c for c in categories}

    # 计算总支出
    total_expense = sum(category_totals.values())

    # 准备结果
    labels = []
    values = []
    colors = []
    amounts = []

    for cat_id, total in category_totals.items():
        category = category_map.get(cat_id)
        if category:
            labels.append(category.name)
            values.append(round((total / total_expense) * 100, 1) if total_expense > 0 else 0)  # 百分比
            colors.append(category.color)
            amounts.append(round(total, 2))

    return {
        "labels": labels,
        "values": values,
        "colors": colors,
        "amounts": amounts,
        "period": {
            "start": start_date,
            "end": end_date
        }
    }


@app.get("/trends/")
def get_trends(
        period: str = "month",  # day, month, quarter, year
        year: Optional[int] = None,
        month: Optional[int] = None,
        db: Session = Depends(get_db),
        current_user: User = Depends(get_current_user)
) -> Dict[str, Any]:
    """获取收支趋势数据"""
    valid_periods = {"day", "month", "quarter", "year"}
    if period not in valid_periods:
        raise HTTPException(status_code=400, detail=f"无效的 period 参数，可选值: {', '.join(valid_periods)}")

    today = utc_now()

    # 根据周期确定时间范围
    if period == "day":
        # 按天聚合：必须指定年月，默认当月
        if year is None or month is None:
            year = today.year
            month = today.month
        _, days_in_month = calendar.monthrange(year, month)
        labels = [f"{d}日" for d in range(1, days_in_month + 1)]
        start_dates = [datetime(year, month, d) for d in range(1, days_in_month + 1)]
        end_dates = [datetime(year, month, d, 23, 59, 59, 999999) for d in range(1, days_in_month + 1)]

    elif period == "month":
        # 如果指定了年月，只查询该月
        if year is not None and month is not None:
            labels = [f"{year}年{month}月"]
            start_dates = [datetime(year, month, 1)]
            end_dates = [month_end(year, month)]
        else:
            # 过去6个月（默认行为，兼容旧版）
            labels = []
            start_dates = []
            end_dates = []

            for i in range(6):
                m = today.month - i
                y = today.year

                if m <= 0:
                    m += 12
                    y -= 1

                labels.append(f"{y}年{m}月")
                start_dates.append(datetime(y, m, 1))
                end_dates.append(month_end(y, m))

    elif period == "quarter":
        # 过去4个季度
        labels = []
        start_dates = []
        end_dates = []

        for i in range(4):
            current_quarter = (today.month - 1) // 3 - i
            year = today.year

            while current_quarter < 0:
                current_quarter += 4
                year -= 1

            start_month = current_quarter * 3 + 1
            end_month = start_month + 2

            labels.append(f"{year}年Q{current_quarter + 1}")
            start_dates.append(datetime(year, start_month, 1))
            # 使用 month_end 避免 end_month + 1 = 13 时越界
            end_dates.append(month_end(year, end_month))

    else:  # year
        # 过去12个月
        labels = []
        start_dates = []
        end_dates = []

        for i in range(12):
            month = today.month - i
            year = today.year

            if month <= 0:
                month += 12
                year -= 1

            labels.append(f"{year}年{month}月")
            start_dates.append(datetime(year, month, 1))
            end_dates.append(month_end(year, month))

    # 按时间范围查询数据
    income_data = []
    expense_data = []

    for i in range(len(start_dates)):
        start = start_dates[i]
        end = end_dates[i]

        # 收入
        income = db.query(Transaction).filter(
            Transaction.owner_id == current_user.id,
            Transaction.type == TransactionType.income,
            Transaction.date >= start,
            Transaction.date <= end
        ).with_entities(Transaction.amount).all()

        total_income = sum(t[0] for t in income)
        income_data.append(round(total_income, 2))

        # 支出
        expense = db.query(Transaction).filter(
            Transaction.owner_id == current_user.id,
            Transaction.type == TransactionType.expense,
            Transaction.date >= start,
            Transaction.date <= end
        ).with_entities(Transaction.amount).all()

        total_expense = sum(t[0] for t in expense)
        expense_data.append(round(total_expense, 2))

    return {
        "labels": labels,
        "income": income_data,
        "expense": expense_data
    }


@app.get("/")
async def test_db(db: Session = Depends(get_db)):
    try:
        # 执行原生 SQL 查询数据库版本
        result = db.execute(text("SELECT VERSION()")).fetchone()
        db_version = result[0] if result else "Unknown"
        return {"status": "successfully!", "message": "Database connection is working!", "db_version": db_version}
    except Exception as e:
        return {"status": "error", "message": f"Database connection failed: {str(e)}"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=5300)
