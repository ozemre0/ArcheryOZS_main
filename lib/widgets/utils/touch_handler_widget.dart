import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// Bu widget, dokunmatik ekran girişlerinin daha iyi işlenmesini sağlamak için
/// eklenmiştir. Özellikle Android'de görülen dokunmatik ekran kilitlenme
/// sorunlarını çözmek için tasarlanmıştır.
class TouchHandlerWidget extends StatelessWidget {
  final Widget child;

  // Dokunma sırasında haptic feedback verilsin mi?
  final bool enableHapticFeedback;

  // Hızlı ardışık dokunuşları filtrelemek için minimum süre (ms)
  final int minTouchDebounceMs;

  const TouchHandlerWidget({
    super.key,
    required this.child,
    this.enableHapticFeedback = true,
    this.minTouchDebounceMs = 100, // Varsayılan olarak 100ms
  });

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        // Tap hareketlerini özelleştirilmiş şekilde yöneten recognizer
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          () => TapGestureRecognizer(),
          (TapGestureRecognizer instance) {
            instance.onTapDown = _handleTapDown;
            instance.onTapUp = _handleTapUp;
            instance.onTapCancel = _handleTapCancel;
          },
        ),

        // Sürükleme hareketlerini özelleştirilmiş şekilde yöneten recognizer
        PanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
          () => PanGestureRecognizer(),
          (PanGestureRecognizer instance) {
            instance.onStart = _handlePanStart;
            instance.onUpdate = _handlePanUpdate;
            instance.onEnd = _handlePanEnd;
          },
        ),
      },
      behavior:
          HitTestBehavior.translucent, // Dokunuş olaylarını geçirmeyi sağlar
      child: child,
    );
  }

  // Son dokunuş zamanı - debouncing için kullanılır
  static DateTime? _lastTouchTime;

  void _handleTapDown(TapDownDetails details) {
    final now = DateTime.now();

    // Çok hızlı ardışık dokunuşları filtreleme (debouncing)
    if (_lastTouchTime != null &&
        now.difference(_lastTouchTime!).inMilliseconds < minTouchDebounceMs) {
      return;
    }

    _lastTouchTime = now;

    if (enableHapticFeedback) {
      HapticFeedback.selectionClick();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    // İsterseniz tap up olaylarını özel olarak işleyebilirsiniz
  }

  void _handleTapCancel() {
    // Dokunuş iptal edildiğinde yapılacak işlemler
  }

  void _handlePanStart(DragStartDetails details) {
    // Sürükleme başladığında yapılacak işlemler
    if (enableHapticFeedback) {
      HapticFeedback.lightImpact();
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    // Sürükleme güncellendiğinde yapılacak işlemler
  }

  void _handlePanEnd(DragEndDetails details) {
    // Sürükleme bittiğinde yapılacak işlemler
  }
}

/// Material App'in üst seviyesinde kullanılmak üzere, dokunmatik olayları
/// daha iyi yöneten bir sarmalayıcı widget.
class TouchOptimizedApp extends StatelessWidget {
  final MaterialApp materialApp;

  const TouchOptimizedApp({super.key, required this.materialApp});

  @override
  Widget build(BuildContext context) {
    return TouchHandlerWidget(
      child: materialApp,
    );
  }
}
