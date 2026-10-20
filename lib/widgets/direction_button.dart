import 'package:flutter/material.dart';

class DirectionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String command;
  final bool isStopButton;
  final Function(String, String) onCommandStart;
  final Function() onCommandEnd;
  final bool isEnabled;

  const DirectionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.command,
    required this.onCommandStart,
    required this.onCommandEnd,
    this.isStopButton = false,
    this.isEnabled = true,
  });

  @override
  State<DirectionButton> createState() => _DirectionButtonState();
}

class _DirectionButtonState extends State<DirectionButton> {
  // Butona basılı tutan parmaklar: iki parmakla basılırsa ilki kalkınca araç durmasın.
  final Set<int> _activePointers = {};

  bool get _isPressed => _activePointers.isNotEmpty;

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.isEnabled) return;
    final wasPressed = _isPressed;
    setState(() => _activePointers.add(event.pointer));
    if (!wasPressed) {
      widget.onCommandStart(widget.command, widget.label);
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    // Buton basılıyken ekran kapanırsa (ör. sekme değişti) parmağın kalkma olayı yine de
    // buraya ulaşıyor; aracı durdurmayı o durumda kontrol ekranının dispose()'u yapıyor.
    if (!mounted || !_activePointers.contains(event.pointer)) return;
    setState(() => _activePointers.remove(event.pointer));
    // Eğer bu buton dur butonu değilse, son parmak çekildiğinde stop komutu gitsin.
    // Bu arada bağlantı kopmuş olsa bile çağrılır ki yön, aktif yönlerden çıkarılsın.
    if (!_isPressed && !widget.isStopButton) {
      widget.onCommandEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final buttonColor = widget.isStopButton ? Colors.red.shade700 : colorScheme.primary;
    final pressedColor = widget.isStopButton ? Colors.red.shade900 : colorScheme.primaryContainer;

    // GestureDetector yerine ham dokunuş olayları: dokunuş tanıyıcı parmak 18 px kayınca
    // dokunuşu iptal sayıyordu ve araç sürüş sırasında kendiliğinden duruyordu.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: _isPressed ? pressedColor : buttonColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            if (!_isPressed && widget.isEnabled)
              BoxShadow(
                color: buttonColor.withValues(alpha: 0.5),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Opacity(
          opacity: widget.isEnabled ? 1.0 : 0.5,
          // Küçük ekranlarda buton küçülünce ikon ve yazı taşmasın, orantılı küçülsün.
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.icon,
                      size: widget.isStopButton ? 56 : 48,
                      color: _isPressed ? colorScheme.onPrimaryContainer : colorScheme.onPrimary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: _isPressed ? colorScheme.onPrimaryContainer : colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
