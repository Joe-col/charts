# Astria 本地开发环境清单（阶段一验证版）

**验证时间：** 2025-11-01  
**环境类型：** Windows + WSL2 + Docker Desktop + kind + astria-charts  

## 1. 基础环境

| 项目 | 说明 |
|------|------|
| **OS** | Windows 11 + WSL2 (Ubuntu 22.04) |
| **容器引擎** | Docker Desktop v24（WSL 后端） |
| **Kubernetes 发行版** | kind v0.23 + k8s v1.30 |
| **Helm** | v3.x |
| **命令行工具** | kubectl 1.30 / just / make / jq |
| **CNI 插件** | **kindnet (default)** |
| **Git commit (astria-charts)** | f0aac86c1a49b3a6b8a353d7bee118e40ffe8a01 |

---

## 2. 集群与命名空间

| 项目 | 值 |
|------|----|
| **kind cluster name** | `astria` |
| **kubectl context** | `kind-astria` |
| **Astria namespace** | `astria-dev-cluster` |
| **额外 namespace** | `astria-sequencer-single` (空，备用 demo) |

---

## 3. 数据库（PostgreSQL）

| 参数 | 值 |
|------|----|
| 容器名 | `astria-pg` |
| 镜像 | postgres:15 |
| 地址 | 127.0.0.1:5432 |
| 用户 / 密码 | astria / astria |
| 数据库 | astria |
| 备注 | 供 feature service 与 audit 模块使用 |

---

## 4. Astria 核心服务（命名空间 `astria-dev-cluster`）

| 组件 | Service 名 | 类型 | 端口 | 功能 |
|------|-------------|------|------|------|
| **Sequencer RPC** | `node0-sequencer-rpc-service` | ClusterIP | **26657** | 区块链 RPC 接口 |
| **Sequencer gRPC** | `node0-sequencer-grpc-service` | ClusterIP | **8080** | AI/调度 gRPC 接口 |
| **Sequencer P2P** | `node0-sequencer-p2p-service` | NodePort | 26656 : 30907 | 节点间 P2P 通信 |
| **Faucet** | `astria-evm-faucet-service` | ClusterIP | **8080** | 发放测试 token |
| **Composer** | `composer` | Deployment | — | 批处理/协调组件 |
| **Celestia-local** | `celestia-local-0` | StatefulSet | — | 数据可用性层 |

---

## 5. Ingress 与 Port-Forward

| 项目 | 值 |
|------|----|
| Ingress Namespace | ingress-nginx |
| Ingress Service | ingress-nginx-controller |
| NodePort (外部端口) | 30238 |
| 本地转发 | **127.0.0.1:8080 → ingress-nginx:80** |
| 监听验证 | `ss -tnlp | grep 8080` → kubectl port-forward 进程存在 |
| 日志 | `/root/astria-charts/logs/portforward.log` |

---

## 6. 外部访问方式（开发机视角）

| 服务 | 访问地址 |
|------|-----------|
| **Sequencer Health** | http://rpc.sequencer.127.0.0.1.nip.io:8080/health |
| **Executor** | http://executor.astria.127.0.0.1.nip.io:8080 |
| **Faucet** | http://faucet.astria.127.0.0.1.nip.io:8080 |

> ⚠ 8080 为 port-forward 出口。  
> 内部 collector 应使用 ClusterIP 服务 (`node0-sequencer-rpc-service:26657`) 而非 8080。

---

## 7. 内部服务访问（Pod → Pod）

| 名称 | 地址 | 说明 |
|------|------|------|
| Sequencer RPC | `node0-sequencer-rpc-service:26657` | JSON-RPC 接口 |
| Sequencer gRPC | `node0-sequencer-grpc-service:8080` | 调度通信 |
| Faucet | `astria-evm-faucet-service:8080` | 测试 token 发放 |
| PostgreSQL | `astria-pg.default.svc.cluster.local:5432` | 数据存储 |

---

## 8. 当前 Pods 概览
kubectl get pods -n astria-dev-cluster
NAME READY STATUS AGE
sequencer-0 3/3 Running 2h
composer-xxxx 1/1 Running 2h
celestia-local-0 2/2 Running 2h
evm-faucet-xxxx 1/1 Running 2h

## 9. 日志与监控

| 模块 | 日志位置 | 说明 |
|------|-----------|------|
| ingress-nginx | `/root/astria-charts/logs/portforward.log` | 本地转发 |
| sequencer | `kubectl logs -n astria-dev-cluster sequencer-0` | 区块打包 |
| postgres | `docker logs astria-pg` | 数据库活动 |
| composer | `kubectl logs -n astria-dev-cluster -l app=composer` | 批处理 调度 |

---


## 10. 时间与时区

- 所有采集、存储使用 **UTC** 时间。  
- `kubectl get events --sort-by=.metadata.creationTimestamp` 验证同步。

---


## 11. 已知问题

| 模块 | 状态 | 说明 |
|------|------|------|
| blockscout-postgres | ImagePullBackOff | 外部 registry 未授权，暂不影响核心组件 |
| astria-sequencer-single ns | 空 | 预留 demo 环境 |

---


## 12. 后续阶段依赖关系

| 阶段 | 主要输入 | 当前可用性 |
|------|-----------|------------|
| **阶段 2 – 交易生成 / 流量注入** | Faucet 内部 URL (`astria-evm-faucet-service:8080`)<br>Executor RPC (SVC 待确认) | Faucet ✅ 可用；Executor ❌ 未部署 |
| **阶段 3 – 数据采集** | Sequencer RPC (`node0-sequencer-rpc-service:26657`) | ✅ 可用 |
| **阶段 4 – 特征服务** | PostgreSQL (127.0.0.1:5432 / astria) | ✅ 可用 |
| **阶段 5 – 调度控制器** | Sequencer gRPC (`node0-sequencer-grpc-service:8080`) | ✅ 可用 |

---


## 13. 环境验证命令汇总
kind get clusters
kubectl get ns
kubectl get svc -n astria-dev-cluster
ss -tnlp | grep 8080
curl http://rpc.sequencer.127.0.0.1.nip.io:8080/health

## 14. 后续扩展指引

- **阶段 2 目标**：编写交易生成器 (traffic generator)，调用 Faucet 发 token → Executor 发送交易；  
  输出：交易速率 TPS 与 延迟 日志。  
- **阶段 3 目标**：采集 Sequencer RPC 数据（`26657`）与 交易批次 元信息，存入 PostgreSQL。  
- **阶段 4 目标**：启动 feature-service 容器，从数据库生成特征。  
- **阶段 5 目标**：部署 AI 调度控制器，通过 Sequencer gRPC 进行排序实验。  

---