import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:sborapps/core/services/admin_auth_service.dart';
import 'package:sborapps/core/services/app_config.dart';

class AppUpdate {
  final int versionCode;
  final String versionName;
  final int size;

  const AppUpdate({
    required this.versionCode,
    required this.versionName,
    required this.size,
  });

  factory AppUpdate.fromJson(Map<String, dynamic> json) => AppUpdate(
        versionCode: int.tryParse('${json['version_code']}') ?? 0,
        versionName: json['version_name']?.toString() ?? '',
        size: int.tryParse('${json['size']}') ?? 0,
      );
}

class AppUpdateException implements Exception {
  final String message;

  const AppUpdateException(this.message);

  @override
  String toString() => message;
}

class AppUpdateService {
  AppUpdateService._();

  static const MethodChannel _channel = MethodChannel('sborapps/app_update');
  static const Duration _timeout = Duration(seconds: 30);

  static String get _url => '${AppConfig.apiBaseUrl}/app_update.php';

  static bool get isSupported => kReleaseMode && !kIsWeb && Platform.isAndroid;

  static Future<AppUpdate?> check() async {
    if (!isSupported) return null;

    final token = await AdminAuthService.getToken();
    if (token == null) return null;

    final response = await http.get(
      Uri.parse('$_url?action=check'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(_timeout);
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> || data['available'] != true) return null;

    final update = AppUpdate.fromJson(data);
    final current = await _channel.invokeMethod<int>('versionCode') ?? 0;
    return update.versionCode > current ? update : null;
  }

  static Future<File> download(
    AppUpdate update, {
    required void Function(double progress) onProgress,
  }) async {
    final token = await AdminAuthService.getToken();
    if (token == null) {
      throw const AppUpdateException('Войдите в приложение заново');
    }

    final dirPath = await _channel.invokeMethod<String>('updatesDir');
    if (dirPath == null) {
      throw const AppUpdateException('Нет доступа к памяти телефона');
    }

    final dir = Directory(dirPath);
    final file = File('${dir.path}/sborapps-${update.versionCode}.apk');
    if (await file.exists() && await file.length() == update.size) {
      onProgress(1);
      return file;
    }

    await for (final entity in dir.list()) {
      if (entity is File) await entity.delete();
    }

    final part = File('${file.path}.part');
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse('$_url?action=download'))
        ..headers['Authorization'] = 'Bearer $token';
      final response = await client.send(request).timeout(_timeout);
      if (response.statusCode != 200) {
        throw AppUpdateException(
          'Сервер не отдал обновление (${response.statusCode})',
        );
      }

      final total = response.contentLength ?? update.size;
      var received = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in response.stream.timeout(_timeout)) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress(received / total);
        }
      } finally {
        await sink.close();
      }

      if (update.size > 0 && received != update.size) {
        throw const AppUpdateException('Файл загрузился не полностью');
      }

      return await part.rename(file.path);
    } finally {
      client.close();
    }
  }

  static Future<void> install(File file) async {
    await _channel.invokeMethod('install', {'path': file.path});
  }
}
