import 'package:flutter/material.dart';

const _kOrange = Color(0xFFFF5000);

class DropdownItem<T> {
  final T value;
  final String label;
  final Widget? leading;

  const DropdownItem({required this.value, required this.label, this.leading});
}

class CustomDropdown<T> extends StatelessWidget {
  final T value;
  final List<DropdownItem<T>> items;
  final ValueChanged<T>? onChanged;
  final String? hint;
  final Widget? prefixIcon;
  final double? width;
  final bool dense;
  final bool enabled;

  const CustomDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.prefixIcon,
    this.width,
    this.dense = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Ensure the current value matches an available item
    final hasValue = items.any((item) => item.value == value);
    final effectiveValue = hasValue ? value : null;

    return SizedBox(
      width: width ?? double.infinity,
      child: Container(
        height: dense ? 40 : 54,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: !enabled
              ? (isDark ? const Color(0xFF1A0F0A) : const Color(0xFFf1f5f9))
              : (isDark ? const Color(0xFF281710) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: !enabled
                ? (isDark ? Colors.white12 : Colors.grey.shade300)
                : (isDark ? const Color(0xFF4D2D20) : Colors.grey.shade300),
            width: 1.5,
          ),
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            if (prefixIcon != null) ...[prefixIcon!, const SizedBox(width: 8)],
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: effectiveValue,
                  hint: Text(
                    hint ?? '',
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? const Color(0xFF64748b) : Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  isExpanded: true,
                  icon: Icon(
                    !enabled
                        ? Icons.lock_outline_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: !enabled
                        ? (isDark ? Colors.white38 : Colors.grey.shade500)
                        : (isDark
                            ? const Color(0xFF94a3b8)
                            : const Color(0xFF64748b)),
                  ),
                  dropdownColor: isDark
                      ? const Color(0xFF281710)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  elevation: 6,
                  style: TextStyle(
                    fontSize: 15,
                    color: !enabled
                        ? (isDark ? Colors.white60 : const Color(0xFF334155))
                        : (isDark
                            ? const Color(0xFFcbd5e1)
                            : const Color(0xFF1A0F0A)),
                    fontWeight: FontWeight.w600,
                  ),
                  onChanged: enabled
                      ? (val) {
                          if (val != null && onChanged != null) onChanged!(val);
                        }
                      : null,
                  items: items.map((item) {
                    final isSelected = item.value == effectiveValue;
                    return DropdownMenuItem<T>(
                      value: item.value,
                      child: Row(
                        children: [
                          if (item.leading != null) ...[
                            item.leading!,
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? _kOrange
                                    : (isDark
                                          ? const Color(0xFFcbd5e1)
                                          : const Color(0xFF1A0F0A)),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: _kOrange,
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
