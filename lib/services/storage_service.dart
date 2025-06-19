import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import './supabase_config.dart';

class StorageService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  Future<String> uploadProfilePhoto(String userId, dynamic photo) async {
    try {
      String fileName;
      String fileExt;

      // Web platformu için XFile, mobil için File kullanıyoruz
      if (kIsWeb) {
        if (photo is XFile) {
          final name = photo.name;
          fileExt = name.substring(name.lastIndexOf('.') + 1);
          fileName = 'profile_$userId.$fileExt';
        } else {
          throw Exception('Web platformunda geçersiz dosya formatı');
        }
      } else {
        if (photo is File) {
          fileExt = photo.path.split('.').last;
          fileName = 'profile_$userId.$fileExt';
        } else {
          throw Exception('Mobil platformda geçersiz dosya formatı');
        }
      }

      // Önce eski fotoğrafları bul ve sil
      try {
        final List<FileObject> files =
            await _supabase.storage.from('profile_photos').list();

        final existingFiles = files
            .where((file) => file.name.startsWith('profile_$userId.'))
            .toList();

        // Tüm eski dosyaları sil
        for (var file in existingFiles) {
          try {
            await _supabase.storage.from('profile_photos').remove([file.name]);

            // Silme işleminin tamamlanmasını bekle
            await Future.delayed(const Duration(milliseconds: 500));
          } catch (e) {
            print('Eski dosya silinirken hata: ${e.toString()}');
          }
        }
      } catch (e) {
        print('Dosya listesi alınırken hata: ${e.toString()}');
      }

      // Yeni fotoğrafı yükle
      try {
        final fileOptions = FileOptions(
          upsert: true, // Aynı isimde dosya varsa üzerine yaz
          contentType: 'image/${fileExt.toLowerCase()}',
        );

        if (kIsWeb) {
          // Web platformu için, önce XFile'den bytes elde ediyoruz
          if (photo is XFile) {
            final bytes = await photo.readAsBytes();
            await _supabase.storage
                .from('profile_photos')
                .uploadBinary(fileName, bytes, fileOptions: fileOptions);
          }
        } else {
          // Mobil platformlar için normal dosya yükleme
          if (photo is File) {
            await _supabase.storage
                .from('profile_photos')
                .upload(fileName, photo, fileOptions: fileOptions);
          }
        }

        // URL'i al ve döndür
        final String photoUrl =
            _supabase.storage.from('profile_photos').getPublicUrl(fileName);

        return photoUrl;
      } catch (e) {
        throw Exception(
            'Yeni fotoğraf yüklenirken hata oluştu: ${e.toString()}');
      }
    } catch (e) {
      throw Exception('Fotoğraf işlemi sırasında hata oluştu: ${e.toString()}');
    }
  }

  Future<void> deleteProfilePhoto(String photoPath) async {
    try {
      await _supabase.storage.from('profile_photos').remove([photoPath]);
    } catch (e) {
      throw Exception('Fotoğraf silinirken bir hata oluştu: $e');
    }
  }
}
