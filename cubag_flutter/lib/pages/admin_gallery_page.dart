import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../components/cors_image_widget.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10b981);
const _kCardBg = Color(0xFF281710);

class AdminGalleryPage extends StatefulWidget {
  const AdminGalleryPage({super.key});

  @override
  State<AdminGalleryPage> createState() => _AdminGalleryPageState();
}

class _AdminGalleryPageState extends State<AdminGalleryPage> {
  final ApiService _api = ApiService();
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  String _categoryFilter = 'All';

  final List<String> _categories = [
    'All',
    'Conferences',
    'Port Operations',
    'Education',
    'Leadership',
  ];

  @override
  void initState() {
    super.initState();
    _fetchGallery();
  }

  Future<void> _fetchGallery() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.get('/events/admin/gallery');
      if (mounted && res.data is Map && res.data['items'] is List) {
        setState(() {
          _items = res.data['items'];
          _loading = false;
        });
      } else if (mounted && res.data is List) {
        setState(() {
          _items = res.data;
          _loading = false;
        });
      }
    } catch (e, st) {
      AppLogger.error('admin_gallery', e, st);
      if (mounted) {
        setState(() {
          _error = 'Failed to load gallery items';
          _loading = false;
        });
      }
    }
  }

  Future<void> _showGalleryDialog([dynamic existing]) async {
    final isEdit = existing != null;
    final titleCtrl = TextEditingController(
      text: existing?['title']?.toString() ?? '',
    );
    String uploadedUrl = existing?['image_url']?.toString() ?? '';
    String category = existing?['category']?.toString() ?? 'Conferences';
    String gradStart = existing?['grad_start']?.toString() ?? '#6B3E26';
    String gradEnd = existing?['grad_end']?.toString() ?? '#3E2418';

    Uint8List? selectedImageBytes;
    String? selectedImageName;
    bool submitting = false;

    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kOrange.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.photo_library_rounded,
                    color: _kOrange,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isEdit ? 'Edit Gallery Photo' : 'Upload Gallery Photo',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upload photo attachment with short writings & captions for the homepage CUBAG Gallery.',
                      style: GoogleFonts.inter(
                        fontSize: 16.5,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Photo Caption / Title
                    TextField(
                      controller: titleCtrl,
                      decoration: InputDecoration(
                        labelText: 'Photo Caption / Title *',
                        hintText: 'e.g. CUBAG Annual General Meeting 2026',
                        prefixIcon: const Icon(Icons.title_rounded, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Category Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: InputDecoration(
                        labelText: 'Category',
                        prefixIcon: const Icon(Icons.category_outlined, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Conferences',
                          child: Text('Conferences'),
                        ),
                        DropdownMenuItem(
                          value: 'Port Operations',
                          child: Text('Port Operations'),
                        ),
                        DropdownMenuItem(
                          value: 'Education',
                          child: Text('Education'),
                        ),
                        DropdownMenuItem(
                          value: 'Leadership',
                          child: Text('Leadership'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val == null) return;
                        setDlgState(() {
                          category = val;
                          if (val == 'Port Operations') {
                            gradStart = '#1A3A5C';
                            gradEnd = '#0D2137';
                          } else if (val == 'Education') {
                            gradStart = '#1B5E20';
                            gradEnd = '#0A3012';
                          } else if (val == 'Leadership') {
                            gradStart = '#4A1A42';
                            gradEnd = '#2B0A28';
                          } else {
                            gradStart = '#6B3E26';
                            gradEnd = '#3E2418';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Image Attachment Section
                    Text(
                      'Photo Attachment',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.withAlpha(20),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.withAlpha(50)),
                      ),
                      child: Column(
                        children: [
                          if (selectedImageBytes != null) ...[
                            Container(
                              height: 240,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A0F0A),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  selectedImageBytes!,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    selectedImageName ?? 'Attached image',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    setDlgState(() {
                                      selectedImageBytes = null;
                                      selectedImageName = null;
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.red,
                                  ),
                                  label: const Text(
                                    'Remove',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ] else if (uploadedUrl.isNotEmpty) ...[
                            Container(
                              height: 240,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A0F0A),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: CorsImageWidget(
                                  url: ApiService.resolveImageUrl(uploadedUrl),
                                  fit: BoxFit.contain,
                                  errorWidget: Container(
                                    height: 120,
                                    color: Colors.grey.shade900,
                                    child: const Center(
                                      child: Icon(
                                        Icons.photo_outlined,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Current Photo (Full View)',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    setDlgState(() => uploadedUrl = '');
                                  },
                                  icon: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.red,
                                  ),
                                  label: const Text(
                                    'Remove',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 36,
                              color: _kOrange.withAlpha(200),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Select a JPEG, PNG, or WEBP image file',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],

                          // Pick attachment button
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _kOrange,
                              side: const BorderSide(color: _kOrange),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                            onPressed: () async {
                              try {
                                final result = await FilePicker.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: [
                                    'jpg',
                                    'jpeg',
                                    'png',
                                    'webp',
                                    'gif',
                                  ],
                                  withData: true,
                                );
                                if (result != null && result.files.isNotEmpty) {
                                  final file = result.files.first;
                                  if (file.bytes != null) {
                                    setDlgState(() {
                                      selectedImageBytes = file.bytes;
                                      selectedImageName = file.name;
                                    });
                                  }
                                }
                              } catch (e) {
                                if (dlgCtx.mounted) {
                                  ScaffoldMessenger.of(dlgCtx).showSnackBar(
                                    SnackBar(
                                      content: Text('File picker error: $e'),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.attach_file_rounded, size: 18),
                            label: Text(
                              selectedImageBytes != null || uploadedUrl.isNotEmpty
                                  ? 'Replace Photo Attachment'
                                  : 'Choose Photo Attachment',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: submitting
                    ? null
                    : () async {
                        final title = titleCtrl.text.trim();
                        if (title.isEmpty) return;
                        setDlgState(() => submitting = true);
                        try {
                          String finalUrl = uploadedUrl;

                          // If new attachment picked, upload it first
                          if (selectedImageBytes != null) {
                            final exactBytes = Uint8List.fromList(selectedImageBytes!);
                            final mpFile = MultipartFile.fromBytes(
                              exactBytes,
                              filename:
                                  selectedImageName ?? 'gallery_photo.jpg',
                            );
                            final uploadRes = await _api.upload(
                              '/uploads/image',
                              FormData.fromMap({'image': mpFile}),
                            );
                            if (uploadRes.data != null &&
                                uploadRes.data['url'] != null) {
                              finalUrl = uploadRes.data['url'].toString();
                            }
                          }

                          if (isEdit) {
                            await _api.put(
                              '/events/admin/gallery/${existing['id']}',
                              data: {
                                'title': title,
                                'category': category,
                                'image_url': finalUrl,
                                'grad_start': gradStart,
                                'grad_end': gradEnd,
                                'is_active': existing['is_active'] ?? true,
                              },
                            );
                          } else {
                            await _api.post(
                              '/events/admin/gallery',
                              data: {
                                'title': title,
                                'category': category,
                                'image_url': finalUrl,
                                'grad_start': gradStart,
                                'grad_end': gradEnd,
                              },
                            );
                          }
                          if (dlgCtx.mounted) {
                            Navigator.pop(dlgCtx);
                            _fetchGallery();
                          }
                        } catch (e) {
                          setDlgState(() => submitting = false);
                          if (dlgCtx.mounted) {
                            ScaffoldMessenger.of(dlgCtx).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Failed to save gallery photo: $e',
                                ),
                              ),
                            );
                          }
                        }
                      },
                child: submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        isEdit ? 'Save Changes' : 'Publish Photo',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );

    titleCtrl.dispose();
  }

  Future<void> _toggleStatus(dynamic item) async {
    final id = item['id'];
    final newActive = !(item['is_active'] == true);
    try {
      await _api.put(
        '/events/admin/gallery/$id',
        data: {'is_active': newActive},
      );
      _fetchGallery();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating status: $e')));
      }
    }
  }

  Future<void> _deleteItem(dynamic item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Archive Gallery Item?'),
        content: Text(
          'Are you sure you want to remove "${item['title']}" from the public gallery?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _api.delete('/events/admin/gallery/${item['id']}');
      _fetchGallery();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error archiving gallery item: $e')),
        );
      }
    }
  }

  List<dynamic> get _filteredItems {
    return _items.where((it) {
      final title = (it['title']?.toString() ?? '').toLowerCase();
      final cat = (it['category']?.toString() ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();
      final matchesSearch =
          query.isEmpty || title.contains(query) || cat.contains(query);

      if (_categoryFilter != 'All' &&
          !cat.contains(_categoryFilter.toLowerCase())) {
        return false;
      }
      return matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _kCardBg : Colors.white;
    final borderCol = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFe2e8f0);

    final total = _items.length;
    final active = _items.where((i) => i['is_active'] == true).length;

    return AppLayout(
      title: 'Gallery Management',
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'Photo Gallery & Media Attachments',
            subtitle:
                'Upload photo attachments with captions across Conferences, Port Operations, Education & Leadership.',
            actions: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAdminOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                onPressed: () => _showGalleryDialog(),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: Text(
                  'Upload Photo',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Metric Stats Cards
          Row(
            children: [
              Expanded(
                child: AdminStatCard(
                  label: 'Total Photos',
                  value: '$total',
                  icon: Icons.photo_library_outlined,
                  color: kAdminBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdminStatCard(
                  label: 'Active Live',
                  value: '$active',
                  icon: Icons.check_circle_outline_rounded,
                  color: kAdminGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdminStatCard(
                  label: 'Categories',
                  value: '4 Categories',
                  icon: Icons.category_outlined,
                  color: kAdminOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Category Chips & Search Bar
          AdminToolbar(
            searchHint: 'Search gallery items by title or category...',
            onSearchChanged: (v) => setState(() => _searchQuery = v),
            filters: _categories.map((cat) {
              final isSel = _categoryFilter == cat;
              return AdminFilterChip(
                label: cat,
                isSelected: isSel,
                onTap: () => setState(() => _categoryFilter = cat),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Content Grid / List
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: _kOrange)),
            )
          else if (_error != null)
            Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          else if (_filteredItems.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderCol),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No gallery items match your filter.',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 360,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 1.05,
              ),
              itemCount: _filteredItems.length,
              itemBuilder: (ctx, i) {
                final it = _filteredItems[i];
                final isActive = it['is_active'] == true;
                final grad0 = _parseColor(
                  it['grad_start']?.toString() ?? '#6B3E26',
                );
                final grad1 = _parseColor(
                  it['grad_end']?.toString() ?? '#3E2418',
                );
                final imgUrl = it['image_url']?.toString() ?? '';

                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [grad0, grad1],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(20),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      // If photo attachment URL is present, show image at full opacity with crisp gradient overlay
                      if (imgUrl.isNotEmpty) ...[
                        Positioned.fill(
                          child: CorsImageWidget(
                            url: ApiService.resolveImageUrl(imgUrl),
                            fit: BoxFit.cover,
                            errorWidget: const SizedBox(),
                          ),
                        ),
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withAlpha(90),
                                  Colors.transparent,
                                  Colors.black.withAlpha(190),
                                ],
                                stops: const [0.0, 0.4, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ],

                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withAlpha(120),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    it['category']?.toString() ?? 'Conferences',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      constraints: const BoxConstraints(),
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      tooltip: 'Edit',
                                      onPressed: () => _showGalleryDialog(it),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      constraints: const BoxConstraints(),
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Colors.white70,
                                        size: 18,
                                      ),
                                      tooltip: 'Archive',
                                      onPressed: () => _deleteItem(it),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  it['title']?.toString() ?? '',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black87,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      isActive ? '● Active' : '○ Hidden',
                                      style: GoogleFonts.inter(
                                        color: isActive
                                            ? _kGreen
                                            : Colors.white60,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        shadows: const [
                                          Shadow(
                                            color: Colors.black87,
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: isActive,
                                      activeThumbColor: _kGreen,
                                      onChanged: (_) => _toggleStatus(it),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      final s = hex.replaceAll('#', '');
      return Color(int.parse('FF$s', radix: 16));
    } catch (_) {
      return const Color(0xFF6B3E26);
    }
  }
}
