# 协同编辑系统完整流程

## 架构概览

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              客户端 (Browser)                           │
│  ┌─────────────┐    ┌──────────────────┐    ┌───────────────────────┐  │
│  │  CodeMirror │◄──►│  EditorClient    │◄──►│  ActionCableAdapter   │  │
│  │   (编辑器)   │    │  (ot.js 客户端)  │    │   (WebSocket 通信)     │  │
│  └─────────────┘    └──────────────────┘    └───────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │ WebSocket
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           Rails Web 进程                                │
│  ┌────────────────────────┐                                             │
│  │  RoomCollabChannel     │  ──操作入队──►  Redis Stream               │
│  │  (ActionCable Channel) │  ◄─广播结果──  ActionCable.broadcast       │
│  └────────────────────────┘                                             │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                              Redis                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌────────────┐  │
│  │ ot:ops:{shard}│  │ot:state:... │  │ot:history:..│  │ot:clients:.│  │
│  │  (操作流)     │  │ (文档状态)   │  │ (操作历史)   │  │ (客户端信息) │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  └────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │ XREAD BLOCK
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         RoomOTWorker (后台进程)                          │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  1. 从 Stream 读取操作                                            │  │
│  │  2. 获取/创建 Session (OT::Server + 文档状态)                      │  │
│  │  3. 执行 OT 变换 (transform against concurrent ops)               │  │
│  │  4. 持久化到 Redis + 写入文件系统                                  │  │
│  │  5. 广播结果给所有客户端                                           │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                          @sessions 内存缓存                              │
│                    { "room:123:main.py" => Session }                    │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 详细流程

### 1. 客户端连接与初始化

```
用户打开文件
    │
    ▼
editor_controller.js: openFile(path)
    │
    ▼
创建 ActionCable 订阅
    │ { channel: "RoomCollabChannel", room_id: X, path: "main.py" }
    ▼
RoomCollabChannel#subscribed
    │
    ├── 验证用户权限 (RoomMembership.exists?)
    ├── 注册客户端到 Redis (ot:clients:{room}:{path})
    ├── 从 Redis 获取文档状态 (RoomOTRedis.fetch_room_state)
    │
    ▼
返回初始文档
    { type: "doc", str: "content...", revision: 42, clients: {...} }
    │
    ▼
editor_controller.js: initializeEditor(data)
    │
    ├── 创建 CodeMirror 编辑器
    ├── 创建 ot.EditorClient (管理本地 OT 状态)
    └── 创建 ot.CodeMirrorAdapter (监听编辑器变化)
```

**关键代码**:
- `app/javascript/controllers/editor_controller.js:140-171` - `openFile`
- `app/channels/room_collab_channel.rb:4-21` - `subscribed`

---

### 2. 用户编辑操作 (本地 → 服务端)

```
用户在编辑器输入 "Hello"
    │
    ▼
CodeMirrorAdapter 捕获变化
    │
    ▼
EditorClient.applyClient(operation)
    │
    ├── 创建 TextOperation
    │   例如: [5, "Hello", 3]  // retain(5), insert("Hello"), retain(3)
    │
    ├── 本地立即应用 (乐观更新 UI)
    │
    ▼
ActionCableAdapter.sendOperation(revision, operation, selection)
    │
    ▼
WebSocket 发送到服务端
    { action: "operation", revision: 42, operation: [...], selection: {...} }
    │
    ▼
RoomCollabChannel#operation(data)
    │
    ▼
RoomOTRedis.enqueue_operation(...)
    │
    ▼
写入 Redis Stream
    XADD ot:ops:0 * room_id 123 path "main.py" client_id "abc" revision 42 operation '[...]' selection '{...}'
```

**关键代码**:
- `app/javascript/controllers/editor_controller.js:24-27` - `sendOperation`
- `app/channels/room_collab_channel.rb:31-43` - `operation`
- `app/services/room_ot_redis.rb:163-174` - `enqueue_operation`

---

### 3. Worker 处理操作 (核心 OT 逻辑)

