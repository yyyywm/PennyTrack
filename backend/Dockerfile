# ===== Stage 1: builder =====
FROM python:3.11-slim AS builder

# 使用国内 Debian 镜像源，大幅加速 apt 下载
RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources \
    && apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# 使用独立 venv 便于整个目录拷贝到最终镜像
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# 使用国内 PyPI 镜像源，大幅加速 pip 下载
ENV PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
ENV PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt


# ===== Stage 2: runtime =====
FROM python:3.11-slim

# 拷贝构建好的虚拟环境，最终镜像不再包含 build-essential
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /app

# 复制应用代码
COPY main.py .

# 创建非 root 用户并切换（安全最佳实践）
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# 暴露端口（通过环境变量 PORT 控制，默认 8000）
ENV PORT=8000
EXPOSE ${PORT}

# 使用 sh -c + exec 形式：
#   - sh -c 让 ${PORT} 在运行时展开
#   - exec 让 uvicorn 取代 sh 成为 PID 1，docker stop 发出的 SIGTERM 才能被正确接收并优雅停机
CMD ["sh", "-c", "exec uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
