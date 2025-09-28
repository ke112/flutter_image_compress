import 'dart:io';

import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:photo_manager/photo_manager.dart';

class GallerySaverService {
  /// Save an image file to user's photo gallery.
  /// Returns true on success.
  static Future<bool> saveImageFile(File file, {String? name}) async {
    try {
      if (Platform.isIOS) {
        // iOS: must request Photos permission before saving
        final PermissionState state = await PhotoManager.requestPermissionExtend();
        if (!state.isAuth) {
          await PhotoManager.openSetting();
          return false;
        }
        return await _saveToGallery(file, name: name);
      }

      if (Platform.isAndroid) {
        // Android: request media permission
        final PermissionState state = await PhotoManager.requestPermissionExtend();
        if (state.isAuth) {
          if (await _saveToGallery(file, name: name)) return true;
        } else {
          // User denied; offer to open Settings
          await PhotoManager.openSetting();
        }
        return false;
      }

      // Other platforms: best effort
      return await _saveToGallery(file, name: name);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _saveToGallery(File file, {String? name}) async {
    final dynamic result = await ImageGallerySaver.saveFile(file.path, isReturnPathOfIOS: true, name: name);
    if (result is Map) {
      final dynamic ok = result['isSuccess'];
      final dynamic path = result['filePath'] ?? result['fileUri'] ?? result['savedPath'];
      if (ok == true || ok == 1) return true;
      if (path is String && path.isNotEmpty) return true;
    }
    return false;
  }
}