```
RoomOTWorker 无限循环
    │
    ▼
XREAD BLOCK 1000 STREAMS ot:ops:0 last_id
    │ 阻塞等待新操作
    ▼
收到操作消息
    │
    ▼
process(stream_id, fields)
    │
    ├── 解析字段: room_id, path, client_id, revision, operation, selection
    │
    ├── 创建 WrappedOperation
    │   wrapped = TextOperation
    │   meta = Selection (光标位置)
    │
    ▼
fetch_session(scope, room_id, path)
    │
    ├── 检查 @sessions 缓存
    │   key = "room:123:main.py"
    │
    ├── 缓存未命中: 从 Redis 重建 Session
    │   doc, rev, base_rev = RoomOTRedis.fetch_room_state(room, path)
    │   operations = RoomOTRedis.load_history(room_id, path)
    │   session = OT::Session.new(doc, operations, base_rev)
    │
    ▼
session.synchronize do  ←── 互斥锁，保证同一文档串行处理
    │
    ▼
session.server.receive_operation(revision, wrapped)
    │
    │  ═════════════════════════════════════════
    │  │  OT::Server#receive_operation (核心!)  │
    │  ═════════════════════════════════════════
    │  │                                         │
    │  │  1. 验证 revision                       │
    │  │     - revision < base_rev → StaleRevision │
    │  │     - revision > current → ArgumentError │
    │  │                                         │
    │  │  2. 计算 concurrent_operations          │
    │  │     其他客户端在此 revision 之后提交的操作 │
    │  │     concurrent = operations[index..-1]  │
    │  │                                         │
    │  │  3. OT 变换 (transform)                 │
    │  │     concurrent.each do |op|             │
    │  │       operation = transform(operation, op)[0] │
    │  │     end                                  │
    │  │                                         │
    │  │  4. 应用操作到文档                       │
    │  │     document = operation.apply(document) │
    │  │                                         │
    │  │  5. 记录操作到历史                       │
    │  │     operations << operation             │
    │  │                                         │
    │  │  6. 返回变换后的操作                     │
    │  ═════════════════════════════════════════
    │
    ▼
持久化结果
    │
    ├── RoomOTRedis.persist_operation
    │   更新 Redis: doc, revision, base_rev
    │   追加到 history 列表
    │
    ├── RoomFiles.write(room, path, document)
    │   写入数据库 (文件内容)
    │
    ▼
广播给客户端
    │
    ├── { type: "ack", client_id: "abc" }
    │   确认操作已处理
    │
    └── { type: "operation", client_id: "abc", operation: [...], selection: {...} }
        广播给其他客户端
```

**关键代码**:
- `app/services/room_ot_worker.rb:24-40` - `run` 主循环
- `app/services/room_ot_worker.rb:54-110` - `process`
- `lib/ot/server.rb:17-35` - `receive_operation` (核心 OT 算法)
- `lib/ot/text_operation.rb:297-413` - `transform`

---

### 4. 客户端接收远程操作

```
WebSocket 收到消息
    │
    ▼
ActionCableAdapter#receive(data)
    │
    ├── type: "ack"
    │   → 触发 callbacks.ack()
    │   → EditorClient 确认操作，清除 pending 状态
    │
    ├── type: "operation" (来自其他客户端)
    │   → 触发 callbacks.operation(data.operation)
    │   → EditorClient.applyServer(operation)
    │   │   ├── 对本地 pending 操作进行 OT 变换
    │   │   └── 应用到 CodeMirror 编辑器
    │   │
    │   └── 触发 callbacks.selection(client_id, selection)
    │       → 更新其他用户的光标显示
    │
    ├── type: "resync"
    │   → 请求重新同步完整文档
    │
    └── type: "client_left"
        → 移除该客户端的光标显示
```

**关键代码**:
- `app/javascript/controllers/editor_controller.js:34-68` - `receive`

---

## OT 算法核心

### TextOperation 结构

```ruby
# 操作由三种基本类型组成
[5, "Hello", -3, 10]
#  │       │      │
#  │       │      └── retain(10): 保留后 10 个字符
#  │       └── delete(3): 删除 3 个字符 (负数)
#  └── retain(5): 保留前 5 个字符

# 例如原文档 "Hello World" (11 字符)
# 操作 [5, " Beautiful ", -5, 1]
# 结果: "Hello Beautiful d"
```

### Transform 算法 (并发操作合并)

