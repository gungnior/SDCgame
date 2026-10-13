# Android 导出（本机可复现的做法）

> 2026-10-13 · 首次导出成功：`build/soudache.apk` 44.2 MB，签名 v2/v3 通过。
> 本文记的是**本机实际跑通的那条路**，包括踩过的两个坑。

## 1. 一次性备料（约 1.25 GB）

| 件 | 来源 | 放哪 |
|---|---|---|
| Godot 导出模板 | `Godot_v4.7.2-stable_export_templates.tpz`（GitHub Releases） | `%APPDATA%\Godot\export_templates\4.7.2.stable\` |
| JDK 21 | Adoptium Temurin（`api.adoptium.net`） | `<项目>\_install\jdk\jdk-21.0.12.1+1` |
| Android build-tools | `build-tools_r34-windows.zip`（dl.google.com） | `<项目>\_install\android-sdk\build-tools\34.0.0` |
| Android platform-tools | `platform-tools-latest-windows.zip` | `<项目>\_install\android-sdk\platform-tools` |
| 调试签名证书 | `keytool -genkeypair`（别名 `androiddebugkey`，口令 `android`） | `%APPDATA%\Godot\keystores\debug.keystore` |

## 2. Godot 编辑器设置（一次性，写 `%APPDATA%\Godot\editor_settings-4.7.tres`）

```
export/android/android_sdk_path = "E:/AAAASDC/_install/android-sdk"
export/android/java_sdk_path  = "E:/AAAASDC/_install/jdk/jdk-21.0.12.1+1"
export/android/debug_keystore      = ".../Godot/keystores/debug.keystore"   # 默认值，已就位
export/android/debug_keystore_pass = "android"
```

## 3. 导出命令

```powershell
$env:JAVA_HOME = "E:\AAAASDC\_install\jdk\jdk-21.0.12.1+1"
$env:PATH = (Join-Path $env:JAVA_HOME "bin") + ";" + $env:PATH
cd E:\AAAASDC
& _install\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . `
    --export-debug "Android" build\soudache.apk
```

发布版把 `--export-debug` 换成 `--export-release`（需要另配 release keystore；
`export_presets.cfg` 里的 preset 名就是 `"Android"`）。

## 4. 踩过的两个坑

1. **`platform-tools` 必装**：即使预设里 `use_gradle_build=false`，Godot 的导出校验仍会去 SDK 里找
   `platform-tools`（adb），缺了就报「编辑器设置中的 Android SDK 路径无效。缺失 platform-tools 目录！」。
2. **导出模板不必全解压**：tpz 有 1.2 GB，而导出 Android 只需要 `android_debug.apk`、
   `android_release.apk` 和 `version.txt` 三件（`version.txt` 用于版本校验）。

## 5. 验货清单（本机实跑过）

```powershell
& _install\android-sdk\build-tools\34.0.0\apksigner.bat verify --verbose --print-certs build\soudache.apk
```

- 结果：`Verifies`；`v2 true` / `v3 true`；`CN=Android Debug`；RSA 2048。
- 包名 `com.aaaaadsh.soudache`；版本 `0.24.0-uiredesign`；引擎 `4.7.2.stable`。
- 642 个条目，`assets/` 下 544 个；本轮 15 个新功能脚本（`.gdc`）全部在包内。

## 6. 装到手机（不需要 adb）

把 `build/soudache.apk` 拷进手机（数据线 / 网盘 / 聊天工具任选），
在手机上允许「安装未知来源应用」后点开安装即可。
