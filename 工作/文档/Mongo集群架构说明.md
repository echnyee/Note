# Mongo 集群整体架构说明

## 1. 整体架构概览

MongoDB 在需要大规模水平扩展时，通常使用 **Sharded Cluster（分片集群）**。
一个典型的 Mongo 分片集群，主要由以下三类角色组成：

1. **mongos**
   - 路由节点
   - 客户端通常连接它，而不是直接连接各个 shard
   - 根据分片元数据，把请求转发到正确的分片

2. **Config Server**
   - 配置服务器
   - 保存整个集群的元数据，例如：
     - 哪些 collection 开启了分片
     - chunk 如何划分
     - chunk 当前位于哪个 shard
   - 不保存业务数据，只保存集群路由和分布信息

3. **Shard**
   - 真正存储业务数据的节点
   - 每个 shard 只保存全量数据中的一部分
   - 多个 shard 组合起来承载整个数据库的数据

---

## 2. 架构示意图

```text
                ┌───────────────┐
                │   Client/App  │
                └───────┬───────┘
                        │
          ┌─────────────┼─────────────┐
          │             │             │
   ┌──────▼──────┐ ┌────▼─────┐ ┌────▼─────┐
   │   mongos    │ │  mongos  │ │  mongos  │
   │  路由节点    │ │ 路由节点  │ │ 路由节点  │
   └──────┬──────┘ └────┬─────┘ └────┬─────┘
          │             │             │
          └─────────────┼─────────────┘
                        │
                ┌───────▼────────┐
                │ Config Server  │
                │ Replica Set    │
                └───────┬────────┘
                        │
      ┌─────────────────┼─────────────────┐
      │                 │                 │
┌─────▼─────┐     ┌─────▼─────┐     ┌─────▼─────┐
│ Shard 1   │     │ Shard 2   │     │ Shard 3   │
│ ReplicaSet│     │ ReplicaSet│     │ ReplicaSet│
└───────────┘     └───────────┘     └───────────┘
```

---

## 3. mongos 是什么，是否单点

### 3.1 mongos 的职责

`mongos` 是 Mongo 分片集群中的**路由节点**，主要负责：

- 接收客户端请求
- 查询或缓存集群元数据
- 根据分片键和元数据，把请求路由到正确的 shard
- 在需要时聚合多个 shard 的结果后返回给客户端

它本身**不保存业务数据**。

### 3.2 mongos 是单点吗

**不应该设计成单点。生产环境通常会部署多个 `mongos`。**

原因如下：

- `mongos` 本身是无状态或近似无状态的
- 它不是主从结构
- 多个 `mongos` 之间没有主备关系
- 任意一个挂掉，其他 `mongos` 仍然可以继续提供服务

因此，`mongos` 通常会这样部署：

- 多实例部署在不同机器上
- 应用连接多个 `mongos`
- 或者前面挂负载均衡器

### 3.3 一个 mongos 挂掉会怎样

- 连接到这个 `mongos` 的客户端会失败或重连
- 其他 `mongos` 不受影响
- 集群数据不会丢失，因为数据并不存放在 `mongos` 上

所以可以理解为：

> 单个 `mongos` 实例可能故障，但整个路由层不应是单点。

---

## 4. 分片（Shard）内部是什么结构

在生产环境中，一个 `shard` 通常**不是单机实例**，而是一个 **Replica Set（副本集）**。

也就是说：

- **Sharding（分片）** 负责横向切分数据
- **Replica Set（副本集）** 负责高可用和冗余备份

一个 shard 常见结构如下：

```text
Shard1 = Replica Set
  ├─ Primary
  ├─ Secondary
  └─ Secondary
```

多个 shard 可能是：

```text
Shard1 = Replica Set
Shard2 = Replica Set
Shard3 = Replica Set
```

---

## 5. shard 里会有 primary / secondary 吗

**会。**

但这里的 `Primary / Secondary`，是指**每个 shard 自己内部副本集的角色**，不是整个分片集群全局只有一个主。

例如：

