import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/cubag_design.dart';
import '../services/api_service.dart';

/// App-wide notice shown while the CUBAG server cannot be reached. Screens
/// keep showing what they last loaded; this says so, once, at the top.
class OfflineNotice extends StatefulWidget {
  final Widget child;
  const OfflineNotice({super.key, required this.child});

  @override
  State<OfflineNotice> createState() => _OfflineNoticeState();
}

class _OfflineNoticeState extends State<OfflineNotice> {
  bool _checking = false;

  Future<void> _retry() async {
    setState(() => _checking = true);
    try {
      await ApiService().get('/health');
    } catch (_) {
      // Still offline; the notice stays.
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ApiService.offline,
      builder: (context, isOffline, _) {
        if (!isOffline) return widget.child;
        final topInset = MediaQuery.paddingOf(context).top;
        return Column(
          children: [
            AnnotatedRegion<SystemUiOverlayStyle>(
              // Light status-bar icons on the dark notice.
              value: SystemUiOverlayStyle.light,
              child: Material(
                color: CubagColors.ink,
                child: Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      CubagSpace.md,
                      topInset + 6,
                      CubagSpace.xs,
                      6,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.cloud_off_rounded,
                          size: 18,
                          color: CubagColors.onCocoaMuted,
                        ),
                        const SizedBox(width: CubagSpace.sm),
                        Expanded(
                          child: Text(
                            'No connection. You are seeing saved information.',
                            style: CubagType.small.copyWith(
                              color: CubagColors.onCocoa,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _checking ? null : _retry,
                          style: TextButton.styleFrom(
                            foregroundColor: CubagColors.onCocoa,
                          ),
                          child: Text(_checking ? 'Checking…' : 'Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: widget.child,
              ),
            ),
          ],
        );
      },
    );
  }
}