```
初始文档: "ABC"
        │
        ├─► 客户端 A: insert("X") at 0 → "XABC"
        │
        └─► 客户端 B: delete(1) at end → "AB"

两个操作并发到达服务端，需要 transform:

服务端收到 B 的操作时:
  - A 的操作已经应用，文档现在是 "XABC"
  - B 的操作 (delete last char) 需要变换

transform(B, A):
  B' = [retain(1), delete(1), retain(2)]  # 跳过 A 插入的 "X"

应用 B' 到 "XABC" → "XAB"
```

**关键代码**: `lib/ot/text_operation.rb:297-413`

---

## Transform 触发条件详解

### 核心逻辑

```ruby
# lib/ot/server.rb:26-30
def receive_operation(revision, operation)
  # ...
  index = revision - @base_revision
  concurrent_operations = @operations.slice(index, @operations.length - index) || []
  concurrent_operations.each do |concurrent|
    operation = operation.class.transform(operation, concurrent)[0]
  end
  # ...
end
```

### 什么时候需要 Transform？

**当 `revision < server.revision` 时**，即客户端的 revision 落后于服务端。

```
服务端状态: revision = 5, operations = [op1, op2, op3, op4, op5]
                                         ↑
                                    base_revision = 0
```

### 具体计算过程示例

```
时间线:
─────────────────────────────────────────────────────────►

服务端 revision:    0 → 1 → 2 → 3 → 4 → 5
服务端 operations:     [opA, opB, opC, opD, opE]

客户端 A:
  - 在 revision=2 时开始编辑
  - 发送 operation 时带 revision=2
  - 到达服务端时，revision 已经是 5

客户端 B:
  - 在 revision=3 时开始编辑
  - 发送 operation 时带 revision=3
  - 到达服务端时，revision 已经是 5
```

```ruby
# 服务端当前状态
@base_revision = 0
@operations = [opA, opB, opC, opD, opE]  # 长度 = 5
server.revision = 0 + 5 = 5

# 客户端 A 发送操作，带 revision = 2
index = 2 - 0 = 2
concurrent_operations = @operations.slice(2, 3) = [opC, opD, opE]

# 客户端 A 的操作需要与 opC, opD, opE 依次 transform！
opA' = transform(opA, opC)[0]   # 先和 opC 变换
opA'' = transform(opA', opD)[0] # 再和 opD 变换
opA''' = transform(opA'', opE)[0] # 最后和 opE 变换
```

### 并发的定义

**两个操作"并发"是指：它们基于相同的文档状态（相同的 revision）进行编辑。**

```
                文档状态 revision=3
                       │
         ┌─────────────┴─────────────┐
         ▼                           ▼
    客户端 A 编辑                  客户端 B 编辑
    发送 revision=3               发送 revision=3
         │                           │
         │                           │
    先到达服务端 ──────────────────► 后到达服务端
    服务端 revision 变成 4
                                  服务端 revision 已经是 4
                                  但 B 带的 revision=3

                                  index = 3 - 0 = 3
                                  concurrent = [opA]  ← A 的操作

                                  B' = transform(opB, opA)[0]
```

**核心结论**：
- transform 发生在并发操作时
- "并发" = 多个操作基于同一 revision
- 客户端发送的是**旧的操作号**（落后于服务端），而非"同一个操作号"

### Revision 同步机制

Revision 通过 **ACK 消息** 同步：

```
客户端                                    服务端
   │                                        │
   │── operation(rev=3, opA) ──────────────►│
   │                                        │ 处理成功
   │                                        │ revision: 3 → 4
   │◄─────────── ack ──────────────────────│
   │                                        │
   │  客户端收到 ack                         │
   │  本地 revision = 4                     │
   │                                        │
   │── operation(rev=4, opB) ──────────────►│
```

**等待 ack 期间的行为**：

```
客户端状态（等待 ack 中）:
  - confirmed_revision = 3    (已确认)
  - pending_operations = [opA] (等待确认)
  - local_revision = 4        (本地乐观更新后)

用户继续编辑:
  - 新操作 opB 基于 opA 的结果
  - 放入 pending_operations = [opA, opB]
  - 不立即发送，等 ack 后再发
```

### 三种场景详解

#### 场景 1：无并发（顺序操作）

```
客户端 A: rev=3 → ack → rev=4 → 编辑 → rev=5 → 发送
服务端:   rev=3 → 处理 → rev=4 → 处理 → rev=5

无 transform，操作直接应用
```

