import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'oa_theme.dart';

/// Kamerayla QR kod ya da barkod okur; bulunan metni geri döndürür.
class QrPage extends StatefulWidget {
  const QrPage({super.key});

  @override
  State<QrPage> createState() => _QrPageState();
}

class _QrPageState extends State<QrPage> {
  // formats boş: bütün QR ve barkod türleri okunur.
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && v.trim().isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(v.trim());
        return;
      }
    }
  }

  /// Kamera ya da okuyucu hatası: genel mesaj yerine ne olduğunu Türkçe söyler,
  /// altında da teknik ayrıntıyı gösterir (sorunu bulmak için).
  Widget _error(MobileScannerException e) {
    final text = switch (e.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Kamera izni verilmedi. Telefonun Ayarlar → Uygulamalar → Pusula → İzinler bölümünden kamerayı aç.',
      MobileScannerErrorCode.unsupported => 'Bu telefonda kamerayla kod okuma desteklenmiyor.',
      _ => 'Kamera açıldı ama kod okuyucu başlatılamadı.',
    };
    final detail = [e.errorCode.name, e.errorDetails?.code, e.errorDetails?.message]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' · ');
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 36),
              const SizedBox(height: 14),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5)),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectableText(detail,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _error(error),
          ),
          // Hedef çerçevesi
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: OAColors.amber, width: 3),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Kapat',
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Fener',
                        icon: const Icon(Icons.flashlight_on_outlined, color: Colors.white),
                        onPressed: () => _controller.toggleTorch(),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('QR kodu ya da barkodu çerçeveye getir.\nKamera açılmazsa Ayarlar\'dan kamera iznini ver.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 15)),
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
