import '../components/filter_tabs.dart';
import '../components/admin_list.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../components/cors_image_widget.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';
import '../design/cubag_design.dart';

const _kOrange = CubagColors.action;

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
                  style: TextStyle(
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
                      style: TextStyle(
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
                      style: TextStyle(
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
                                color: CubagColors.ink,
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
                                    style: TextStyle(
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
                                color: CubagColors.ink,
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
                                  style: TextStyle(
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
                              style: TextStyle(
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
                              style: TextStyle(
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
        title: const Text('Archive this photo?'),
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
    final items = _filteredItems;
    final shown = _items.where((i) => i['is_active'] == true).length;

    return AppLayout(
      title: 'Gallery',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminHeader(
                title: 'Gallery',
                subtitle: 'Photos members see in the app. $shown of ${_items.length} shown. Hide a photo to take it down without deleting it.',
                actions: [
                  FilledButton.icon(
                    onPressed: () => _showGalleryDialog(),
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                    label: const Text('Add photo'),
                  ),
                ],
              ),
              FilterTabs(
                tabs: [for (final c in _categories) (c, c == 'All' ? 'All' : c)],
                selected: _categoryFilter,
                onSelected: (c) => setState(() => _categoryFilter = c),
              ),
              const SizedBox(height: CubagSpace.sm),
              AdminSearchField(
                hint: 'Search photo titles',
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(height: CubagSpace.md),
              if (_loading)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                EmptyMessage(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not load the gallery',
                  message: _error,
                  action: OutlinedButton(onPressed: _fetchGallery, child: const Text('Try again')),
                )
              else if (items.isEmpty)
                EmptyMessage(
                  icon: Icons.photo_library_outlined,
                  title: _items.isEmpty ? 'No photos yet' : 'No photos match',
                  message: _items.isEmpty
                      ? 'Add photos from meetings and events. Members see them in the app.'
                      : 'Try another topic, or clear the search.',
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 320,
                    mainAxisSpacing: CubagSpace.md,
                    crossAxisSpacing: CubagSpace.md,
                    mainAxisExtent: 290,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _photoTile(items[i]),
                ),
              const SizedBox(height: CubagSpace.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoTile(dynamic it) {
    final isActive = it['is_active'] == true;
    final imgUrl = it['image_url']?.toString() ?? '';
    final title = it['title']?.toString() ?? '';
    final category = it['category']?.toString() ?? '';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CubagColors.paper,
        borderRadius: BorderRadius.circular(CubagRadius.card),
        border: Border.all(color: CubagColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Opacity(
              opacity: isActive ? 1 : 0.45,
              child: Container(
                color: CubagColors.sand,
                child: imgUrl.isEmpty
                    ? const Icon(Icons.image_outlined, size: 40, color: CubagColors.muted)
                    : CorsImageWidget(
                        url: ApiService.resolveImageUrl(imgUrl),
                        fit: BoxFit.cover,
                        errorWidget: const Icon(Icons.broken_image_outlined, size: 32, color: CubagColors.muted),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(CubagSpace.md, CubagSpace.sm, CubagSpace.md, 0),
            child: Text(title, style: CubagType.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(CubagSpace.md, 0, 0, CubagSpace.xxs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    [if (category.isNotEmpty) category, isActive ? 'Shown' : 'Hidden'].join(' · '),
                    style: CubagType.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Tooltip(
                  message: isActive ? 'Shown to members' : 'Hidden from members',
                  child: Switch(value: isActive, onChanged: (_) => _toggleStatus(it)),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert_rounded, color: CubagColors.muted),
                  onSelected: (v) {
                    if (v == 'edit') _showGalleryDialog(it);
                    if (v == 'delete') _deleteItem(it);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Archive', style: TextStyle(color: CubagColors.lapsed))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
