import os

FEES_FILE = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter/lib/pages/admin_fees_page.dart"

with open(FEES_FILE, "r", encoding="utf-8") as f:
    content = f.read()

# Replace _buildFeeTable to use LayoutBuilder and stretch to 100% width
old_table_func = """    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(isDark ? 25 : 5), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 900),
          child: DataTable(
            horizontalMargin: 16,
            columnSpacing: 18,
            headingRowColor: WidgetStateProperty.all(isDark ? const Color(0xFF131722) : const Color(0xFFF8FAFC)),
            headingTextStyle: GoogleFonts.outfit(fontSize: 10.5, fontWeight: FontWeight.w800, color: textMuted, letterSpacing: 0.5),
            columns: const [
              DataColumn(label: Text('NAME / DESCRIPTION')),
              DataColumn(label: Text('AMOUNT (GHS)')),
              DataColumn(label: Text('FREQUENCY')),
              DataColumn(label: Text('BREAKDOWN / PURPOSE')),
              DataColumn(label: Text('ACTIONS')),
            ],"""

new_table_func = """    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(isDark ? 25 : 5), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = constraints.maxWidth > 900 ? constraints.maxWidth : 900.0;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: tableWidth),
              child: DataTable(
                horizontalMargin: 20,
                columnSpacing: 24,
                headingRowColor: WidgetStateProperty.all(isDark ? const Color(0xFF131722) : const Color(0xFFF8FAFC)),
                headingTextStyle: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: textMuted, letterSpacing: 0.5),
                columns: const [
                  DataColumn(label: Text('NAME / DESCRIPTION')),
                  DataColumn(label: Text('AMOUNT (GHS)')),
                  DataColumn(label: Text('FREQUENCY')),
                  DataColumn(label: Text('BREAKDOWN / PURPOSE')),
                  DataColumn(label: Text('ACTIONS')),
                ],"""

if old_table_func in content:
    content = content.replace(old_table_func, new_table_func)
    # also close LayoutBuilder
    content = content.replace("          child: DataTable(\n", "          child: DataTable(\n")
    # find ending of DataTable
    # In the original, it ends with:
    #             rows: items.map(...).toList(),
    #           ),
    #         ),
    #       ),
    #     );
    old_end = """                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );"""

    new_end = """                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
              ),
            ),
          );
        },
      ),
    );"""
    content = content.replace(old_end, new_end)

with open(FEES_FILE, "w", encoding="utf-8") as f:
    f.write(content)

print("Updated admin_fees_page.dart tables to stretch to full width")
