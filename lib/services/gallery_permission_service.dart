import 'dart:io';



import 'package:permission_handler/permission_handler.dart';

import 'package:photo_manager/photo_manager.dart';



enum GalleryAccessResult {

  granted,

  denied,

  permanentlyDenied,

}



/// 갤러리(사진) 읽기 권한을 요청한다.

class GalleryPermissionService {

  GalleryPermissionService._();



  static const _photoManagerOption = PermissionRequestOption(

    androidPermission: AndroidPermission(

      type: RequestType.image,

      mediaLocation: false,

    ),

  );



  static Future<GalleryAccessResult> ensurePhotoAccess() async {

    var state = await PhotoManager.requestPermissionExtend(

      requestOption: _photoManagerOption,

    );

    if (state.hasAccess) {

      return GalleryAccessResult.granted;

    }



    if (Platform.isAndroid || Platform.isIOS) {

      final platformGranted = await _requestPlatformPermission();

      if (platformGranted) {

        state = await PhotoManager.requestPermissionExtend(

          requestOption: _photoManagerOption,

        );

        if (state.hasAccess) {

          return GalleryAccessResult.granted;

        }

      }



      if (await _isPermanentlyDenied()) {

        return GalleryAccessResult.permanentlyDenied;

      }

    }



    return GalleryAccessResult.denied;

  }



  static Future<bool> _requestPlatformPermission() async {

    if (Platform.isAndroid) {

      var photos = await Permission.photos.status;

      if (!photos.isGranted && !photos.isLimited) {

        photos = await Permission.photos.request();

      }

      if (photos.isGranted || photos.isLimited) {

        return true;

      }



      var storage = await Permission.storage.status;

      if (!storage.isGranted) {

        storage = await Permission.storage.request();

      }

      return storage.isGranted;

    }



    if (Platform.isIOS) {

      var photos = await Permission.photos.status;

      if (!photos.isGranted && !photos.isLimited) {

        photos = await Permission.photos.request();

      }

      return photos.isGranted || photos.isLimited;

    }



    return true;

  }



  static Future<bool> _isPermanentlyDenied() async {

    if (Platform.isAndroid) {

      final photosStatus = await Permission.photos.status;

      if (photosStatus.isPermanentlyDenied) {

        return true;

      }

      final storageStatus = await Permission.storage.status;

      return storageStatus.isPermanentlyDenied;

    }



    if (Platform.isIOS) {

      return (await Permission.photos.status).isPermanentlyDenied;

    }



    return false;

  }

}


