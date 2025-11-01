#!/bin/bash
set -e

# =============================================
# Astria 启动脚本（WSL + kind + astria-charts）
# 适配 namespace = astria-dev-cluster
# =============================================

TARGET_CLUSTER=astria
ASTRIA_NS=astria-dev-cluster
LOG_DIR=/root/astria-charts/logs

echo "========== [1] 启动 PostgreSQL =========="

# 检查容器是否 *存在*（无论运行中还是已停止）
# 我们使用 `docker ps -a` 并精确过滤名称
if docker ps -a --filter "name=astria-pg" --format "{{.Names}}" | grep -q "astria-pg"; then
    # 容器存在，尝试启动它
    # 如果它已在运行，此命令会自动跳过
    # 如果它已停止，此命令会启动它
    echo "PostgreSQL 容器 (astria-pg) 已存在，尝试启动..."
    docker start astria-pg
else
    # 容器完全不存在，创建新的
    echo "启动 PostgreSQL 容器..."
    docker run -d \
      --name astria-pg \
      -e POSTGRES_PASSWORD=astria \
      -e POSTGRES_USER=astria \
      -e POSTGRES_DB=astria \
      -p 5432:5432 \
      postgres:15
fi

echo "========== [2] 检查 kind 集群 =========="
if ! kind get clusters | grep -q "$TARGET_CLUSTER"; then
  echo "未检测到 kind 集群，正在创建..."
  kind create cluster --name "$TARGET_CLUSTER" --config /root/kind-persistent.yaml
  cd ~/astria-charts
  just deploy astria-local
  just deploy rollup
else
  echo "kind 集群已存在。"
  # 检查 Astria 命名空间是否存在，否则补部署
  if ! kubectl get ns "$ASTRIA_NS" >/dev/null 2>&1; then
    echo "未检测到命名空间 $ASTRIA_NS ，补充部署 Astria..."
    cd ~/astria-charts
    just deploy astria-local
    just deploy rollup
  fi
fi

echo "========== [3] 节点标签 =========="
kubectl label node "$TARGET_CLUSTER"-control-plane ingress-ready=true --overwrite

echo "========== [4] 检查 ingress-nginx =========="
if kubectl get ns ingress-nginx >/dev/null 2>&1; then
  echo "ingress-nginx 已存在。"
else
  echo "部署 ingress-nginx..."
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null
  helm repo update >/dev/null
  helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace
fi

echo "等待 ingress-nginx-controller 启动中..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  -l app.kubernetes.io/component=controller \
  --timeout=180s || echo "警告：ingress 控制器未全部 ready"

echo "========== [5] 当前 Pod 状态 =========="
kubectl get pods -A

echo "========== [6] 启动端口转发 (8080→80) =========="
mkdir -p "$LOG_DIR"

# 先杀掉旧的 port-forward
if pgrep -f "port-forward -n ingress-nginx" >/dev/null; then
  echo "检测到旧的 port-forward，正在终止..."
  pkill -f "port-forward -n ingress-nginx"
fi

# 后台启动新的 port-forward
nohup kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80 \
  >"$LOG_DIR/portforward.log" 2>&1 &

sleep 2
if ss -tnlp | grep -q ":8080"; then
  echo "8080 端口监听成功。"
else
  echo "警告：8080 端口未监听，port-forward 可能失败，请查看 $LOG_DIR/portforward.log"
fi

echo "========== 启动完成 =========="
echo "访问方式1（最稳）："
echo "  kubectl port-forward -n $ASTRIA_NS svc/sequencer 8090:80"
echo "  curl http://127.0.0.1:8090/health"
echo "访问方式2（ingress 通后可用）："
echo "  http://rpc.sequencer.127.0.0.1.nip.io:8080/health"
