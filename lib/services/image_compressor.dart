import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class ImageCompressorResult {
  final File file;
  final int bytes;
  final int qualityUsed;
  final SizeInfo sizeInfo;

  ImageCompressorResult({required this.file, required this.bytes, required this.qualityUsed, required this.sizeInfo});
}

class SizeInfo {
  final int? width;
  final int? height;
  const SizeInfo({this.width, this.height});
}

class ImageCompressorOptions {
  final int targetSizeInKB;
  final int initialQuality;
  final int minQuality;
  final int step;
  final int? maxWidth;
  final int? maxHeight;
  final CompressFormat format;
  final bool keepExif;

  const ImageCompressorOptions({
    required this.targetSizeInKB,
    this.initialQuality = 92,
    this.minQuality = 40,
    this.step = 4,
    this.maxWidth,
    this.maxHeight,
    this.format = CompressFormat.jpeg,
    this.keepExif = true,
  }) : assert(targetSizeInKB > 0),
       assert(initialQuality <= 100 && initialQuality > 0),
       assert(minQuality > 0 && minQuality <= initialQuality),
       assert(step > 0);
}

class ImageCompressorService {
  /// Compress image to target size in KB with iterative quality reduction and optional downscale.
  static Future<ImageCompressorResult> compressToTarget(
    File sourceFile, {
    required ImageCompressorOptions options,
  }) async {
    final int targetBytes = options.targetSizeInKB * 1024;
    // Disable EXIF when target is very small to reduce size and avoid native issues (reserved for native path)
    // Note: current path uses pure Dart; keep variable for future native usage if needed.
    // final bool effectiveKeepExif = options.keepExif && targetBytes >= 300 * 1024;
    // Safety: if provided target is unrealistically small (< 10KB), cap it to 10KB to avoid native crashes
    final int safeTargetBytes = targetBytes < 10 * 1024 ? 10 * 1024 : targetBytes;

    // Fast path: if already <= target, return original copy to temp dir
    final int originalBytes = await sourceFile.length();
    if (originalBytes <= targetBytes) {
      final File copied = await _copyToTemp(sourceFile);
      return ImageCompressorResult(file: copied, bytes: originalBytes, qualityUsed: 100, sizeInfo: const SizeInfo());
    }

    // Use pure-Dart fallback path (image package) with resize candidates.
    // Prefer no-resize first so we can aim for the highest possible quality near the target size.
    final List<int> dimensionCandidates = <int>[
      0,
      3000,
      2048,
      1600,
      1280,
      1024,
      800,
      640,
      480,
      360,
      320,
      256,
      224,
      200,
      180,
      160,
      128,
    ];

    File? globalBestFile; // <= target
    int? globalBestBytes;
    int globalBestQuality = options.initialQuality;

    File? globalSmallestFile; // overall smallest even if > target
    int? globalSmallestBytes;
    int globalSmallestQuality = options.initialQuality;

    final List<File> garbageTrials = <File>[]; // temporary files to clean up
    const int maxTotalTrials = 60; // allow more trials to reach stricter targets reliably
    int totalTrials = 0;

    for (final int dim in dimensionCandidates) {
      int low = options.minQuality;
      int high = options.initialQuality;

      File? localBestFile; // best candidate under target at this dim (closest to target)
      int? localBestBytes;
      int localBestQuality = options.initialQuality;

      while (low <= high) {
        if (totalTrials >= maxTotalTrials) {
          break;
        }
        final int mid = (low + high) >> 1;
        File? trial;
        try {
          trial = await _compressWithDart(sourcePath: sourceFile.path, quality: mid, maxDim: dim);
        } catch (_) {
          trial = null;
        }

        if (trial == null) {
          break;
        }

        final int trialBytes = await trial.length();
        totalTrials++;

        // Track global smallest (also ensure we don't keep more than needed)
        if (globalSmallestBytes == null || trialBytes < globalSmallestBytes) {
          // Old smallest (if not same file) becomes deletable
          if (globalSmallestFile != null && globalSmallestFile.path != trial.path) {
            garbageTrials.add(globalSmallestFile);
          }
          globalSmallestFile = trial;
          globalSmallestBytes = trialBytes;
          globalSmallestQuality = mid;
        } else {
          // Not keeping this trial, mark for deletion later
          garbageTrials.add(trial);
        }

        if (trialBytes <= safeTargetBytes) {
          // Update local best to the largest bytes under target (closest to target)
          if (localBestBytes == null || trialBytes > localBestBytes) {
            if (localBestFile != null && localBestFile.path != trial.path) {
              garbageTrials.add(localBestFile);
            }
            localBestFile = trial;
            localBestBytes = trialBytes;
            localBestQuality = mid;
          } else {
            // Not keeping this trial, mark for deletion later
            garbageTrials.add(trial);
          }
          // Try higher quality while staying under target
          low = mid + 1;
        } else {
          // Too large, reduce quality
          high = mid - 1;
        }
      }

      // Promote local best (closest under target in this dim) to global best
      if (localBestFile != null && localBestBytes != null) {
        if (globalBestBytes == null || localBestBytes > globalBestBytes) {
          if (globalBestFile != null && globalBestFile.path != localBestFile.path) {
            garbageTrials.add(globalBestFile);
          }
          globalBestFile = localBestFile;
          globalBestBytes = localBestBytes;
          globalBestQuality = localBestQuality;
        } else if (localBestFile.path != globalBestFile!.path) {
          // Not keeping this local best
          garbageTrials.add(localBestFile);
        }
      }

      // Early exit: once we reach a good result under target, stop trying smaller dims
      if (globalBestBytes != null && globalBestBytes <= safeTargetBytes) {
        break;
      }
    }

    // Fallback: if nothing under target was found and we still exceed the target,
    // try again with smaller dimensions and lower min quality bound (down to 10).
    if (globalBestBytes == null &&
        globalSmallestBytes != null &&
        globalSmallestBytes > safeTargetBytes &&
        options.minQuality > 10) {
      final List<int> fallbackDims = <int>[360, 320, 256, 224, 200, 180, 160, 128];
      int fallbackTrials = 0;
      const int maxFallbackTrials = 40;
      for (final int dim in fallbackDims) {
        int low = 10;
        int high = options.initialQuality;
        while (low <= high) {
          if (fallbackTrials >= maxFallbackTrials) {
            break;
          }
          final int mid = (low + high) >> 1;
          File? trial;
          try {
            trial = await _compressWithDart(sourcePath: sourceFile.path, quality: mid, maxDim: dim);
          } catch (_) {
            trial = null;
          }
          if (trial == null) {
            break;
          }
          final int trialBytes = await trial.length();
          fallbackTrials++;

          // Track global smallest as well
          if (globalSmallestBytes == null || trialBytes < globalSmallestBytes) {
            if (globalSmallestFile != null && globalSmallestFile.path != trial.path) {
              garbageTrials.add(globalSmallestFile);
            }
            globalSmallestFile = trial;
            globalSmallestBytes = trialBytes;
            globalSmallestQuality = mid;
          } else {
            garbageTrials.add(trial);
          }

          if (trialBytes <= safeTargetBytes) {
            if (globalBestBytes == null || trialBytes > globalBestBytes) {
              if (globalBestFile != null && globalBestFile.path != trial.path) {
                garbageTrials.add(globalBestFile);
              }
              globalBestFile = trial;
              globalBestBytes = trialBytes;
              globalBestQuality = mid;
            }
            // try raising quality while staying under target
            low = mid + 1;
          } else {
            high = mid - 1;
          }
        }

        if (globalBestBytes != null && globalBestBytes <= safeTargetBytes) {
          break;
        }
      }
    }

    // Decide final output
    File chosenFile;
    int chosenBytes;
    int chosenQuality;

    if (globalBestFile != null && globalBestBytes != null) {
      chosenFile = globalBestFile;
      chosenBytes = globalBestBytes;
      chosenQuality = globalBestQuality;
    } else if (globalSmallestFile != null && globalSmallestBytes != null && globalSmallestBytes < originalBytes) {
      chosenFile = globalSmallestFile;
      chosenBytes = globalSmallestBytes;
      chosenQuality = globalSmallestQuality;
    } else {
      // Fallback: original
      chosenFile = sourceFile;
      chosenBytes = originalBytes;
      chosenQuality = 100;
    }

    // Final enforcement: if still above target, force shrink with quality=1 and progressively smaller dims
    if (chosenBytes > safeTargetBytes) {
      final List<int> enforcementDims = <int>[640, 480, 360, 320, 256, 224, 200, 180, 160, 128, 112, 96, 80];
      for (final int dim in enforcementDims) {
        File? trial;
        try {
          trial = await _compressWithDart(sourcePath: sourceFile.path, quality: 1, maxDim: dim);
        } catch (_) {
          trial = null;
        }
        if (trial == null) continue;
        final int trialBytes = await trial.length();
        if (trialBytes <= safeTargetBytes) {
          garbageTrials.add(chosenFile);
          chosenFile = trial;
          chosenBytes = trialBytes;
          chosenQuality = 1;
          break;
        } else {
          garbageTrials.add(trial);
        }
      }
    }

    // Cleanup unused temp files
    for (final File f in garbageTrials) {
      if (f.path != chosenFile.path) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }

    return ImageCompressorResult(
      file: chosenFile,
      bytes: chosenBytes,
      qualityUsed: chosenQuality,
      sizeInfo: const SizeInfo(),
    );
  }

