## 概念

Mailbox: 邮箱，也即一个指针，指向集群中的某个entity。Mailbox能发起rpc调用；也能作为参数在rpc之间传递，然后发起回调。

## 数据结构

```
string entity_type; // mailbox所指向的entity的类型，例如Avatar、RedisService等
string entity_id;   // entity_id
string process_id;  // mailbox所在进程id，对于不可迁移的entity也等于entity所在的进程id
int    entity_term; // 集群的逻辑时钟暂时未用
```

## 原理

对于不可迁移的entity，可认为mailbox和对应的entity存在于同一个logic进程。

![[Pasted image 20251118144439.png]]

对于可迁移的entity，mailbox存在与router上，entity迁移前后mailbox保持不变，只是指向改变。在entity迁移期间mailbox所在的router会缓存集群发给entity的消息，迁移完毕后，router再把缓存的消息发到迁移后的entity上。
![[Pasted image 20251118144427.png]]