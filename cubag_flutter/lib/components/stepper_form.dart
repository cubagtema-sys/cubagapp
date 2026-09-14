import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

/// A reusable mobile-first multi-step form with animated progress bar,
/// step indicators, and optional file upload with preview.
///
/// Usage:
/// ```dart
/// StepperForm(
///   steps: [
///     FormStep(title: 'Identity', icon: Icons.person, builder: (ctx) => ...),
///     FormStep(title: 'Documents', icon: Icons.upload, builder: (ctx) => ...),
///   ],
///   onComplete: () async { /* submit */ },
/// )
/// ```
class StepperForm extends StatefulWidget {
  final List<FormStep> steps;
  final Future<void> Function() onComplete;
  final String completeLabel;
  final Color accentColor;

  const StepperForm({
    super.key,
    required this.steps,
    required this.onComplete,
    this.completeLabel = 'Submit',
    this.accentColor = const Color(0xFFFF5000),
  });

  @override
  State<StepperForm> createState() => StepperFormState();
}

class StepperFormState extends State<StepperForm>
    with SingleTickerProviderStateMixin {
  int _current = 0;
  bool _loading = false;
  String? _error;
  late AnimationController _progressCtrl;
  late Animation<double> _progressAnim;

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _updateProgress();
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  void _updateProgress() {
    final target = (_current + 1) / widget.steps.length;
    _progressAnim = Tween<double>(
      begin: _progressCtrl.value,
      end: target,
    ).animate(CurvedAnimation(parent: _progressCtrl, curve: Curves.easeInOut));
    _progressCtrl.forward(from: 0);
  }

  void setError(String msg) => setState(() => _error = msg);

  void nextStep() {
    if (_current < widget.steps.length - 1) {
      setState(() {
        _current++;
        _error = null;
      });
      _updateProgress();
    }
  }

  void prevStep() {
    if (_current > 0) {
      setState(() {
        _current--;
        _error = null;
      });
      _updateProgress();
    }
  }

  Future<void> _handleComplete() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.onComplete();
    } catch (e) {
      setState(() => _error = e.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_current];
    final isLast = _current == widget.steps.length - 1;
    final isFirst = _current == 0;
    final accent = widget.accentColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Progress bar ──
        AnimatedBuilder(
          animation: _progressAnim,
          builder: (_, _) => Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Step ${_current + 1} of ${widget.steps.length}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${(_progressAnim.value * 100).round()}%',
                    style: TextStyle(
                      fontSize: 13,
                      color: accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _progressAnim.value,
                  backgroundColor: accent.withAlpha(25),
                  valueColor: AlwaysStoppedAnimation(accent),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Step chips ──
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: widget.steps.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final s = widget.steps[i];
              final done = i < _current;
              final active = i == _current;
              return GestureDetector(
                onTap: done
                    ? () {
                        setState(() => _current = i);
                        _updateProgress();
                      }
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? accent
                        : done
                        ? accent.withAlpha(20)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: done
                        ? Border.all(color: accent.withAlpha(60))
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (done)
                        Icon(Icons.check_circle, size: 14, color: accent)
                      else
                        Icon(
                          s.icon,
                          size: 14,
                          color: active ? Colors.white : Colors.grey,
                        ),
                      const SizedBox(width: 4),
                      Text(
                        s.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: active
                              ? Colors.white
                              : done
                              ? accent
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),

        // ── Step title ──
        Text(
          step.title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A0F0A),
          ),
        ),
        if (step.subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            step.subtitle!,
            style: const TextStyle(fontSize: 15, color: Colors.grey),
          ),
        ],
        const SizedBox(height: 16),

        // ── Error ──
        if (_error != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x15ef4444),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x33ef4444)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFef4444),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFef4444),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── Step content ──
        step.builder(context),

        const SizedBox(height: 24),

        // ── Navigation buttons ──
        Row(
          children: [
            if (!isFirst)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: prevStep,
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Back'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ),
            if (!isFirst) const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _loading
                    ? null
                    : (isLast
                          ? _handleComplete
                          : () {
                              step.onNext?.call();
                            }),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  minimumSize: const Size(0, 48),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        isLast ? widget.completeLabel : 'Continue',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Definition of a single step in the [StepperForm].
class FormStep {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget Function(BuildContext context) builder;

  /// Called when user taps Continue. Use to validate before calling [StepperFormState.nextStep].
  final VoidCallback? onNext;

  const FormStep({
    required this.title,
    required this.icon,
    required this.builder,
    this.subtitle,
    this.onNext,
  });
}

/// A file upload field with drag-style preview for images and file metadata.
/// Integrates with [file_picker] package.
class FileUploadField extends StatefulWidget {
  final String label;
  final List<String> allowedExtensions;
  final void Function(PlatformFile file) onFilePicked;
  final Color accentColor;

  const FileUploadField({
    super.key,
    required this.label,
    required this.onFilePicked,
    this.allowedExtensions = const ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
    this.accentColor = const Color(0xFFFF5000),
  });

  @override
  State<FileUploadField> createState() => _FileUploadFieldState();
}

class _FileUploadFieldState extends State<FileUploadField> {
  PlatformFile? _file;

  bool get _isImage {
    final ext = _file?.extension?.toLowerCase();
    return ext == 'jpg' ||
        ext == 'jpeg' ||
        ext == 'png' ||
        ext == 'gif' ||
        ext == 'webp';
  }

  Future<void> _pick() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: widget.allowedExtensions,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _file = result.files.first);
      widget.onFilePicked(_file!);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: Color(0xFF1A0F0A),
          ),
        ),
        const SizedBox(height: 8),

        if (_file == null)
          // Upload area
          GestureDetector(
            onTap: _pick,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32),
              decoration: BoxDecoration(
                border: Border.all(color: accent.withAlpha(60), width: 1.5),
                borderRadius: BorderRadius.circular(12),
                color: accent.withAlpha(8),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accent.withAlpha(20),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.cloud_upload_outlined,
                      color: accent,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tap to upload',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.allowedExtensions
                        .map((e) => e.toUpperCase())
                        .join(', '),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          )
        else
          // File preview
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: accent.withAlpha(40)),
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
            ),
            child: Row(
              children: [
                // Image preview or file icon
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: _isImage && _file!.bytes != null
                        ? Image.memory(_file!.bytes!, fit: BoxFit.cover)
                        : Container(
                            color: accent.withAlpha(15),
                            child: Center(
                              child: Text(
                                '.${_file!.extension ?? '?'}',
                                style: TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _file!.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatSize(_file!.size),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0x15ef4444),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Color(0xFFef4444),
                      size: 16,
                    ),
                  ),
                  onPressed: () => setState(() => _file = null),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
      ],
    );
  }
}
