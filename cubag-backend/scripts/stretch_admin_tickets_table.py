import os

TICKETS_FILE = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter/lib/pages/admin_tickets_page.dart"

with open(TICKETS_FILE, "r", encoding="utf-8") as f:
    content = f.read()

# Replace the DataTable scroll wrapping to use LayoutBuilder with dynamic minWidth
old_snippet = """          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 960),
                child: DataTable("""

new_snippet = """          else
            LayoutBuilder(
              builder: (context, constraints) {
                final tableWidth = constraints.maxWidth > 960 ? constraints.maxWidth : 960.0;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: tableWidth),
                    child: DataTable("""

old_end_snippet = """                    );
                  }).toList(),
                ),
              ),
            ),"""

new_end_snippet = """                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),"""

if old_snippet in content and old_end_snippet in content:
    content = content.replace(old_snippet, new_snippet)
    content = content.replace(old_end_snippet, new_end_snippet)
    with open(TICKETS_FILE, "w", encoding="utf-8") as f:
        f.write(content)
    print("Updated admin_tickets_page.dart table to stretch to full width")
else:
    print("Could not match exact snippet in admin_tickets_page.dart")
