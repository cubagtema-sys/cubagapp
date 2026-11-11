import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/cubag_design.dart';
import 'app_logo.dart';

/// Shared frame for the signed-out screens (sign in, forgot / reset password):
/// a cocoa header carrying the association's seal with its name and motto set
/// beside it, then a white sheet with the screen's form.
class AuthScaffold extends StatelessWidget {
  final Widget child;

  /// Shows a back arrow in the header (e.g. Forgot password -> Sign in).
  final VoidCallback? onBack;

  const AuthScaffold({super.key, required this.child, this.onBack});

  /// Laptops, desktop browsers (admins sign in here) and iPads in landscape.
  static const wideBreakpoint = 900.0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width >= wideBreakpoint) return _wide(context, size);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: CubagColors.cocoa,
        body: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: size.height),
            // The white sheet always reaches the bottom edge, however short
            // the header or form.
            child: IntrinsicHeight(
              child: Column(
                children: [
                  AuthHeader(onBack: onBack),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: CubagColors.paper,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(CubagRadius.hero),
                        ),
                      ),
                      padding: EdgeInsets.fromLTRB(
                        CubagSpace.lg,
                        CubagSpace.xl,
                        CubagSpace.lg,
                        CubagSpace.xl + MediaQuery.paddingOf(context).bottom,
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension on AuthScaffold {
  /// Two halves: the association on cocoa, the form on white.
  Widget _wide(BuildContext context, Size size) {
    return Scaffold(
      backgroundColor: CubagColors.paper,
      body: Row(
        children: [
          Expanded(
            flex: 5,
            child: ColoredBox(
              color: CubagColors.cocoa,
              child: Stack(
                children: [
                  Positioned(
                    right: -140,
                    bottom: -120,
                    child: IgnorePointer(
                      child: Container(
                        width: 460,
                        height: 460,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: CubagColors.seal.withAlpha(40),
                            width: 48,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(CubagSpace.xxxl + 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: CubagColors.paper,
                            ),
                            padding: const EdgeInsets.all(4),
                            child: const AppLogo(size: 104, borderRadius: 52, showShadow: false),
                          ),
                          const SizedBox(height: CubagSpace.xxl),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: Text(
                              'Customs Brokers Association of Ghana',
                              style: CubagType.display.copyWith(
                                color: CubagColors.onCocoa,
                                fontSize: 40,
                                height: 46 / 40,
                              ),
                            ),
                          ),
                          const SizedBox(height: CubagSpace.sm),
                          Text(
                            'Honesty and Efficiency',
                            style: CubagType.body.copyWith(color: CubagColors.onCocoaMuted),
                          ),
                          const SizedBox(height: CubagSpace.xxl),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Text(
                              'Licences, dues, compliance documents and member '
                              'services for licensed customs brokers, in one place.',
                              style: CubagType.body.copyWith(color: CubagColors.onCocoa),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CubagSpace.xxxl,
                        vertical: CubagSpace.xxxl,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: child,
                      ),
                    ),
                  ),
                  if (onBack != null)
                    Positioned(
                      left: CubagSpace.md,
                      top: CubagSpace.md,
                      child: IconButton(
                        tooltip: 'Back',
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back_rounded),
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

/// Seal on the left; association name (serif) and motto beside it.
class AuthHeader extends StatelessWidget {
  final VoidCallback? onBack;
  const AuthHeader({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    // One line: [back] seal  name / motto — sitting close under the status bar.
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          onBack == null ? CubagSpace.lg : CubagSpace.xs,
          CubagSpace.md,
          CubagSpace.lg,
          CubagSpace.lg,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 456),
            child: Row(
              children: [
                if (onBack != null) ...[
                  IconButton(
                    tooltip: 'Back',
                    onPressed: onBack,
                    color: CubagColors.onCocoa,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: CubagSpace.xxs),
                ],
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: CubagColors.paper,
                  ),
                  padding: const EdgeInsets.all(3),
                  child: const AppLogo(size: 56, borderRadius: 28, showShadow: false),
                ),
                const SizedBox(width: CubagSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // Two balanced lines, never a lone "Ghana".
                        'Customs Brokers\nAssociation of Ghana',
                        semanticsLabel: 'Customs Brokers Association of Ghana',
                        style: CubagType.title.copyWith(
                          color: CubagColors.onCocoa,
                          fontSize: 20,
                          height: 25 / 20,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Honesty and Efficiency',
                        style: CubagType.small.copyWith(color: CubagColors.onCocoaMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Label above a field.
class AuthFieldLabel extends StatelessWidget {
  final String text;
  const AuthFieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: CubagType.label),
  );
}

/// Inline message: error (default) or success.
class AuthNote extends StatelessWidget {
  final String message;
  final bool success;
  const AuthNote({super.key, required this.message, this.success = false});

  @override
  Widget build(BuildContext context) {
    final fg = success ? CubagColors.valid : CubagColors.lapsed;
    final bg = success ? CubagColors.validTint : CubagColors.lapsedTint;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(CubagSpace.sm),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(CubagRadius.control),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              success
                  ? Icons.check_circle_outline_rounded
                  : Icons.error_outline_rounded,
              color: fg,
              size: 20,
            ),
            const SizedBox(width: CubagSpace.xs),
            Expanded(
              child: Text(message, style: CubagType.small.copyWith(color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Password field with a show/hide button whose label follows its state.
class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled;
  final String? hint;
  final Iterable<String> autofillHints;
  final TextInputAction action;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  const PasswordField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.hint,
    this.autofillHints = const [AutofillHints.password],
    this.action = TextInputAction.done,
    this.onSubmitted,
    this.focusNode,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      obscureText: !_show,
      autofillHints: widget.autofillHints,
      textInputAction: widget.action,
      onFieldSubmitted: widget.onSubmitted,
      style: CubagType.body.copyWith(color: CubagColors.ink),
      decoration: InputDecoration(
        hintText: widget.hint,
        suffixIcon: IconButton(
          tooltip: _show ? 'Hide password' : 'Show password',
          icon: Icon(
            _show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          ),
          onPressed: widget.enabled
              ? () => setState(() => _show = !_show)
              : null,
        ),
      ),
    );
  }
}