#### 场景 2：有并发（两个客户端同时编辑）

```
         rev=3
           │
     ┌─────┴─────┐
     ▼           ▼
  客户端 A     客户端 B
  revision=3   revision=3
     │           │
     ▼           │
  先到达         │
     │           │
  rev→4          │
     │           ▼
     │        后到达，带 rev=3
     │           │
     │        index = 3 - 0 = 3
     │        concurrent = [opA]
     │           │
     │        transform(opB, opA)
     │           │
     ▼           ▼
  rev=5       rev=5
```

#### 场景 3：单客户端多个 pending 操作

```
客户端快速输入:
  op1 (rev=3) → 发送
  op2 (基于op1) → 放入 pending
  op3 (基于op2) → 放入 pending

收到 ack(op1):
  发送 op2 (rev=4)

收到 ack(op2):
  发送 op3 (rev=5)

服务端依次处理，无 transform（因为是同一客户端顺序操作）
```

### 总结表

| 问题 | 答案 |
|------|------|
| 什么情况触发 transform？ | 客户端 revision < 服务端 revision |
| 并发才会 transform 吗？ | 是的，"并发" = 多个操作基于同一 revision |
| 是发送同一个操作号吗？ | 不是。是发送了**旧的操作号**（落后于服务端） |
| revision 如何同步？ | 收到 `ack` 后客户端更新本地 revision |

**核心公式**：
```ruby
concurrent_operations = @operations[revision - base_revision..-1]
# 如果 revision == server.revision，concurrent = []，无需 transform
# 如果 revision < server.revision，concurrent 不为空，需要 transform
```

---

## Redis 数据结构

| Key | 类型 | 用途 |
|-----|------|------|
| `ot:ops:{shard}` | Stream | 操作消息队列 |
| `ot:ops:{shard}:checkpoint` | String | Worker 消费位点 |
| `ot:state:{room_id}:{path}` | Hash | 文档状态 `{doc, rev, base_rev, last_id}` |
| `ot:history:{room_id}:{path}` | List | 操作历史 (JSON) |
| `ot:clients:{room_id}:{path}` | Hash | 客户端信息 `{client_id: {name, selection, seen_at}}` |

---

## 历史压缩

当操作历史超过阈值 (`OT_HISTORY_MAX=5000`)：

```ruby
# lib/ot/server.rb:37-43
def compact!(max_history)
  return false if operations.length <= max_history

  @base_revision = revision  # 更新基准版本号
  @operations = []           # 清空历史
  true
end
```

触发压缩后，广播 `{ type: "resync" }`，客户端需重新获取完整文档。

---

## 分片机制

分片用于水平扩展 Worker 处理能力：

```ruby
# app/services/room_ot_redis.rb:36-40
def self.shard_for(room_id, path)
  return 0 if STREAM_SHARDS <= 1
  Zlib.crc32("#{room_id}:#{path}") % STREAM_SHARDS
end
```

- 同一 `room_id:path` 的操作始终路由到同一分片
- 不同文档可以并行处理
- 默认 `OT_STREAM_SHARDS=1`，单 Worker 足以处理中等规模

---

## 流程总结

| 阶段 | 组件 | 动作 |
|------|------|------|
| 连接 | Channel | 返回文档 + revision + clients |
| 编辑 | 前端 | 乐观更新 + 发送 operation |
| 入队 | Channel | 写入 Redis Stream |
| 处理 | Worker | OT 变换 + 更新状态 |
| 持久化 | Worker | Redis + 数据库 |
| 广播 | Worker | ack + operation |
| 同步 | 前端 | 应用远程操作 + 更新光标 |

---

## 核心组件文件

| 文件 | 职责 |
|------|------|
| `app/channels/room_collab_channel.rb` | WebSocket 连接管理，操作入队 |
| `app/services/room_ot_redis.rb` | Redis 数据访问层 |
| `app/services/room_ot_worker.rb` | 后台 OT 处理进程 |
| `lib/ot/server.rb` | OT 服务端逻辑 (receive_operation) |
| `lib/ot/session.rb` | 会话管理 (锁 + 状态) |
| `lib/ot/text_operation.rb` | 文本操作 + transform 算法 |
| `lib/ot/selection.rb` | 光标选区 + transform |
| `app/javascript/controllers/editor_controller.js` | 前端编辑器控制器 |