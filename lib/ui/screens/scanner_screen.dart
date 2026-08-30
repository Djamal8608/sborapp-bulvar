import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerScreen extends StatefulWidget {
  final String title;

  final Future<ScanFeedback> Function(String barcode) onScan;

  const ScannerScreen({
    super.key,
    required this.title,
    required this.onScan,
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class ScanFeedback {
  final bool ok;
  final String text;

  const ScanFeedback({required this.ok, required this.text});
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();

  bool _busy = false;
  String? _lastBarcode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  ScanFeedback? _feedback;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;

    final code = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    final now = DateTime.now();
    if (code == _lastBarcode && now.difference(_lastAt).inMilliseconds < 2000) {
      return;
    }

    _lastBarcode = code;
    _lastAt = now;
    setState(() => _busy = true);

    try {
      final result = await widget.onScan(code);
      if (!mounted) return;
      setState(() => _feedback = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _feedback = ScanFeedback(ok: false, text: 'Ошибка: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fb = _feedback;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.flashlight_on),
            tooltip: 'Подсветка',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),

          Center(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          if (_busy)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 3),
            ),

          if (fb != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                width: double.infinity,
                color: fb.ok ? Colors.green.shade700 : Colors.red.shade700,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                child: Row(
                  children: [
                    Icon(
                      fb.ok ? Icons.check_circle : Icons.error,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        fb.text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}