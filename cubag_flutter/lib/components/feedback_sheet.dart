import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/cubag_design.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';

/// "Tell us what is hard": a short note to the Secretariat about the app.
/// It is sent as a support ticket (subject "App feedback: <area>"), so it
/// shows up in the admin Tickets list and the member sees replies in Support.
class FeedbackSheet extends StatefulWidget {
  /// Sends the ticket; replaceable in tests.
  final Future<bool> Function(String subject, String message)? send;
  const FeedbackSheet({super.key, this.send});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: CubagColors.paper,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(CubagRadius.hero)),
        ),
        builder: (_) => const FeedbackSheet(),
      );

  static const areas = ['Paying dues', 'Licence and renewal', 'Documents', 'Finding something', 'Reading the screen', 'Something else'];
  static const quick = ['The text is too small', 'I could not find it', 'I did not understand a word', 'It showed an error'];

  @override
  State<FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<FeedbackSheet> {
  final _ctrl = TextEditingController();
  String _area = FeedbackSheet.areas.first;
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<bool> _post(String subject, String message) async {
    try {
      final res = await ApiService().post('/tickets', data: {'subject': subject, 'message': message});
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e, st) {
      AppLogger.error('feedback_sheet', e, st);
      return false;
    }
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Write a few words, or tap one of the reasons above.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final ok = await (widget.send ?? _post)('App feedback: $_area', text);
    if (!mounted) return;
    if (ok) HapticFeedback.mediumImpact();
    setState(() {
      _sending = false;
      _sent = ok;
      if (!ok) _error = 'Could not send. Check your connection and try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(CubagSpace.lg, CubagSpace.md, CubagSpace.lg, CubagSpace.lg + bottom),
      child: SingleChildScrollView(
        child: _sent ? _thanks(context) : _form(context),
      ),
    );
  }

  Widget _thanks(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: CubagSpace.lg),
          const Icon(Icons.check_circle_rounded, color: CubagColors.valid, size: 48),
          const SizedBox(height: CubagSpace.sm),
          Text('Thank you', style: CubagType.title),
          const SizedBox(height: CubagSpace.xxs),
          Text(
            'The Secretariat will read it. If they reply, you will see it under Support.',
            style: CubagType.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: CubagSpace.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ),
        ],
      );

  Widget _form(BuildContext context) {
    Widget pill(String label, bool selected, VoidCallback onTap) => ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          labelStyle: CubagType.body.copyWith(color: selected ? CubagColors.onCocoa : CubagColors.ink),
          selectedColor: CubagColors.cocoa,
          backgroundColor: CubagColors.paper,
          side: BorderSide(color: selected ? CubagColors.cocoa : CubagColors.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          onSelected: (_) => onTap(),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: CubagColors.lineStrong, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: CubagSpace.md),
        Text('Tell us what is hard', style: CubagType.title),
        const SizedBox(height: CubagSpace.xxs),
        Text('Anything slow, confusing or hard to read. It goes straight to the CUBAG Secretariat.', style: CubagType.body),
        const SizedBox(height: CubagSpace.lg),
        Text('What is it about?', style: CubagType.label),
        const SizedBox(height: CubagSpace.xs),
        Wrap(
          spacing: CubagSpace.xs,
          runSpacing: CubagSpace.xs,
          children: [for (final a in FeedbackSheet.areas) pill(a, a == _area, () => setState(() => _area = a))],
        ),
        const SizedBox(height: CubagSpace.lg),
        Text('What happened?', style: CubagType.label),
        const SizedBox(height: CubagSpace.xs),
        Wrap(
          spacing: CubagSpace.xs,
          runSpacing: CubagSpace.xs,
          children: [
            for (final q in FeedbackSheet.quick)
              ActionChip(
                label: Text(q),
                labelStyle: CubagType.small.copyWith(color: CubagColors.ink),
                backgroundColor: CubagColors.sand,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                onPressed: () {
                  final t = _ctrl.text.trim();
                  _ctrl.text = t.isEmpty ? '$q.' : '$t $q.';
                  setState(() => _error = null);
                },
              ),
          ],
        ),
        const SizedBox(height: CubagSpace.sm),
        TextField(
          controller: _ctrl,
          minLines: 3,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          style: CubagType.body.copyWith(color: CubagColors.ink),
          decoration: const InputDecoration(hintText: 'For example: I could not find where to download my receipt.'),
        ),
        if (_error != null) ...[
          const SizedBox(height: CubagSpace.xs),
          Text(_error!, style: CubagType.small.copyWith(color: CubagColors.lapsed)),
        ],
        const SizedBox(height: CubagSpace.lg),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _sending ? null : _submit,
            child: Text(_sending ? 'Sending…' : 'Send to CUBAG'),
          ),
        ),
      ],
    );
  }
}
