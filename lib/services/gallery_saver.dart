import 'dart:io';

import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:photo_manager/photo_manager.dart';

class GallerySaverService {
  /// Save an image file to user's photo gallery.
  /// Returns true on success.
  static Future<bool> saveImageFile(File file, {String? name}) async {
    try {
      // Request photo library permission before saving
      final PermissionState state = await PhotoManager.requestPermissionExtend();
      if (!state.isAuth) {
        // Try to open settings if permanently denied
        await PhotoManager.openSetting();
        return false;
      }

      final dynamic result = await ImageGallerySaver.saveFile(file.path, isReturnPathOfIOS: true, name: name);
      if (result is Map) {
        final dynamic ok = result['isSuccess'];
        final dynamic path = result['filePath'] ?? result['fileUri'] ?? result['savedPath'];
        if (ok == true || ok == 1) return true;
        if (path is String && path.isNotEmpty) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
