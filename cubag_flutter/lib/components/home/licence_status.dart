/// What the member's licence looks like today, and the one action that moves
/// it forward. Pure (no Flutter imports) so every branch is unit-tested.
enum LicenceStage { activationPending, expired, dueSoon, renewalSoon, valid }

class LicenceStatus {
  final LicenceStage stage;

  /// Short pill text on the licence card ("Valid", "Renew in 23 days").
  final String pill;

  /// One plain sentence under the details.
  final String message;

  /// The card's main action; null when nothing is needed.
  final String? actionLabel;
  final String? actionRoute;

  /// Days until expiry (negative once expired); null when unknown.
  final int? daysLeft;

  /// Share of the licence year still remaining, 0..1 (null when unknown).
  final double? yearRemaining;

  const LicenceStatus({
    required this.stage,
    required this.pill,
    required this.message,
    this.actionLabel,
    this.actionRoute,
    this.daysLeft,
    this.yearRemaining,
  });

  bool get needsAttention =>
      stage == LicenceStage.expired ||
      stage == LicenceStage.dueSoon ||
      stage == LicenceStage.activationPending;
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "5 Dec 2026"
String formatLicenceDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

DateTime? parseExpiry(Object? raw) {
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty || s == 'None' || s == 'null') return null;
  return DateTime.tryParse(s);
}

LicenceStatus licenceStatus({
  required bool packagePaid,
  required DateTime? expiry,
  required int pendingTasks,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final day = DateTime(today.year, today.month, today.day);

  if (!packagePaid) {
    return LicenceStatus(
      stage: LicenceStage.activationPending,
      pill: 'Activation pending',
      message: pendingTasks > 0
          ? 'Complete your remaining steps to activate your membership.'
          : 'Pay the membership package to activate your licence and voting rights.',
      actionLabel: pendingTasks > 0 ? 'View steps ($pendingTasks)' : 'Pay package fee',
      actionRoute: pendingTasks > 0
          ? '/tasks'
          : '/payments?fee=Membership%20Entrance%20Package',
    );
  }

  if (expiry == null) {
    return const LicenceStatus(
      stage: LicenceStage.valid,
      pill: 'Active',
      message: 'Your membership is active.',
    );
  }

  final exp = DateTime(expiry.year, expiry.month, expiry.day);
  // Count calendar days in UTC so a daylight-saving change (members abroad)
  // can't make a 200-day span read as 199.
  final daysLeft = DateTime.utc(exp.year, exp.month, exp.day)
      .difference(DateTime.utc(day.year, day.month, day.day))
      .inDays;
  final remaining = (daysLeft / 365).clamp(0.0, 1.0);
  final date = formatLicenceDate(exp);

  if (daysLeft < 0) {
    return LicenceStatus(
      stage: LicenceStage.expired,
      pill: 'Expired',
      message: 'Your licence expired on $date. Renew to restore good standing.',
      actionLabel: 'Renew licence',
      actionRoute: '/compliance',
      daysLeft: daysLeft,
      yearRemaining: 0,
    );
  }
  if (daysLeft <= 30) {
    final when = daysLeft == 0 ? 'today' : (daysLeft == 1 ? 'tomorrow' : 'in $daysLeft days');
    return LicenceStatus(
      stage: LicenceStage.dueSoon,
      pill: daysLeft == 0 ? 'Expires today' : 'Renew in $daysLeft ${daysLeft == 1 ? 'day' : 'days'}',
      message: 'Your licence expires $when, on $date.',
      actionLabel: 'Renew licence',
      actionRoute: '/compliance',
      daysLeft: daysLeft,
      yearRemaining: remaining,
    );
  }
  // The server accepts renewals only in the last 30 days (routes/payments.py,
  // LICENSE_ACTIVE). In the month before, say when the window opens.
  if (daysLeft <= 60) {
    final opens = exp.subtract(const Duration(days: 30));
    return LicenceStatus(
      stage: LicenceStage.renewalSoon,
      pill: 'Valid',
      message: 'Renewal opens on ${formatLicenceDate(opens)}. Unused days carry over.',
      daysLeft: daysLeft,
      yearRemaining: remaining,
    );
  }
  return LicenceStatus(
    stage: LicenceStage.valid,
    pill: 'Valid',
    message: 'In good standing until $date.',
    daysLeft: daysLeft,
    yearRemaining: remaining,
  );
}

/// "Good morning" / "Good afternoon" / "Good evening".
String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}
