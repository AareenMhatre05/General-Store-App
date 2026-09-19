import 'package:flutter/material.dart';

/// Text that scrolls steadily from right to left.
///
/// Hand-rolled rather than pulled from a package: it is one animation
/// controller and a transform, and every Android dependency in this
/// project has cost a build fight at some point.
///
/// Speed is expressed in logical pixels per second so a long message and
/// a short one move at the same visible pace — a duration-based version
/// makes long text sprint and short text crawl.
class MarqueeText extends StatefulWidget {
  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.pixelsPerSecond = 40,
    this.gap = 64,
  });

  final String text;
  final TextStyle? style;
  final double pixelsPerSecond;

  /// Blank space between the end of one pass and the start of the next,
  /// so the message does not read as one run-on sentence.
  final double gap;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Duration is set once the text width is known, in build.
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();
        final textWidth = painter.width;
        final travel = textWidth + widget.gap;

        final seconds = travel / widget.pixelsPerSecond;
        final duration = Duration(milliseconds: (seconds * 1000).round());
        if (_controller.duration != duration) {
          _controller
            ..duration = duration
            ..repeat();
        }

        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final offset = -_controller.value * travel;
              // Each copy is Positioned with an explicit width equal to
              // the text's measured width. Without that, the Stack hands
              // down the *visible* width as a constraint and the Text is
              // laid out to fit it -- which clips the message mid-word,
              // however far it has scrolled.
              Widget copy(double left) => Positioned(
                    left: left,
                    top: 0,
                    bottom: 0,
                    width: textWidth,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.text,
                        style: style,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                  );

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Two copies a full travel apart: as one leaves, the
                  // next is already arriving, so the loop has no gap.
                  copy(offset + constraints.maxWidth),
                  copy(offset + constraints.maxWidth - travel),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