```text
Shard1（副本集）
  - Primary
  - Secondary
  - Secondary

Shard2（副本集）
  - Primary
  - Secondary
  - Secondary
```

### 写请求流程

通常写请求是这样走的：

1. 客户端把请求发给 `mongos`
2. `mongos` 根据分片键定位目标 shard
3. 请求被转发到目标 shard 的 `Primary`
4. `Primary` 写入成功后，再复制到 `Secondary`

### 读请求流程

读请求取决于读偏好（read preference）：

- 默认通常从 `Primary` 读
- 也可以配置允许从 `Secondary` 读
- `mongos` 会根据读偏好把请求发给合适的副本节点

---

## 6. 有了分片之后，还会有 Replica Set 吗

**会，而且通常是必须有的。**

这里要区分两个维度：

### 6.1 Sharding 解决什么问题

- 数据量太大，单机放不下
- 单机读写吞吐不够
- 需要横向扩容

### 6.2 Replica Set 解决什么问题

- 节点故障时高可用
- 数据冗余
- 自动主从切换
- 提高可靠性

所以二者不是替代关系，而是**组合关系**：

> 分片解决扩展问题，副本集解决高可用问题。

---

## 7. 常见的三种部署思路

### 7.1 只有副本集

```text
Replica Set
  - Primary
  - Secondary
  - Secondary
```

特点：

- 有高可用
- 每个节点都保存全量数据
- 扩展能力有限

### 7.2 只有分片，不做副本

```text
Shard1（单机）
Shard2（单机）
Shard3（单机）
```

特点：

- 有横向扩展
- 但没有高可用
- 任一 shard 故障时，该 shard 上的数据不可用

这种结构一般不适合生产。

### 7.3 分片 + 副本集

```text
Shard1 = Replica Set
Shard2 = Replica Set
Shard3 = Replica Set
```

特点：

- 可以横向扩展
- 又有高可用
- 这是最常见的生产架构

---

## 8. Config Server 本身也通常是副本集

这一点很重要。

`Config Server` 一般也不是单机，而是一个专用的 **Replica Set**，例如：

```text
ConfigRS
  - Primary
  - Secondary
  - Secondary
```

它保存的是集群级元数据，例如：

- 哪些库 / 表启用了分片
- chunk 的划分情况
- chunk 分布在哪些 shard 上
- balancer 所需的元数据

因此，Mongo 分片集群中通常会存在两类副本集：

1. **Config Server Replica Set**
2. **各个 Shard 的 Replica Set**

---

## 9. 整体关系总结

### mongos

- 是路由层
- 不存业务数据
- 通常部署多个
- 不是副本集
- 不应成为单点

### Config Server

- 存储集群元数据
- 通常自身也是副本集

### Shard

- 存储业务数据
- 每个 shard 通常是一个副本集

### Replica Set

- 负责高可用、数据冗余、主从切换
- 出现在 Config Server 和各个 Shard 内部

---

## 10. 一句总结

Mongo 生产集群最典型的形态是：

> **多个 mongos 路由节点 + 一个 Config Server 副本集 + 多个由 Replica Set 构成的 Shard**

也就是说：

- `mongos` 负责路由
- `Config Server` 负责保存元数据
- `Shard` 负责存业务数据
- `Replica Set` 负责高可用

---

## 11. 一个典型生产拓扑示例

```text
3 x mongos

3 x Config Server（组成一个副本集）

Shard1 = 3 节点副本集
Shard2 = 3 节点副本集
Shard3 = 3 节点副本集
```

这类结构兼顾了：

- 水平扩展能力
- 故障转移能力
- 数据可靠性
- 生产可用性

---

## 12. 直观类比

如果用更直白的方式理解：

- `mongos`：像网关 / 路由器
- `Config Server`：像路由表和拓扑配置中心
- `Shard`：像真正存储数据的数据库分区
- `Replica Set`：像每个分区内部的主备集群

所以整个 Mongo 分片集群，本质上就是：

> **多个路由节点 + 一个配置副本集 + 多个分片副本集**

