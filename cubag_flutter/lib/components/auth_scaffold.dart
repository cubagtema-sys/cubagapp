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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
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

/// Seal on the left; association name (serif) and motto beside it.
class AuthHeader extends StatelessWidget {
  final VoidCallback? onBack;
  const AuthHeader({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          CubagSpace.lg,
          onBack == null ? CubagSpace.xxl : CubagSpace.xs,
          CubagSpace.lg,
          CubagSpace.xl,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (onBack != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: CubagSpace.xs),
                    child: IconButton(
                      tooltip: 'Back',
                      onPressed: onBack,
                      style: IconButton.styleFrom(
                        foregroundColor: CubagColors.onCocoa,
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft,
                      ),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                Row(
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: CubagColors.paper,
                      ),
                      padding: const EdgeInsets.all(3),
                      child: const AppLogo(
                        size: 64,
                        borderRadius: 32,
                        showShadow: false,
                      ),
                    ),
                    const SizedBox(width: CubagSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            // Two balanced lines, never a lone "Ghana".
                            'Customs Brokers\nAssociation of Ghana',
                            semanticsLabel:
                                'Customs Brokers Association of Ghana',
                            style: CubagType.title.copyWith(
                              color: CubagColors.onCocoa,
                              fontSize: 22,
                              height: 27 / 22,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Honesty and Efficiency',
                            style: CubagType.small.copyWith(
                              color: CubagColors.onCocoaMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
