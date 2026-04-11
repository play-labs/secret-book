# 个人加密文档管理应用设计文档（精简决策版 v1）

> 目标：让产品设计、当前实现和安全方案保持一致，避免文档落后于代码。

---

## 1. 产品定位（已定）

* 类型：个人加密文档管理，不是网站密码管理器
* 平台：Flutter，优先 Windows 桌面
* 模式：离线优先 + 云端仅同步密文 `vault.bundle`
* 多用户：同一台机器通过用户名隔离不同保险库

---

## 2. 核心模型（已定）

### 文档模型

```text
Document
- id
- title
- content
- createdAt
- updatedAt
- assetRefs
```

### 资源模型

```text
Asset
- id
- path
- mediaType
- size
- createdAt
- bytes
```

### Vault 内部逻辑结构

外部只有一个 `vault.bundle`，但内部采用虚拟文件系统组织：

```text
/vault
  manifest.json
  /docs
    <doc-id>.md
  /assets
    <asset-name>
```

说明：

* `manifest.json`：记录 revision、文档元数据、资源索引和路径映射
* `docs/`：保存每篇文档的 Markdown 正文
* `assets/`：保存图片与任意二进制附件

对外仍然只有一个加密后的 `vault.bundle`，虚拟文件系统只是解密后的内部结构。

---

## 3. 密码与加密方案（关键）

### 主密码

当前设计：

* 用户第一次创建保险库时设置主密码
* 主密码不会写入 `config.toml`
* 主密码直接输入给 KDF，不做额外 MD5 预处理
* 修改主密码时，会对整个 `vault.bundle` 重新加密

结论：

* 安全性最终仍然高度依赖主密码强度
* `Argon2id` 的作用是让每次猜密码变贵，而不是替代强密码

### KDF

当前已定并已实现：

* `Argon2id`
* 参数：`memory = 65536`、`iterations = 3`、`parallelism = 1`、`hashLength = 32`

说明：

* KDF 用来把主密码派生为真正的加密密钥
* `kdf.name / memory / iterations / parallelism / salt` 会公开写入 `vault.bundle`
* 这属于正常设计，不构成泄密

### 加密算法

当前已定并已实现：

* `XChaCha20-Poly1305`

说明：

* 这是实际用于加密整个 Vault 的 AEAD 算法
* 会产生 `nonce` 和 `mac`
* `mac` 用于完整性校验，防止错误密码或数据被篡改时仍被当作正常数据处理

### salt / nonce / mac

当前实现：

* `salt`：每次加密随机生成 16 字节
* `nonce`：每次加密随机生成 24 字节
* `mac`：每次加密由 AEAD 自动生成

说明：

* `salt` 用于主密码 -> 密钥 的派生过程
* `nonce` 用于密钥 -> 密文 的加密过程
* `mac` 用于校验密文、nonce、aad 是否被篡改
* `salt` 和 `nonce` 都不是秘密，可以公开存储在 `vault.bundle` 中

### 加密粒度

当前已定：

* 整体 Vault 加密

含义：

```text
主密码
  -> Argon2id
  -> 得到加密密钥
  -> 打包整个 Vault 明文结构（manifest + docs + assets）
  -> 用 XChaCha20-Poly1305 加密整个 Vault
  -> 生成 vault.bundle
```

---

## 4. vault.bundle 存储结构（已定）

### 外层：加密 envelope

磁盘上的 `vault.bundle` 是加密文件，逻辑上类似：

```json
{
  "version": 1,
  "revision": 12,
  "savedAt": "2026-04-10T04:30:00.000Z",
  "kdf": {
    "name": "argon2id",
    "memory": 65536,
    "iterations": 3,
    "parallelism": 1,
    "salt": "..."
  },
  "cipher": {
    "name": "xchacha20poly1305",
    "nonce": "...",
    "mac": "..."
  },
  "payload": "..."
}
```

说明：

* `payload` 是真正的密文
* `revision / savedAt / kdf / cipher` 是公开元数据
* `vault.bundle` 本身不是明文 Markdown，也不是明文 JSON 文件树

### 内层：解密后的明文结构

`payload` 解密后对应的逻辑结构：

```text
manifest.json
docs/<doc-id>.md
assets/<asset-name>
```

---

## 5. 本地存储（已定）

### 本地目录结构

当前实现已经按用户名隔离：

```text
app_data/
  secret_book/
    <username>/
      vault.bundle
      config.toml
```

说明：

* `vault.bundle`：唯一敏感文件
* `config.toml`：只存非敏感配置，例如 OSS endpoint、STS 地址、自动保存延迟等

### 当前保存流程

```text
内存中的 DocumentVault
  -> pack 成 manifest + docs + assets
  -> 序列化为明文 bytes
  -> 加密为 envelope
  -> 写入 vault.bundle
```

---

## 6. 同步策略（已实现主链路）

### 远端路径

当前实现已经按用户名隔离：

```text
{username}/vault.bundle
{username}/backup/vault.bundle.TIMESTAMP
```

### 规则

* 本地保存后尝试同步
* 上传前检查远端 revision
* 若远端已更新，则禁止覆盖
* 上传前会先把远端旧版移动为备份对象

### 认证方式

当前实现：

* 阿里云 OSS
* STS 接口获取临时凭证
* STS API URL、Header、Body 都可配置

---

## 7. UI 结构（当前实现）

### 布局

* 左侧：文档列表、搜索、Vault 信息
* 右侧：文档区 / 文件区 / 工具区

### 编辑器模式

当前实现：

* 文档区单状态切换：`Edit` 或 `Preview`
* 编辑区带基础 Markdown 语法高亮
* 预览区支持复制文本

### 文件能力

当前实现：

* 支持上传图片和任意二进制文件
* 文件统一写入 `assets/`
* 支持下载到本地
* 支持删除资源

---

## 8. 编辑与保存（当前实现）

### 保存策略

* 自动保存
* `Ctrl+S` 立即保存
* 保存时串行排队
* 若已有排队保存，不继续无限堆积
* 只有内容真实变化时才保存

### 自动保存

* 默认编辑后 15 秒保存
* 可在 `config.toml` 中调整

---

## 9. 当前确定方案

* Markdown 文档
* Vault 内部采用虚拟文件系统（`manifest + docs + assets`）
* 整体 Vault 加密
* `Argon2id + XChaCha20-Poly1305`
* `salt / nonce` 随机生成并写入 bundle
* `mac` 用于完整性校验
* 本地和 OSS 都按用户名分目录
* 阿里云 OSS + STS 临时凭证
* 自动保存 + `Ctrl+S`
* 图片和二进制附件支持
* 工具页支持随机密码生成