import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

/// Порог протяга для закрытия: страница закрывается, если её увели больше чем
/// на (1 - _kCloseThreshold) экрана. 0.7 → достаточно ~30% (в стандартном
/// SwipeablePageRoute было 0.5, т.е. половина — слишком длинный свайп).
const double _kCloseThreshold = 0.7;

/// Скорость флика (ширин экрана/сек), при которой закрываем даже коротким
/// движением. В оригинале было 1.0 — слишком резкий флик требовался.
const double _kMinFlingVelocity = 0.4;

/// Полноэкранный follow-свайп «назад» (едет за пальцем), но с более низким
/// порогом закрытия, чем у пакета swipeable_page_route — короткий свайп вправо
/// уже закрывает экран (как в Telegram). Свайп ВЛЕВО не перехватывается —
/// уходит на свайп-ответ по сообщению.
class SwipeBackPageRoute<T> extends CupertinoPageRoute<T> {
  SwipeBackPageRoute({required super.builder, super.settings});

  bool get _popGestureInProgress => navigator?.userGestureInProgress ?? false;

  bool get _popGestureEnabled {
    if (isFirst) return false;
    if (willHandlePopInternally) return false;
    if (popDisposition == RoutePopDisposition.doNotPop) return false;
    if (fullscreenDialog) return false;
    if (animation?.status != AnimationStatus.completed) return false;
    if (secondaryAnimation?.status != AnimationStatus.dismissed) return false;
    if (_popGestureInProgress) return false;
    return true;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Widget wrapped = fullscreenDialog
        ? child
        : _BackGestureDetector<T>(
            enabledCallback: () => _popGestureEnabled,
            onStartPopGesture: () => _BackGestureController<T>(
              navigator: navigator!,
              controller: controller!,
            ),
            child: child,
          );
    return CupertinoPageTransition(
      primaryRouteAnimation: animation,
      secondaryRouteAnimation: secondaryAnimation,
      linearTransition: _popGestureInProgress,
      child: wrapped,
    );
  }
}

// Максимальные длительности доводящих анимаций (как в оригинале).
const int _kMaxDroppedSwipePageForwardAnimationTime = 800; // мс
const int _kMaxPageBackAnimationTime = 300; // мс

class _BackGestureDetector<T> extends StatefulWidget {
  const _BackGestureDetector({
    required this.enabledCallback,
    required this.onStartPopGesture,
    required this.child,
  });

  final ValueGetter<bool> enabledCallback;
  final ValueGetter<_BackGestureController<T>> onStartPopGesture;
  final Widget child;

  @override
  State<_BackGestureDetector<T>> createState() =>
      _BackGestureDetectorState<T>();
}

class _BackGestureDetectorState<T> extends State<_BackGestureDetector<T>> {
  _BackGestureController<T>? _controller;

  @override
  Widget build(BuildContext context) {
    final gestureDetector = RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _RightwardDragRecognizer:
            GestureRecognizerFactoryWithHandlers<_RightwardDragRecognizer>(
          () => _RightwardDragRecognizer(
            debugOwner: this,
            enabledCallback: widget.enabledCallback,
            startedCallback: () => _controller != null,
          ),
          (r) => r
            ..onStart = _handleStart
            ..onUpdate = _handleUpdate
            ..onEnd = _handleEnd
            ..onCancel = _handleCancel,
        ),
      },
    );
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(child: gestureDetector),
      ],
    );
  }

  double get _width => context.size?.width ?? 1;

  void _handleStart(DragStartDetails _) {
    _controller = widget.onStartPopGesture();
  }

  void _handleUpdate(DragUpdateDetails d) {
    _controller?.dragUpdate((d.primaryDelta ?? 0) / _width);
  }

  void _handleEnd(DragEndDetails d) {
    _controller?.dragEnd(d.velocity.pixelsPerSecond.dx / _width);
    _controller = null;
  }

  void _handleCancel() {
    _controller?.dragEnd(0);
    _controller = null;
  }
}

class _BackGestureController<T> {
  _BackGestureController({required this.navigator, required this.controller}) {
    navigator.didStartUserGesture();
  }

  final AnimationController controller;
  final NavigatorState navigator;

  /// Палец сдвинулся на [delta] (доля ширины экрана). value: 1 = на экране,
  /// 0 = уехал; движение вправо уменьшает value.
  void dragUpdate(double delta) {
    controller.value -= delta;
  }

  void dragEnd(double velocity) {
    const Curve curve = Curves.fastLinearToSlowEaseIn;
    // snapBack == true → возвращаем страницу на место (НЕ закрываем).
    final bool snapBack;
    if (velocity.abs() >= _kMinFlingVelocity) {
      snapBack = velocity <= 0; // флик вправо (velocity>0) → закрыть.
    } else {
      snapBack = controller.value > _kCloseThreshold;
    }

    if (snapBack) {
      final t = math.min(
        lerpDouble(_kMaxDroppedSwipePageForwardAnimationTime, 0,
                controller.value)!
            .floor(),
        _kMaxPageBackAnimationTime,
      );
      unawaited(controller.animateTo(1,
          duration: Duration(milliseconds: t), curve: curve));
    } else {
      navigator.pop();
      if (controller.isAnimating) {
        final t = lerpDouble(
                0, _kMaxDroppedSwipePageForwardAnimationTime, controller.value)!
            .floor();
        unawaited(controller.animateBack(0,
            duration: Duration(milliseconds: t), curve: curve));
      }
    }

    if (controller.isAnimating) {
      late AnimationStatusListener cb;
      cb = (_) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(cb);
      };
      controller.addStatusListener(cb);
    } else {
      navigator.didStopUserGesture();
    }
  }
}

/// Ловит только движение ВПРАВО (back). Влево отдаём другим распознавателям
/// (свайп-ответ по сообщению).
class _RightwardDragRecognizer extends HorizontalDragGestureRecognizer {
  _RightwardDragRecognizer({
    required this.enabledCallback,
    required this.startedCallback,
    super.debugOwner,
  });

  final ValueGetter<bool> enabledCallback;
  final ValueGetter<bool> startedCallback;

  @override
  void handleEvent(PointerEvent event) {
    if (_shouldHandle(event)) {
      super.handleEvent(event);
    } else {
      stopTrackingPointer(event.pointer);
    }
  }

  bool _shouldHandle(PointerEvent event) {
    if (startedCallback()) return true;
    if (!enabledCallback()) return false;
    // Разрешаем только вправо (dx >= 0). Влево — не наш жест.
    return event.delta.dx >= 0;
  }
}
