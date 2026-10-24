# sync_scroll_library（修补版）

[English](README.md)

[fluttercandies/sync_scroll_library](https://github.com/fluttercandies/sync_scroll_library)
1.1.0 的修补 fork，也就是 [extended_tabs](https://pub.dev/packages/extended_tabs)
背后的滚动联动库。包名保持不变，应用通过 `dependency_overrides` 接入。**不会**发布到
pub.dev（`publish_to: none`），版本号 `1.1.0+patched.1`。

## 修了什么

子层滚到边界后，`LinkScrollControllerMixin` 会把拖拽交给父层（TabBarView、PageView 之类）。
上游之后再也不收回：只要有父层被激活，`linkActivedParent` 就直接 return。所以同一次
手势里手指反向拖回时，父层一直霸占拖拽直到抬手，子层再也滚不动。

最小复现：`ExtendedTabBarView`（父层）第一页里放一个横向列表（子层）。向左拖到列表末尾，
Tab 视图开始往第二页走；手指不抬，再向右拖：Tab 视图跟着退回第一页，然后继续吞掉拖拽，
列表却停在末尾，明明左边还有大把内容。

修法：父层接管时记下它的偏移作为锚点。反向拖动时，父层保留拖拽，直到它退回锚点；之后
取消父层的拖拽，同一次手势里子层重新可滚。前提是子层在该方向还能滚，否则父层照旧持有拖拽。
rtl 的 delta 取反提前到所有判断之前。全部改动都在 `lib/src/link/link_controller.dart`，
其余与 1.1.0 一致。

已知限制：判断在每次指针移动时、该次移动生效之前进行，所以子层接管时父层最多会越过锚点
一次移动的 delta。带分页物理的父层在拖拽取消后会自己吸附回去。

## 在应用里使用

`dependency_overrides` 只在根包（也就是 app）里生效，并且忽略版本约束
（`extended_tabs` 要求的是 `^1.1.0`）。

本地路径：

```yaml
dependency_overrides:
  sync_scroll_library:
    path: ../dart-labs/sync_scroll_library_patched
```

git（想要可复现的构建，把 `ref` 钉到某个 commit）：

```yaml
dependency_overrides:
  sync_scroll_library:
    git:
      url: https://github.com/icodejoo/dart-labs.git
      path: sync_scroll_library_patched
      ref: main
```

## 测试

```sh
flutter test
```

`test/link_reverse_drag_test.dart` 搭了「关联的子层列表嵌在关联的父层列表里」，用
`startGesture` 加多次 `moveBy` 重放同一次手势。覆盖 ltr/rtl 下的两个边界、同一手势里的二次接管、
以及子层不可滚的情况。交还控制权的用例在上游原版 `link_controller.dart` 下会失败，打上补丁后通过。

## 许可证

MIT，原版权归 FlutterCandies，见 [LICENSE](LICENSE)。
