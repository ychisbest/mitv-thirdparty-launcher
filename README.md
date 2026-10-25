# 小米电视第三方启动器（无 Root 改包名 + 临时 Root 笔记）

在 **小米电视 / 小米盒子（MIUI TV，Android 10 实测）** 上，把第三方桌面设成真正的默认 Home，并记录相关踩坑。

实测机型：`MiTV-MTEQ0`（代号 `baymax`）/ Android 10 / `mi_platform_id=1186`

> **风险声明**：可能影响保修、稳定性与安全。操作前确认能进设置 / 能 ADB。本文仅供学习研究，请自行承担风险。

---

## 目录

1. [现象与根因](#1-现象与根因)
2. [官方第三方桌面白名单](#2-官方第三方桌面白名单)
3. [推荐方案：改包名蹭白名单](#3-推荐方案改包名蹭白名单)
4. [正确操作顺序](#4-正确操作顺序)
5. [信号源（HDMI）问题](#5-信号源hdmi问题)
6. [临时 Root：TvService 4400](#6-临时-roottvservice-4400)
7. [ADB 为什么会自己关](#7-adb-为什么会自己关)
8. [精简建议](#8-精简建议)
9. [持久 Magisk 结论](#9-持久-magisk-结论)
10. [常用命令速查](#10-常用命令速查)

---

## 1. 现象与根因

### 现象

1. 装了第三方桌面（FLauncher / Projectivy / Orchard 等），`set-home-activity` 显示 Success，按 Home 仍进 `com.mitv.tvhome`。
2. `pm disable-user com.mitv.tvhome` 后按 Home → **黑屏**。
3. 黑屏时实际是：`com.android.tv.settings/.system.FallbackHome`。

### 根因

`services.jar` 里 `PackageManagerService.chooseBestActivity` 对 **HOME** 做了过滤：

- HOME 候选 **> 1** 时，只保留：
  - `system` 应用；或
  - `MitvSettings.isThirdpartyHomeAllowed(pkg) == true` 的包
- 白名单来自 `/data/system/mitv_security_center.xml`，flag **`third_party_home = 4`**
- shell **读不了 / 写不了** 该文件；`setprop persist.appcontrol_w_mask` 也被 SELinux 拦住

判定逻辑（简化）：

| 条件 | 结果 |
|------|------|
| 白名单为空 / null | 第三方 HOME 全放行 |
| `persist.appcontrol_w_mask & 4 == 0` | 该 flag 放行 |
| 否则 | 包名必须在白名单里且带 flag 4 |

禁用系统桌面后，候选变成「第三方 + FallbackHome」→ 第三方被滤掉 → 只剩 FallbackHome → 黑屏。  
FallbackHome **不能**被 shell `pm disable`（`SecurityException`）。

框架 **只比对包名字符串，不校验签名**。

---

## 2. 官方第三方桌面白名单

公开 CDN（与机内云控同源配置，可随时间变化）：

```text
https://cdn.cnbj3-fusion.fds.api.mi-img.com/xmls/mitv_security_center.xml
https://cdn.cnbj3-fusion.fds.api.mi-img.com/xmls/ccc.xml
```

`<feature name="third_party_home">` 中**明确像桌面**的包名（2026-10 拉取，请以 CDN 最新为准）：

| 包名 | 备注 |
|------|------|
| `com.bytv.launcher` | 常用改装目标 |
| `com.bytv.launcher.special` | |
| `com.ts.launcher` | 常用改装目标 |
| `com.tongshi.home` | |
| `com.meituan.retail.launcher` | |

同 feature 下还有大量非桌面包（统计、语音、调试等），完整列表见 [docs/whitelist-third_party_home.txt](docs/whitelist-third_party_home.txt)。

---

## 3. 推荐方案：改包名蹭白名单

**不用 Root、不 MITM 云控。**

思路：把任意第三方桌面的 `applicationId` / `package` 改成白名单里的包（如 `com.bytv.launcher`），Activity 类名可保持原 FQCN。

### 工具

- `apktool`、`jarsigner` / `apksigner`、`zipalign`
- 自签 debug keystore 即可（框架不验签）

### 步骤概要

```bash
# 1. 解码
apktool d -f your-launcher.apk -o src

# 2. 改 AndroidManifest.xml
#    package="com.bytv.launcher"
#    自定义 permission / FileProvider authorities 同步改前缀
#    Activity 用全限定名，例如 app.orchard.tv.MainActivity / me.efesser.flauncher.MainActivity

# 3. 同步改 smali 里硬编码的 applicationId 字符串（const-string "原包名"）
#    不要改真正的类路径 Lcom/... （Class.forName 用的类名要保留）

# 4. 回编、对齐、签名
apktool b src -o unsigned.apk
zipalign -f 4 unsigned.apk aligned.apk
jarsigner -sigalg SHA256withRSA -digestalg SHA-256 \
  -keystore debug.keystore -storepass android -keypass android \
  aligned.apk androiddebugkey

# 5. 安装并设默认（见下一节）
```

实测成功过的桌面：

- FLauncher → `com.bytv.launcher`
- Projectivy → `com.ts.launcher`（可顺带改信号源入口）
- Orchard TV (`app.orchard.tv`) → `com.bytv.launcher`

---

## 4. 正确操作顺序

**先保证 resolve 已指向第三方，再禁 tvhome。** 顺序反了容易黑屏。

```bash
adb connect <TV_IP>:5555

# 安装改包名后的 APK
adb install -r orchard_bytv.apk

# 设默认（组件名按实际 APK）
adb shell cmd package set-home-activity --user 0 \
  com.bytv.launcher/app.orchard.tv.MainActivity

# 必须已经指向第三方
adb shell cmd package resolve-activity --brief \
  -a android.intent.action.MAIN -c android.intent.category.HOME

# 再禁系统桌面
adb shell pm disable-user --user 0 com.mitv.tvhome

# 验证
adb shell input keyevent KEYCODE_HOME
adb shell dumpsys window | grep mCurrentFocus
```

### 恢复系统桌面

```bash
adb shell pm enable com.mitv.tvhome
adb shell cmd package set-home-activity --user 0 \
  com.mitv.tvhome/.MainActivityUserMode
```

---

## 5. 信号源（HDMI）问题

### 原因

整包 `pm disable-user com.mitv.tvhome` 后，遥控器「信号源」等入口常失效。  
底层切源在 `mitv.service` / `SourceManager`，UI 多走设置弹窗：

```text
com.xiaomi.mitv.settings.INPUTSOURCE_POPUP
```

实测：

```bash
adb shell am broadcast -a com.xiaomi.mitv.settings.INPUTSOURCE_POPUP
# 可弹出系统切源界面（如 ExternalSourceActivity / settings_window）
```

想只禁 HOME Activity、保留 tvhome 其它能力：shell / 临时 root 调 `pm` **都不行**（组件受保护或 SELinux）。

### 折中

1. **启用整包 tvhome** → 信号源恢复，但 Home 可能抢回系统桌面（需再设 preferred）。
2. **保持禁 tvhome** + 做一个「信号源」小应用，打开即发上述广播（见思路）。
3. 可把 Projectivy 的 `SourcePopupActivity` / HDMI 入口 smali 改成启动该小应用。

---

## 6. 临时 Root：TvService 4400

### 原理

`com.mitv.cloudcontrol` / TvService 中：

- `MITV_SERVICE_MISYSDIAGNOSE = 4400`
- `onTransact(4400)` **无**调用方权限校验
- 写入 `vendor.misysdiagnose.cmd.code` / `arguments`
- `init`：`exec - root root -- /vendor/bin/misysdiagnose -${code} ${arguments}`

`code=s` 表示跑命令。格式：`命令,参数1,参数2,...`（**逗号分隔**，复杂逻辑请用脚本文件）。

### 调用

```bash
# 验证 uid=0（输出写到 /sdcard，勿写 /data/local/tmp）
adb shell 'service call TvService 4400 s16 s s16 "sh,-c,id>/sdcard/root_probe.txt"'
adb shell cat /sdcard/root_probe.txt
# 期望：uid=0(root) ... context=u:r:misysdiagnose:s0
```

推荐：

```bash
adb push my.sh /sdcard/my.sh
adb shell 'service call TvService 4400 s16 s s16 "sh,/sdcard/my.sh"'
```

### 能力边界（重要）

| 能 | 不能 |
|----|------|
| uid=0 跑命令（在 `misysdiagnose` 域内） | `setenforce 0` |
| 写 `/sdcard`、部分 `/data`、`/data/local` | remount `/system` `/vendor` |
| `settings put ...` | 读/写 boot 分区、`/dev/block` |
| | 写 `/data/adb`（Magisk 目录） |
| | 通过 binder 调 `pm`/`am`（常 Failed transaction） |

这是 **按次执行的受限临时 root**，不是完整 Magisk。

---

## 7. ADB 为什么会自己关

`com.xiaomi.mitv.settings` 的 `SettingsBroadcastReceiver` 在：

- `BOOT_COMPLETED`
- `mitv.action.STR_BOOT_COMPLETED`（待机唤醒）

且 `Build.TYPE == user`、电视产品时，强制：

```java
SettingsUtil.setADBEnable(0);
```

所以每次开机 / 部分唤醒后 ADB 会被关掉。

应对：进设置重新打开；或装一个开机后延迟把 `adb_enabled` 设回 1 的小应用；或用临时 root 跑 watchdog 脚本。

`persist.adb.tcp.port=5555` 可能仍在，但 `adb_enabled=0` 时 adbd 不起来。

---

## 8. 精简建议

可用 `pm disable-user --user 0 <包名>`（可 `pm enable` 恢复），参考 [CleanYourTV](https://github.com/Gathin23/cleanyourtv) 小米列表。

常见可冻：

- 云控：`com.mitv.cloudcontrol`
- 升级：`com.xiaomi.mitv.upgrade`
- 推送 / 统计 / 商店 / 画报 / 屏保 等

**慎冻 / 建议保留：**

- `mitv.service`、`com.xiaomi.mitv.settings`、systemui
- 投屏：`com.duokan.airkan.tvbox`、`com.xiaomi.mitv.smartshare`、`com.xiaomi.miplay`（冻了手机投屏会没）
- 语音相关（若还要用小爱）

机上通常 **没有 iptables**，广告域名需路由器拦截。

---

## 9. 持久 Magisk 结论

仅靠 ADB + TvService 4400：**做不到** 可靠持久 Magisk（关不了 SELinux、刷不了 boot、写不了 `/data/adb`）。

`baymax` / Android 10 社区持久 root 多走：**UART（CP2102）→ U-Boot / Recovery → Magisk**。

---

## 10. 常用命令速查

```bash
# 当前默认桌面
adb shell cmd package resolve-activity --brief \
  -a android.intent.action.MAIN -c android.intent.category.HOME

# 所有 HOME 候选
adb shell pm query-activities --brief \
  -a android.intent.action.MAIN -c android.intent.category.HOME

# 设默认 / 禁系统桌面
adb shell cmd package set-home-activity --user 0 <pkg>/<activity>
adb shell pm disable-user --user 0 com.mitv.tvhome

# 临时 root 探针
adb shell 'service call TvService 4400 s16 s s16 "sh,-c,id>/sdcard/id.txt"'

# 系统信号源弹窗
adb shell am broadcast -a com.xiaomi.mitv.settings.INPUTSOURCE_POPUP
```

---

## 参考

- 云控白名单 CDN：上文 XML 链接
- [CleanYourTV](https://github.com/Gathin23/cleanyourtv) 精简与自研桌面
- 社区 baymax UART Magisk 教程（ZNDS 等论坛）

---

## License

文档以 CC0 / 公共领域意愿分享；涉及的第三方 APK、商标归原作者。请勿用于未授权的商业用途。
