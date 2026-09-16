# Proton macOS 主窗口关闭时的状态查询错误

这个程序只有一个 Proton 窗口和静态 HTML，不依赖 SeekMoon。使用发布的
`moonbit-community/proton@0.2.9`，没有修改 Proton 源码。

**复现限制：这是经过实测的 LLDB 辅助时序复现。普通单窗口手工关闭在本次验证中
正常退出；尚未找到无需调试器便稳定触发相同错误的纯 GUI 操作序列。**
LLDB 临时 retain 一次 `CefBrowserHostView`，延后它的析构，让应用观察到本就存在的
“AppKit 已关闭、CEF 尚未完成关闭”状态。没有修改指针、closed 标记或返回值。
这证明 Proton 对关闭中间态的处理有缺口，但不证明 SeekMoon 现场延迟析构的具体原因。

## Upstream status

Report for this repository: [Proton #312](https://github.com/moonbit-community/proton/issues/312).

This repository preserves a **Proton 0.2.9 LLDB-assisted timing reproduction**.
It is not a report that current Proton main is affected.

Before publishing, we found the same close-state failure in
[upstream issue #305](https://github.com/moonbit-community/proton/issues/305),
which was closed by [PR #306](https://github.com/moonbit-community/proton/pull/306)
(merged September 15, 2026). That fix handles the native-window/CEF close gap and
adds local autorelease pools around fullscreen transitions. The fix is an
ancestor of the 0.2.11 version-bump commit. We have not rerun this experiment on
0.2.11 or verified which interaction delayed view destruction in the original
SeekMoon session. Upstream also provides a fullscreen reproduction that does
not require LLDB; see #305 and #306.

The sample contains only one Proton window and static HTML. The debugger adds
one temporary retain to delay CEF view destruction, captures the invalid state,
then balances the retain. It does not write lifecycle fields or forge errors.
Ordinary single-window close was a passing control in our runs.

## 运行

需要 macOS、MoonBit 和 Xcode Command Line Tools。

```sh
./build.sh
./debug.sh
```

待窗口出现，点击左上角红色关闭按钮。脚本会自动：

1. 在 `proton_engine_window_commit_appkit_close` 临时 retain 主浏览器视图。
2. 在 `mac_window.objc.c:2128` 错误分支打印状态和调用栈。
3. release 刚才增加的引用，再继续运行，让原本的错误返回到 Proton。

预期 LLDB 输出：

```text
window->window        = nil
window->closed        = 0
window->appkit_closing = 1
```

日志会出现：

```text
application runtime failed
runtime failed during poll event (-2): window is not initialized
```

日志位置：`~/Library/Logs/dev.repro.proton-close/proton-<PID>.log`。
错误弹窗可能只短暂出现，或因错误处理再次轮询同一坏状态而提前结束；以日志及断点
状态为准。`run_or_abort()` 最后可能停在 SIGABRT；在 LLDB 输入 `process kill`、
`quit` 清理此示例进程。不要操作正在使用的 SeekMoon 进程。

普通运行对照：

```sh
'dist/Proton Close Repro.app/Contents/MacOS/proton-close-repro'
```

`build.sh` 只给新生成的示例 app 添加 `get-task-allow`；不会重新签名或修改
`/Applications/SeekMoon.app`。发布应用不应携带这个调试 entitlement。

## 缺陷位置（Proton 0.2.9）

依赖源码位于 `.mooncakes/moonbit-community/proton/`：

- `internal/native/ffi_mac/mac_window.objc.c:422-463`：
  `proton_engine_window_commit_appkit_close` 设置 `appkit_closing=1`，在第 440 行
  清空 `window->window`，但不设置 `closed`。
- `internal/native/ffi_mac/mac_client.objc.c:308-349`：
  `proton_engine_on_before_close` 在 CEF 的关闭回调里才调用
  `proton_engine_window_mark_closed`（第 344 行）。
- `internal/native/ffi/src/proton_state.c:322-337`：
  `proton_runtime_sync_engine_window_states` 仅跳过已关闭/已销毁的窗口，仍查询
  上述关闭中间态；状态查询的失败被直接返回。
- `internal/native/ffi_mac/mac_window.objc.c:2127-2129`：
  `proton_engine_window_get_state` 把空的 NSWindow 当成无效句柄，返回 `-2`。
- `internal/native/ffi/src/proton.c:503-507` → `facade_runtime_events.mbt:25-26`：
  将该错误升级为整个 runtime 的 `poll event` 失败。

这不需要多个线程并发写同一字段；单主线程上，AppKit 和 CEF 的不同生命周期回调
之间也存在这个中间态。已对 `/Applications/SeekMoon.app` 0.1.97 的实际二进制
进行离线反汇编，以上关键分支一致；未仅凭当前依赖推断旧安装包的行为。

## 修复方向

应把原生窗口已经分离、CEF 仍在收尾的状态显式纳入生命周期，停止对该状态读取
NSWindow 的几何属性，同时继续驱动 CEF 关闭和资源清理。不要简单把所有 `-2`
忽略掉，也不要未经核查就提前设置 `closed`：它还参与关闭事件和资源释放逻辑。

## 验证记录

环境：macOS 26.6.2 / Apple Silicon；moon 0.1.20260915；moonc 0.10.13。
已通过 `moon info && moon fmt` 及 Proton CLI debug app 打包。

`evidence/` 保存本次运行的 LLDB 输出、应用错误日志和安装包反汇编。
发布前已将本机路径替换为 `<repro-root>`，并移除行尾空格；调试内容未改动。
单窗口普通关闭、增加输入框及 unload 回调都未自然复现相同错误。
探索中还观察到带子视图退出卡住，以及 on_ready 回调内自动关闭的崩溃；这些不是
本报告中的同一条错误，未保留在最小示例或当作复现成功的依据。
