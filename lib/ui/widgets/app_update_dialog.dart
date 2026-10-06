import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sborapps/core/services/app_update_service.dart';

class AppUpdateDialog extends StatefulWidget {
  final AppUpdate update;

  const AppUpdateDialog({super.key, required this.update});

  static Future<void> show(BuildContext context, AppUpdate update) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AppUpdateDialog(update: update),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  late AppUpdate _update = widget.update;
  File? _file;
  bool _busy = false;
  int _percent = 0;
  String? _error;

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_file == null) {
        final fresh = await AppUpdateService.check();
        if (fresh == null) {
          if (mounted) Navigator.of(context).pop();
          return;
        }
        _update = fresh;
        if (mounted) setState(() => _percent = 0);
        _file = await AppUpdateService.download(_update, onProgress: _onProgress);
      }
      await AppUpdateService.install(_file!);
    } catch (e) {
      _file = null;
      _error = _errorText(e);
    }

    if (mounted) setState(() => _busy = false);
  }

  void _onProgress(double progress) {
    final percent = (progress * 100).clamp(0, 100).floor();
    if (mounted && percent != _percent) setState(() => _percent = percent);
  }

  String _errorText(Object e) {
    if (e is AppUpdateException) return e.message;
    if (e is SocketException || e is http.ClientException) {
      return 'Нет подключения к интернету. Проверьте сеть и повторите.';
    }
    if (e is TimeoutException) return 'Сервер не отвечает. Повторите попытку.';
    return 'Не удалось загрузить обновление. Повторите попытку.';
  }

  String _formatSize(int bytes) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} МБ';
  }

  @override
  Widget build(BuildContext context) {
    final downloaded = _file != null;
    final version = _update.versionName.isEmpty ? '' : ' ${_update.versionName}';

    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: Icon(Icons.system_update, size: 40, color: Colors.blue[600]),
        title: const Text('Доступно обновление'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Вышла новая версия$version. Чтобы продолжить работу, установите её.'),
            if (_update.size > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Размер: ${_formatSize(_update.size)}',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
            if (_busy && !downloaded) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _percent > 0 ? _percent / 100 : null),
              const SizedBox(height: 8),
              Text('Загрузка… $_percent%'),
            ],
            if (!_busy && downloaded) ...[
              const SizedBox(height: 16),
              const Text(
                'В окне Android нажмите «Установить». '
                'Если окно закрылось, нажмите кнопку ещё раз.',
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: Colors.red[700])),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
            ),
            onPressed: _busy ? null : _start,
            child: Text(
              _error != null
                  ? 'Повторить'
                  : downloaded
                      ? 'Установить'
                      : 'Обновить',
            ),
          ),
        ],
      ),
    );
  }
}
