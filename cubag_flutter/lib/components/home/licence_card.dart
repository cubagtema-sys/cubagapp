import 'package:flutter/material.dart';

import '../../design/cubag_design.dart';
import '../app_logo.dart';
import 'licence_status.dart';

/// The member's licence, presented as the official document it is: the one
/// strong surface on Home. Name in the serif, numbers in even figures, a
/// status pill, a slim bar for how much of the licence year is left, and at
/// most one action.
class LicenceCard extends StatelessWidget {
  final String name;
  final String? company;
  final String? licenceNumber;
  final DateTime? expiry;
  final LicenceStatus status;
  final VoidCallback? onAction;
  final VoidCallback? onOpen;

  const LicenceCard({
    super.key,
    required this.name,
    required this.status,
    this.company,
    this.licenceNumber,
    this.expiry,
    this.onAction,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final (pillFg, pillBg) = switch (status.stage) {
      LicenceStage.expired => (Colors.white, CubagColors.lapsed),
      LicenceStage.dueSoon => (CubagColors.ink, const Color(0xFFFFC98A)),
      LicenceStage.activationPending => (CubagColors.ink, const Color(0xFFFFC98A)),
      _ => (CubagColors.ink, const Color(0xFFBFE6CF)),
    };

    return Semantics(
      container: true,
      label: 'Licence. $name. ${status.pill}. ${status.message}',
      child: Material(
        color: CubagColors.cocoa,
        borderRadius: BorderRadius.circular(CubagRadius.hero),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Stack(
            children: [
              // The seal's ring, echoed large and faint: identifies the
              // document without competing with the text.
              Positioned(
                right: -70,
                top: -60,
                child: IgnorePointer(
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: CubagColors.seal.withAlpha(46),
                        width: 26,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const AppLogo(size: 34, borderRadius: 17, showShadow: false),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Broker licence',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CubagType.small.copyWith(
                              color: CubagColors.onCocoaMuted,
                            ),
                          ),
                        ),
                        _Pill(text: status.pill, fg: pillFg, bg: pillBg),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      name,
                      style: CubagType.title.copyWith(color: CubagColors.onCocoa),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (company != null && company!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        company!,
                        style: CubagType.small.copyWith(color: CubagColors.onCocoaMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _Field(
                            label: 'Licence no.',
                            value: (licenceNumber == null || licenceNumber!.isEmpty)
                                ? 'Not issued yet'
                                : licenceNumber!,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _Field(
                            label: status.stage == LicenceStage.expired
                                ? 'Expired on'
                                : 'Valid until',
                            value: expiry == null ? '—' : formatLicenceDate(expiry!),
                          ),
                        ),
                      ],
                    ),
                    if (status.yearRemaining != null) ...[
                      const SizedBox(height: 16),
                      _YearBar(
                        remaining: status.yearRemaining!,
                        urgent: status.needsAttention,
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      status.message,
                      style: CubagType.small.copyWith(color: CubagColors.onCocoa),
                    ),
                    if (status.actionLabel != null) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: onAction,
                          style: FilledButton.styleFrom(
                            backgroundColor: CubagColors.paper,
                            foregroundColor: CubagColors.cocoa,
                          ),
                          child: Text(status.actionLabel!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String value;
  const _Field({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: CubagType.caption.copyWith(color: CubagColors.onCocoaMuted)),
        const SizedBox(height: 2),
        Text(
          value,
          style: CubagType.figure.copyWith(color: CubagColors.onCocoa, fontSize: 15),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  const _Pill({required this.text, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: CubagType.caption.copyWith(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}

/// How much of the licence year is left. Encodes time, not decoration.
class _YearBar extends StatelessWidget {
  final double remaining;
  final bool urgent;
  const _YearBar({required this.remaining, required this.urgent});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 6,
        child: Stack(
          children: [
            Container(color: Colors.white.withAlpha(36)),
            FractionallySizedBox(
              widthFactor: remaining.clamp(0.02, 1.0),
              child: Container(
                color: urgent ? const Color(0xFFFFC98A) : const Color(0xFFBFE6CF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