  // Keeping native path implementation removed to avoid crashes. If needed in future, re-introduce with guards.

  // Pure Dart JPEG compressor using image package in an Isolate
  static Future<File?> _compressWithDart({
    required String sourcePath,
    required int quality,
    required int maxDim,
  }) async {
    final Uint8List? bytes = await Isolate.run<Uint8List?>(() {
      try {
        final Uint8List data = File(sourcePath).readAsBytesSync();
        final img.Image? decoded = img.decodeImage(data);
        if (decoded == null) return null;

        img.Image image = decoded;
        if (maxDim > 0) {
          final int w = image.width;
          final int h = image.height;
          final int maxSide = maxDim;
          final double scale = w > h ? maxSide / w : maxSide / h;
          if (scale < 1.0) {
            final int nw = (w * scale).floor();
            final int nh = (h * scale).floor();
            image = img.copyResize(image, width: nw, height: nh, interpolation: img.Interpolation.linear);
          }
        }

        final List<int> out = img.encodeJpg(image, quality: quality);
        return Uint8List.fromList(out);
      } catch (_) {
        return null;
      }
    });

    if (bytes == null) return null;
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String targetPath = '${tempDir.path}/fic_dart_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final File f = File(targetPath);
      await f.writeAsBytes(bytes);
      return f;
    } catch (_) {
      return null;
    }
  }

  static Future<File> _copyToTemp(File file) async {
    final Directory tempDir = await getTemporaryDirectory();
    final String filename = 'orig_${DateTime.now().microsecondsSinceEpoch}_${file.uri.pathSegments.last}';
    final File dest = File('${tempDir.path}/$filename');
    return file.copy(dest.path);
  }

  // Helper kept if needed in future; currently unused.
  // static Future<Uint8List> readBytes(File file) async {
  //   return await file.readAsBytes();
  // }
}
