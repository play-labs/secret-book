# Secret Book

个人加密文档管理应用的 Flutter Windows 桌面原型。

## 当前实现

* 用户名入口，按用户名隔离本地目录和 OSS 路径
* 首次创建主密码，后续通过主密码解锁
* 支持修改主密码并重加密整个 `vault.bundle`
* 左侧文档列表、搜索、标签、自动保存、`Ctrl+S` 立即保存
* Markdown 编辑与预览
* 图片和任意二进制文件导入，统一存入 `assets/`
* 预览中支持图片显示
* `Tools` 视图内置随机密码工具
* Windows 窗口大小和位置记忆
* 本地真实 `vault.bundle` 持久化
* `vault.bundle` 整体加密保存和解锁
* Vault 明文结构采用 `manifest + docs + assets`
* 阿里云 OSS 同步链路已接入，远端路径按用户名隔离

## 密码与加密设计

### 主密码

* 主密码不会写入 `config.json`
* 首次创建保险库时，输入的主密码直接作为加密口令
* 之后解锁、保存、改密码都基于该主密码
* 安全性仍然主要依赖主密码强度

### KDF 与加密算法

当前实现：

* KDF：`Argon2id`
* Cipher：`XChaCha20-Poly1305`

当前 Argon2id 参数：

* `memory = 65536`
* `iterations = 3`
* `parallelism = 1`
* `hashLength = 32`

### salt / nonce / mac

* `salt`：每次加密随机生成 16 字节，并写入 `vault.bundle`
* `nonce`：每次加密随机生成 24 字节，并写入 `vault.bundle`
* `mac`：由 AEAD 加密生成，用于完整性校验，并写入 `vault.bundle`

它们都不是秘密，可以公开存储；真正需要保密的是主密码和派生出的密钥。

## vault.bundle 结构

磁盘上的 `vault.bundle` 是加密 envelope，不是明文文档树。

公开 envelope 结构大致如下：

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

其中：

* `payload` 是真正的密文
* `revision / savedAt / kdf / cipher` 是可见元数据

## Vault 明文结构

`payload` 解密后，是一个逻辑上的虚拟文件系统：

```text
manifest.json
docs/<doc-id>.md
assets/<asset-name>
```

其中：

* `manifest.json`：记录 revision、文档元数据、资源索引、路径映射
* `docs/`：保存文档正文
* `assets/`：保存图片与任意二进制附件

## 用户名隔离

本地与远端都按用户名隔离：

* 本地：`{appData}/secret_book/<username>/vault.bundle`
* 本地：`{appData}/secret_book/<username>/config.json`
* OSS：`{username}/vault.bundle`
* OSS 备份：`{username}/backup/vault.bundle.TIMESTAMP`

## 运行

开发模式：

```bash
flutter pub get
flutter run -d windows
```

或使用脚本：

```cmd
.\scripts\run_dev.cmd
```

发布 Windows 版本：

```cmd
.\scripts\publish.cmd
```

发布产物目录：

```text
dist/secret_book-windows-release/
```