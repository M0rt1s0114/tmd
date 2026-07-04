# syntax=docker/dockerfile:1

########################################
# 构建阶段
########################################
FROM golang:1.22-bookworm AS builder

# github.com/mattn/go-sqlite3 依赖 cgo，需要 gcc 工具链
ENV CGO_ENABLED=1 \
    GOOS=linux
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# 先拷贝 go.mod/go.sum 独立下载依赖，充分利用构建缓存
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go build -trimpath -ldflags="-s -w" -o /out/tmd .

########################################
# 运行阶段
########################################
FROM debian:bookworm-slim

# 可在 build 时通过 --build-arg 调整，方便和宿主机挂载目录的属主对齐
ARG PUID=1000
ARG PGID=1000

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -g "${PGID}" tmd \
    && useradd -m -u "${PUID}" -g "${PGID}" -d /home/tmd -s /usr/sbin/nologin tmd

COPY --from=builder /out/tmd /usr/local/bin/tmd

# 程序通过 $HOME 定位 ~/.tmd2 (配置/数据库/日志)
ENV HOME=/home/tmd
WORKDIR /home/tmd

# .tmd2: 配置、sqlite数据库、日志、失败推文dump
# downloads: 建议在 --conf 时把 storage path 填成 /downloads，媒体文件都落在这个卷里
RUN mkdir -p /home/tmd/.tmd2 /downloads \
    && chown -R tmd:tmd /home/tmd /downloads

USER tmd
VOLUME ["/home/tmd/.tmd2", "/downloads"]

ENTRYPOINT ["tmd"]
CMD ["--help"]
