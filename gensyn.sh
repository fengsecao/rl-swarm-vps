#!/bin/bash
set -euo pipefail

log_file="./deploy_rl_swarm_vps.log"
max_retries=10
retry_count=0

# 清理 Docker 环境
docker_cleanup() {
    info "开始清理 Docker 环境..."
    
    # 停止所有运行中的容器
    info "停止所有容器..."
    docker stop $(docker ps -aq) 2>/dev/null || true
    
    # 删除所有容器
    info "删除所有容器..."
    docker rm $(docker ps -aq) 2>/dev/null || true
    
    # 删除所有镜像
    info "删除所有镜像..."
    docker rmi $(docker images -aq) 2>/dev/null || true
    
    # 清理未使用的数据卷
    info "清理未使用的数据卷..."
    docker volume prune -f 2>/dev/null || true
    
    # 清理未使用的网络
    info "清理未使用的网络..."
    docker network prune -f 2>/dev/null || true
    
    # 清理构建缓存
    info "清理构建缓存..."
    docker builder prune -af 2>/dev/null || true
    
    info "Docker 环境清理完成！"
}

info() {
    echo -e "[$(date +"%Y-%m-%d %T")] [INFO] $*" | tee -a "$log_file"
}

error() {
    echo -e "[$(date +"%Y-%m-%d %T")] [ERROR] $*" >&2 | tee -a "$log_file"
    if [ $retry_count -lt $max_retries ]; then
        retry_count=$((retry_count+1))
        info "自动重试 ($retry_count/$max_retries)..."
        exec "$0" "$@"
    else
        echo -e "[$(date +"%Y-%m-%d %T")] [ERROR] 达到最大重试次数 ($max_retries 次)，请手动重启 Docker 并检查环境" >&2 | tee -a "$log_file"
        exit 1
    fi
}

# 检查 Docker 是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker 未安装，请先安装 Docker (https://www.docker.com)"
    fi
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose 未安装，请先安装 Docker Compose"
    fi
}

# 打开 Docker
start_docker() {
    info "正在启动 Docker..."
    if ! open -a Docker; then
        error "无法启动 Docker 应用，请检查 Docker 是否安装或手动启动"
    fi
    # 等待 Docker 启动
    info "等待 Docker 启动完成..."
    sleep 10
    # 检查 Docker 是否运行
    if ! docker info &> /dev/null; then
        error "Docker 未正常运行，请检查 Docker 状态"
    fi
}

# 运行 Docker Compose 容器
run_docker_compose() {
    local attempt=1
    local max_attempts=$max_retries
    while [ $attempt -le $max_attempts ]; do
        info "尝试运行容器 swarm-cpu (第 $attempt 次)..."
        if docker-compose up swarm-cpu; then
            info "容器 swarm-cpu 运行成功"
            return 0
        else
            info "Docker 构建失败，重试中..."
            sleep 2
            ((attempt++))
        fi
    done
    error "Docker 构建超过最大重试次数 ($max_attempts 次)"
}

# 主逻辑
main() {
    # 检查 Docker 环境
    check_docker

    # 启动 Docker
    start_docker
    
    # 询问是否清除 Docker 环境
    echo -e "\n[提问] 是否要清理 Docker 环境？这将删除所有容器、镜像、卷和缓存。\n"
    echo -e "请在 5 秒内输入 'y' 确认清理，否则将继续使用现有环境...\c"
    
    # 设置 5 秒超时的读取
    read -t 5 clean_confirm
    
    # 如果用户输入 y 或 Y，则清理环境
    if [[ "$clean_confirm" == "y" ]] || [[ "$clean_confirm" == "Y" ]]; then
        docker_cleanup
    else
        echo -e "\n[INFO] 继续使用现有 Docker 环境..."
    fi

    # 进入目录
    info "进入 rl-swarm-vps 目录..."
    cd ~/rl-swarm-vps || error "进入 rl-swarm-vps 目录失败"

    # 运行容器
    info "🚀 运行 swarm-cpu 容器..."
    run_docker_compose
}

# 执行主逻辑
main "$@"
