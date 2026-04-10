# Architecture Sketch

## 实际分层

```text
UI
  -> VaultController
    -> VaultRepository
      -> VaultPacker
      -> BundleSerializer
      -> CryptoService
      -> VaultFileStore
      -> SyncService
```

## 关键职责

### VaultController

负责：

* 当前文档选择
* 搜索条件
* 编辑状态
* 自动保存调度
* 串行保存队列
* 资源导入、引用和删除

不负责：

* 加密细节
* 文件系统细节
* OSS SDK 细节

### VaultRepository

负责：

* 按密码解锁 `DocumentVault`
* 保存当前 `DocumentVault`
* 协调打包、序列化、加密和本地持久化

当前接口：

```dart
abstract class VaultRepository {
  Future<DocumentVault> unlock(String password);
  Future<void> save(DocumentVault vault, String password);
}
```

### VaultPacker

负责把内存中的 `DocumentVault` 转成逻辑上的明文文件树：

```text
manifest.json
docs/<doc-id>.md
assets/<asset-name>
```

当前行为：

* `manifest` 保存 revision、文档元数据、资源索引
* 文档正文放入 `docs/<doc-id>.md`
* 资源内容放入 `assets/*`
* `assets` 在 pack 时转成 base64 文本写入明文 payload

### BundleSerializer

负责把加密 envelope 序列化为最终的 `vault.bundle` 字节流，并在解锁时反序列化回来。

### CryptoService

负责：

* 用 `Argon2id` 从主密码派生密钥
* 用 `XChaCha20-Poly1305` 加密和解密整个 Vault

当前输出结构：

```text
vault.bundle
  version
  revision
  savedAt
  kdf
    name = argon2id
    memory
    iterations
    parallelism
    salt
  cipher
    name = xchacha20poly1305
    nonce
    mac
  payload
```

说明：

* `salt` 随机生成，公开存储
* `nonce` 随机生成，公开存储
* `mac` 用于完整性校验
* `payload` 是整个 Vault 的密文

### VaultFileStore

负责：

* 本地 bundle 文件路径
* 本地 config 路径
* 按用户名隔离本地目录

当前本地布局：

```text
%APPDATA%/secret_book/<username>/vault.bundle
%APPDATA%/secret_book/<username>/config.json
```

### SyncService

负责：

* 获取远端 revision
* 上传加密 bundle
* 下载最新 bundle
* 避免覆盖远端更新
* 上传前生成远端备份对象

当前远端布局：

```text
{username}/vault.bundle
{username}/backup/vault.bundle.TIMESTAMP
```

当前认证方式：

* 阿里云 OSS
* STS HTTP 接口获取临时凭证

## 保存链路

```text
用户编辑文档
  -> VaultController debounce / Ctrl+S
  -> VaultRepository.save
  -> VaultPacker.pack
  -> CryptoService.encrypt
  -> BundleSerializer.serializeEnvelope
  -> VaultFileStore.writeBundle
  -> SyncService.syncAfterLocalSave
```

## 解锁链路

```text
用户名
  -> 定位本地 <username>/vault.bundle
  -> 用户输入主密码
  -> VaultRepository.unlock
  -> BundleSerializer.deserializeEnvelope
  -> CryptoService.decrypt
  -> VaultPacker.unpack
  -> 还原 DocumentVault 到内存
```

## 设计结论

* `vault.bundle` 本身就是加密文件
* `manifest.json` 只存在于解密后的明文 payload 中
* 主密码强度仍然是整体安全性的核心
* `Argon2id` 的意义是让每次猜密码变贵
* `salt` 和 `nonce` 可以公开存储，真正要保密的是主密码和派生密钥