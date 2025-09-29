# flutter_image_compress

🚀 The Ultimate Flutter Image Compression Tool
Simply set a maximum file size, and our smart algorithm instantly delivers images with the smallest size and the highest clarity.
Perfect for profile uploads, gallery images, or bulk processing—make your app faster, lighter, and more professional.
✨ Try it once, and you’ll keep coming back to it.

🚀 Flutter 最佳图片压缩利器
轻松设定图片的最大文件大小，智能算法在瞬间为你输出体积最小、清晰度最高的压缩结果。
无论是上传头像、相册图片，还是海量批量处理，都能让你的应用更快、更省、更专业。
✨ 用过一次，你一定会想再次使用它。

## Compression Principles

本项目的压缩策略以“尽量接近且不超过目标大小”为硬标准，并在稳定性与速度之间取得平衡。核心流程与护栏如下：

1. 边界与护栏

- **目标字节阈值**：KB×1024，并设有下限；当目标 < 10KB 时提升至 10KB，避免平台编解码不稳定。
- **已达标直接返回**：原图体积若 ≤ 目标，直接复制到临时目录返回（不改画质，qualityUsed=100）。

2. 近目标快速路径（nearTargetFactor）

- 当原图体积 ≤ nearTargetFactor× 目标（默认 1.2）时，优先采用高保真快速搜索：
  - **原生快速路径（如可用）**：仅对质量做二分，不缩放尺寸；命中即返回。
  - **单次解码自适应搜索**：在 isolate 中一次解码，在内存里多次尝试；使用更高的最小质量下限 preferredMinQuality（默认 80）尽量保真。
- **早停带**：当结果进入 earlyStopRatio× 目标（默认 95%）的区间，提前结束并返回。

3. 原生快速路径（Android/iOS）

- 不缩放尺寸，只对质量做少次二分（尝试次数有上限），命中即返回。
- 支持 keepExif；但保留 EXIF 会增加体积、降低命中目标概率。

4. 单次解码 + 自适应搜索（isolate）

- 仅解码一次到内存，后续所有质量/尺寸尝试均在内存中完成，避免重复 I/O。
- **两点质量估算**：以质量 85 与 35 进行两次探测，线性估算“质量-体积”关系，得到可能命中的 q\* 并优先尝试其附近值。
- 若估算显示需要过低质量才可达标，则先按估算比缩小长边，再在新尺寸上微调质量。
- **维度候选**：从大到小逐步尝试；每个维度对质量采用二分，并设置每维最大尝试次数（maxAttemptsPerDim）与全局总尝试上限（maxTotalTrials）。
- 始终选择“所有 ≤ 目标 的候选中体积最大者”；进入早停带即提前结束。

5. 纯 Dart 兜底与最终强制收敛

- 若前述路径仍未命中目标：
  - 在更小维度上放宽最低质量（最低至 10）重新搜索；
  - 仍未命中则执行最终强制收敛：以质量=1 并逐步减小长边，直至不超过目标体积。
- 全过程只在最终结果时写盘，其余尝试均在内存中完成。

6. 结果选择策略

- 若有“≤ 目标”的候选，返回其中体积最大者；否则返回整体体积最小者或进入强制收敛确保不超过目标。

7. EXIF 策略

- 默认 keepExif=false 以提高命中率与压缩比；开启后仅对 JPG 在原生路径有效，且不保证方向信息。
- 纯 Dart 路径不保留 EXIF。

8. 并发与性能

- 使用信号量限制并发（按 CPU 核心数自适应，最大 3），避免资源争用与卡顿。
- 计算密集部分放在 isolate 中执行，保持 UI 流畅；只在最终写出时进行磁盘 I/O。

9. 可调参数（默认值）

- initialQuality: 92；minQuality: 40；preferredMinQuality: 80；
- earlyStopRatio: 0.95；nearTargetFactor: 1.2；
- maxAttemptsPerDim: 5；maxTotalTrials: 24；
- format: JPEG；keepExif: false（建议按需开启）。

10. 目标与判断

- 当输出体积 ≤ 目标即视为命中；优先“更接近目标”的结果（更大但不超过）。
- 目标单位：KB；换算为字节参与计算。

11. 方向适配与布局注意

- 界面代码使用 EdgeInsetsDirectional/BorderRadiusDirectional 等以适配 LTR/RTL 双向布局。

## 效果展示

<p align="left">
  <img src="assets/images/demo1.png" width="400">
</p>
