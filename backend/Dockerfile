# 使用官方 Python 轻量镜像
FROM python:3.11-slim

# 设置工作目录
WORKDIR /app

# 先复制依赖文件，利用 Docker 缓存层
COPY requirements.txt .

# 安装依赖
RUN pip install --no-cache-dir -r requirements.txt

# 复制应用代码
COPY main.py .

# 创建非 root 用户并切换（安全最佳实践）
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# 暴露端口（通过环境变量 PORT 控制，默认 8000）
ENV PORT=8000
EXPOSE ${PORT}

# 启动命令
CMD uvicorn main:app --host 0.0.0.0 --port ${PORT}
