import '../components/admin_dialog.dart';
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
    final titleCtrl = TextEditingController(text: existing?['title']?.toString() ?? '');
    String uploadedUrl = existing?['image_url']?.toString() ?? '';
    String category = existing?['category']?.toString() ?? 'Conferences';
    if (!_categories.contains(category) || category == 'All') category = 'Conferences';
    Uint8List? pickedBytes;
    String? pickedName;
    bool submitting = false;
    String? error;

    // The member app still uses these colours behind a photo while it loads.
    (String, String) gradientFor(String c) => switch (c) {
          'Port Operations' => ('#1A3A5C', '#0D2137'),
          'Education' => ('#1B5E20', '#0A3012'),
          'Leadership' => ('#4A1A42', '#2B0A28'),
          _ => ('#6B3E26', '#3E2418'),
        };

    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) {
          Future<void> pick() async {
            try {
              final result = await FilePicker.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
                withData: true,
              );
              final file = result?.files.firstOrNull;
              if (file?.bytes != null) {
                setDlgState(() {
                  pickedBytes = file!.bytes;
                  pickedName = file.name;
                  error = null;
                });
              }
            } catch (e) {
              setDlgState(() => error = 'Could not open the photo. Try another file.');
            }
          }

          Future<void> submit() async {
            final title = titleCtrl.text.trim();
            if (title.isEmpty) {
              setDlgState(() => error = 'Add a caption.');
              return;
            }
            if (pickedBytes == null && uploadedUrl.isEmpty) {
              setDlgState(() => error = 'Choose a photo.');
              return;
            }
            setDlgState(() {
              submitting = true;
              error = null;
            });
            try {
              var finalUrl = uploadedUrl;
              if (pickedBytes != null) {
                final mpFile = MultipartFile.fromBytes(
                  Uint8List.fromList(pickedBytes!),
                  filename: pickedName ?? 'gallery_photo.jpg',
                );
                final up = await _api.upload('/uploads/image', FormData.fromMap({'image': mpFile}));
                if (up.data != null && up.data['url'] != null) finalUrl = up.data['url'].toString();
              }
              final g = gradientFor(category);
              final data = {
                'title': title,
                'category': category,
                'image_url': finalUrl,
                'grad_start': g.$1,
                'grad_end': g.$2,
              };
              if (isEdit) {
                await _api.put('/events/admin/gallery/${existing['id']}', data: {...data, 'is_active': existing['is_active'] ?? true});
              } else {
                await _api.post('/events/admin/gallery', data: data);
              }
              if (dlgCtx.mounted) {
                Navigator.pop(dlgCtx);
                _fetchGallery();
              }
            } catch (e) {
              setDlgState(() {
                submitting = false;
                error = 'Could not save the photo. Try again.';
              });
            }
          }

          final hasPhoto = pickedBytes != null || uploadedUrl.isNotEmpty;
          return AdminDialog(
            title: isEdit ? 'Edit photo' : 'Add photo',
            subtitle: 'Members see it in the gallery in the app.',
            actions: [
              TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Cancel')),
              FilledButton(
                onPressed: submitting ? null : submit,
                child: Text(submitting ? 'Saving…' : (isEdit ? 'Save changes' : 'Add photo')),
              ),
            ],
            children: [
              AdminField(
                label: 'Photo',
                help: 'JPEG, PNG or WEBP.',
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: CubagColors.sand,
                    borderRadius: BorderRadius.circular(CubagRadius.card),
                    border: Border.all(color: CubagColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 200,
                        child: pickedBytes != null
                            ? Image.memory(pickedBytes!, fit: BoxFit.cover)
                            : (uploadedUrl.isNotEmpty
                                ? CorsImageWidget(
                                    url: ApiService.resolveImageUrl(uploadedUrl),
                                    fit: BoxFit.cover,
                                    errorWidget: const Center(child: Icon(Icons.broken_image_outlined, color: CubagColors.muted)),
                                  )
                                : InkWell(
                                    onTap: pick,
                                    child: const Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.add_photo_alternate_outlined, size: 36, color: CubagColors.cocoa),
                                          SizedBox(height: CubagSpace.xs),
                                          Text('Choose a photo'),
                                        ],
                                      ),
                                    ),
                                  )),
                      ),
                      if (hasPhoto)
                        Container(
                          color: CubagColors.paper,
                          padding: const EdgeInsets.symmetric(horizontal: CubagSpace.sm),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  pickedName ?? 'Current photo',
                                  style: CubagType.small,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TextButton(onPressed: pick, child: const Text('Replace')),
                              TextButton(
                                onPressed: () => setDlgState(() {
                                  pickedBytes = null;
                                  pickedName = null;
                                  uploadedUrl = '';
                                }),
                                child: const Text('Remove'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              AdminField(
                label: 'Caption',
                child: TextField(
                  controller: titleCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'For example: Annual general meeting 2026'),
                ),
              ),
              AdminField(
                label: 'Topic',
                child: AdminChoice<String>(
                  options: [for (final c in _categories.where((c) => c != 'All')) (c, c)],
                  value: category,
                  onChanged: (v) => setDlgState(() => category = v),
                ),
              ),
              if (error != null) Text(error!, style: CubagType.small.copyWith(color: CubagColors.lapsed)),
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
    final confirm = await showAdminConfirm(context, title: 'Archive this photo?', message: '"${item['title']}" is taken out of the gallery members see.', confirmLabel: 'Archive', destructive: true);
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
