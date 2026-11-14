import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps the member screens (the bottom bar itself lives in AppLayout).
///
/// When the member moves to another section, the new screen eases in
/// (a short fade and a 6 px rise) and the phone gives a light selection
/// tick. The shell's navigators are not duplicated, so each section keeps
/// its scroll position and state.
class UserShell extends StatefulWidget {
  final Widget child;

  /// The current section (StatefulNavigationShell.currentIndex).
  final int index;
  const UserShell({super.key, required this.child, this.index = 0});

  @override
  State<UserShell> createState() => _UserShellState();
}

class _UserShellState extends State<UserShell> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );
  late final Animation<double> _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void didUpdateWidget(UserShell old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      HapticFeedback.selectionClick();
      // Respect "reduce motion".
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: 0.35 + 0.65 * _curve.value,
        child: Transform.translate(offset: Offset(0, 6 * (1 - _curve.value)), child: child),
      ),
    );
  }
}
