import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Custom ScrollBehavior that enables smooth mouse dragging and touch interactions
/// across both desktop and mobile platforms.
class ContinuousRtlScrollBehavior extends MaterialScrollBehavior {
  const ContinuousRtlScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

/// A smooth, continuous Right-to-Left (RTL) scrolling container designed for filter bars and chip lists.
/// - Continuously moves content smoothly from right to left (RTL direction).
/// - Allows manual touch/mouse drag on desktop and mobile.
/// - Automatically pauses on hover or user interaction, then smoothly resumes.
/// - Preserves exact child styling, spacing, and click responsiveness.
class ContinuousRtlScrollView extends StatefulWidget {
  final List<Widget> children;
  final double pixelsPerSecond;
  final Duration pauseAtExtremes;
  final Duration resumeDelay;

  const ContinuousRtlScrollView({
    super.key,
    required this.children,
    this.pixelsPerSecond = 32.0,
    this.pauseAtExtremes = const Duration(milliseconds: 2200),
    this.resumeDelay = const Duration(milliseconds: 1800),
  });

  @override
  State<ContinuousRtlScrollView> createState() => _ContinuousRtlScrollViewState();
}

class _ContinuousRtlScrollViewState extends State<ContinuousRtlScrollView>
    with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  late final Ticker _ticker;

  Duration _lastElapsed = Duration.zero;
  bool _isUserInteracting = false;
  bool _isHovered = false;
  bool _isPausedAtExtreme = false;
  Timer? _resumeTimer;
  Timer? _extremePauseTimer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _ticker = createTicker(_handleTick);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        if (_scrollController.position.maxScrollExtent > 0) {
          _ticker.start();
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant ContinuousRtlScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        if (_scrollController.position.maxScrollExtent > 0 && !_ticker.isActive) {
          _ticker.start();
        }
      }
    });
  }

  void _handleTick(Duration elapsed) {
    if (!mounted || !_scrollController.hasClients) return;

    final dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;

    if (dt <= 0 || dt > 0.1) return;

    if (_isUserInteracting || _isHovered || _isPausedAtExtreme) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    final currentOffset = _scrollController.offset;
    final nextOffset = currentOffset + (widget.pixelsPerSecond * dt);

    if (nextOffset >= maxScroll) {
      _scrollController.jumpTo(maxScroll);
      _handleReachedEnd(maxScroll);
    } else {
      _scrollController.jumpTo(nextOffset);
    }
  }

  void _handleReachedEnd(double maxScroll) {
    _isPausedAtExtreme = true;
    _extremePauseTimer?.cancel();

    _extremePauseTimer = Timer(widget.pauseAtExtremes, () {
      if (!mounted || !_scrollController.hasClients) return;

      _scrollController
          .animateTo(
        0.0,
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeInOutCubic,
      )
          .then((_) {
        if (!mounted) return;
        _extremePauseTimer = Timer(widget.pauseAtExtremes, () {
          if (mounted) {
            setState(() {
              _isPausedAtExtreme = false;
            });
          }
        });
      });
    });
  }

  void _onHover(bool isHovered) {
    if (_isHovered == isHovered) return;
    setState(() {
      _isHovered = isHovered;
    });

    if (!isHovered) {
      _resumeTimer?.cancel();
      _resumeTimer = Timer(widget.resumeDelay, () {
        if (mounted) {
          setState(() => _isHovered = false);
        }
      });
    }
  }

  void _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _resumeTimer?.cancel();
      _extremePauseTimer?.cancel();
      setState(() {
        _isUserInteracting = true;
        _isPausedAtExtreme = false;
      });
    } else if (notification is ScrollEndNotification) {
      _resumeTimer?.cancel();
      _resumeTimer = Timer(widget.resumeDelay, () {
        if (mounted) {
          setState(() {
            _isUserInteracting = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _extremePauseTimer?.cancel();
    _ticker.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _onHover(true),
      onExit: (_) => _onHover(false),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _onScrollNotification(notification);
          return false;
        },
        child: ScrollConfiguration(
          behavior: const ContinuousRtlScrollBehavior(),
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: widget.children,
            ),
          ),
        ),
      ),
    );
  }
}
