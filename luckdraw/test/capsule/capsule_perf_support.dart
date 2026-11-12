import 'package:luckdraw/capsule.dart';
import 'package:luckdraw/extend.dart';

/// 为既有矢量几何基线显式选择 Picture，保留其它 surface 输入。
LuckySurfaceData<CapsuleConfig, CapsuleLayout,
    CapsuleFrame> capsulePictureSurface(
        LuckySurfaceData<CapsuleConfig, CapsuleLayout, CapsuleFrame> data) =>
    LuckySurfaceData(
        config: data.config,
        layout: data.layout,
        layoutGeneration: data.layoutGeneration,
        frame: data.frame,
        frameListenable: data.frameListenable,
        images: data.images,
        imagesListenable: data.imagesListenable,
        layers: data.layers,
        hooks: data.hooks,
        devicePixelRatio: data.devicePixelRatio,
        textScale: data.textScale,
        textDirection: data.textDirection,
        performance:
            data.performance.copyWith(cacheMode: LuckyCacheMode.picture),
        isAnimating: data.isAnimating);
