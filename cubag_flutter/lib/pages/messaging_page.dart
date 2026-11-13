import 'package:flutter/material.dart';
import '../components/app_layout.dart';
import '../services/api_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';
import '../design/cubag_design.dart';

class MessagingPage extends StatefulWidget {
  final String? initialUserId;
  final String? initialUserName;
  final String? initialUserCompany;

  const MessagingPage({
    super.key,
    this.initialUserId,
    this.initialUserName,
    this.initialUserCompany,
  });

  @override
  State<MessagingPage> createState() => _MessagingPageState();
}

class _MessagingPageState extends State<MessagingPage> {
  bool _loading = true;
  bool _loadingChat = false;
  List<dynamic> _conversations = [];
  List<dynamic> _filteredConversations = [];
  String _search = '';
  Map<String, dynamic>? _activeChat;
  List<dynamic> _messages = [];
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _fetchConversations().then((_) {
      _checkInitialChat();
    });
  }

  @override
  void didUpdateWidget(MessagingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialUserId != null && widget.initialUserId!.isNotEmpty) {
      if (widget.initialUserId != oldWidget.initialUserId ||
          _activeChat?['id']?.toString() != widget.initialUserId) {
        _checkInitialChat();
      }
    }
  }

  void _checkInitialChat() {
    if (widget.initialUserId != null &&
        widget.initialUserId!.isNotEmpty &&
        mounted) {
      final existing = _conversations.firstWhere(
        (c) =>
            (c as Map?)?['id']?.toString() == widget.initialUserId.toString(),
        orElse: () => null,
      );

      if (existing != null) {
        _openChat(Map<String, dynamic>.from(existing as Map));
      } else {
        _openChat({
          'id': widget.initialUserId,
          'name': widget.initialUserName ?? 'CUBAG Member',
          'company': widget.initialUserCompany ?? 'CUBAG Member',
        });
      }
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchConversations({bool showLoading = true}) async {
    if (showLoading && _conversations.isEmpty) setState(() => _loading = true);
    try {
      await ApiService().fetchDataWithCache('/messages/conversations', (
        data,
        isCached, {
        bool hasError = false,
      }) {
        if (!mounted) return;
        if (data != null) {
          final all = ApiService.ensureList(data);
          setState(() {
            _conversations = all;
            _applySearch(_search);
            _loading = false;
          });
        }
      });
    } catch (e, st) {
      AppLogger.error('messaging_page', e, st);
    }
    if (mounted && showLoading) setState(() => _loading = false);
  }

  void _applySearch(String q) {
    _search = q;
    final lower = q.toLowerCase();
    _filteredConversations = lower.isEmpty
        ? List.from(_conversations)
        : _conversations.where((c) {
            return (c['name']?.toString().toLowerCase() ?? '').contains(
                  lower,
                ) ||
                (c['company']?.toString().toLowerCase() ?? '').contains(lower);
          }).toList();
  }

  Future<void> _openChat(Map<String, dynamic> target) async {
    setState(() {
      _activeChat = target;
    });
    await _loadMessages(showLoading: _messages.isEmpty);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _loadMessages({
    bool showLoading = true,
    bool bypassCache = false,
  }) async {
    if (_activeChat == null) return;
    final chatId = _activeChat!['id'];
    if (showLoading && _messages.isEmpty) setState(() => _loadingChat = true);
    try {
      if (bypassCache) {
        final res = await ApiService().get('/messages/$chatId');
        if (!mounted || _activeChat?['id'] != chatId) return;
        if (res.statusCode == 200) {
          final rawData = res.data;
          List<dynamic> msgs = (rawData is Map && rawData.containsKey('items'))
              ? List<dynamic>.from((rawData['items'] as List?) ?? [])
              : ApiService.ensureList(rawData);
          setState(() {
            _messages = msgs;
            _loadingChat = false;
          });
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollToBottom(),
          );
        }
        return;
      }

      await ApiService().fetchDataWithCache('/messages/$chatId', (
        data,
        isCached, {
        bool hasError = false,
      }) {
        if (!mounted || _activeChat?['id'] != chatId) return;
        if (data != null) {
          List<dynamic> msgs;
          if (data is Map && data.containsKey('items')) {
            msgs = List<dynamic>.from((data['items'] as List?) ?? []);
          } else {
            msgs = ApiService.ensureList(data);
          }
          setState(() {
            _messages = msgs;
            _loadingChat = false;
          });
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollToBottom(),
          );
        }
      });
    } catch (e, st) {
      AppLogger.error('messaging_page', e, st);
    }
    if (mounted) setState(() => _loadingChat = false);
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _activeChat == null || _isSending) return;
    setState(() => _isSending = true);

    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final pendingMessage = {
      'id': tempId,
      'from': 'me',
      'text': text,
      'time': 'Just now',
      'status': 'sending',
    };

    _msgCtrl.clear();
    setState(() => _messages.add(pendingMessage));
    _scrollToBottom();

    try {
      final res = await ApiService().post(
        '/messages/${_activeChat!['id']}',
        data: {'text': text},
      );
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        final Map<String, dynamic> serverMsg = (res.data is Map)
            ? Map<String, dynamic>.from(res.data as Map)
            : {};
        final mergedMsg = {
          'id': serverMsg['id'] ?? tempId,
          'from': serverMsg['from'] ?? 'me',
          'text': serverMsg['text'] ?? text,
          'time': serverMsg['time'] ?? 'Just now',
          'status': 'sent',
        };
        setState(() {
          final idx = _messages.indexWhere((m) => m['id'] == tempId);
          if (idx != -1) {
            _messages[idx] = mergedMsg;
          } else {
            _messages.add(mergedMsg);
          }
        });
        _scrollToBottom();
        _bustConversationsCache();
        _fetchConversations(showLoading: false);
        _loadMessages(
          showLoading: false,
          bypassCache: true,
        ).then((_) => _scrollToBottom());
      }
    } catch (e, st) {
      AppLogger.error('messaging_page', e, st);
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == tempId);
        if (idx != -1) {
          _messages[idx] = {
            ..._messages[idx],
            'status': 'failed',
            'time': 'Failed to send',
          };
        }
      });
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutQuad,
      );
    }
  }

  void _bustConversationsCache() {
    ApiService.deleteCacheKey('cache_v1_messages/conversations');
  }

  Widget _buildMessageStatusIndicator(Map<String, dynamic> msg) {
    final status = msg['status']?.toString() ?? 'sent';
    final icon = status == 'sending'
        ? Icons.access_time_rounded
        : status == 'failed'
        ? Icons.error_outline_rounded
        : Icons.done_all_rounded;
    final color = status == 'sending'
        ? Colors.white70
        : status == 'failed'
        ? const Color(0xFFFECACA)
        : Colors.white;

    return Icon(icon, size: 12, color: color);
  }

  String _getInitials(Map<String, dynamic>? chat) {
    if (chat == null) return '?';
    if (chat['initials'] != null && chat['initials'].toString().isNotEmpty) {
      return chat['initials'].toString();
    }
    final name = chat['name']?.toString() ?? '';
    if (name.trim().isEmpty) return '?';
    return name
        .trim()
        .split(' ')
        .where((n) => n.isNotEmpty)
        .map((n) => n[0])
        .take(2)
        .join()
        .toUpperCase();
  }

  Widget _buildEmptyChatPlaceholder(Color primary) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? CubagColors.ink : const Color(0xFFFAF7F2),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: primary.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 44,
                  color: primary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Member Messages',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : CubagColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Select a conversation to exchange direct messages with fellow CUBAG members & the secretariat.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white70 : CubagColors.muted,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(Color primary, {required bool isWide}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E120B) : Colors.white;
    final inputBg = isDark ? const Color(0xFF281710) : const Color(0xFFF4EEE6);
    final borderCol = isDark ? const Color(0xFF3E2417) : const Color(0xFFE5DDD3);
    final textCol = isDark ? Colors.white : CubagColors.ink;
    final subTextCol = isDark ? Colors.white70 : CubagColors.muted;
    final hintCol = isDark ? Colors.white54 : const Color(0xFF5F6B7E);

    return Container(
      color: cardBg,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        children: [
          // Search box
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: inputBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderCol, width: 1.0),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: hintCol,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _applySearch(v)),
                    decoration: InputDecoration(
                      hintText: 'Search messages',
                      hintStyle: TextStyle(
                        color: hintCol,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: TextStyle(
                      color: textCol,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (_search.isNotEmpty)
                  Semantics(button: true, label: 'Clear search', child: GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      setState(() => _applySearch(''));
                    },
                    child: Icon(
                      Icons.cancel_rounded,
                      color: hintCol,
                      size: 18,
                    ),
                  )),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Conversation list items
          if (_filteredConversations.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: primary.withAlpha(15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _search.isEmpty ? 'No messages yet' : 'No results found',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: textCol,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _search.isEmpty
                            ? 'Start a conversation from the members directory.'
                            : 'Try searching by a different name or keyword.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: subTextCol,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _filteredConversations.length,
                separatorBuilder: (ctx, i) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final conv = _filteredConversations[i];
                  final initials = _getInitials(
                    Map<String, dynamic>.from(conv),
                  );
                  final unread = (conv['unread'] ?? 0) as int;
                  final isActive =
                      _activeChat?['id']?.toString() == conv['id']?.toString();

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _openChat(Map<String, dynamic>.from(conv)),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isActive && isWide
                              ? primary.withAlpha(isDark ? 35 : 15)
                              : (isDark ? const Color(0xFF24150D) : const Color(0xFFFAF7F2)),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isActive && isWide
                                ? primary.withAlpha(100)
                                : (isDark ? const Color(0xFF381F13) : const Color(0xFFEDE4DA)),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    primary,
                                    const Color(0xFFD94000),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  initials,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          conv['name']?.toString() ?? '',
                                          style: TextStyle(
                                            fontWeight: unread > 0
                                                ? FontWeight.w800
                                                : FontWeight.w700,
                                            fontSize: 15,
                                            color: textCol,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (conv['time'] != null)
                                        Text(
                                          conv['time'].toString(),
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: hintCol,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          conv['lastMsg']?.toString() ??
                                              'Tap to start conversation',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: unread > 0 ? textCol : subTextCol,
                                            fontWeight: unread > 0
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      if (unread > 0) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: CubagColors.lapsed,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            '$unread',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleBlockActiveChat({required bool block}) async {
    final chat = _activeChat;
    final id = chat?['id'];
    if (id == null) return;
    if (block) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Block this member?'),
          content: const Text('They will no longer be able to send you messages.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(d, true), child: const Text('Block')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      final res = block
          ? await ApiService().post('messages/$id/block')
          : await ApiService().delete('messages/$id/block');
      if (!mounted) return;
      final okStatus = (res.statusCode ?? 500) < 300;
      if (okStatus) setState(() => _activeChat = {...?_activeChat, 'blocked': block});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(okStatus
            ? (block ? 'Member blocked.' : 'Member unblocked.')
            : 'Could not update. Please try again.'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update. Please try again.')),
      );
    }
  }

  Future<void> _reportActiveChat() async {
    final id = _activeChat?['id'];
    if (id == null) return;
    const reasons = {
      'spam': 'Spam',
      'harassment': 'Harassment or bullying',
      'abusive': 'Abusive or offensive language',
      'fraud': 'Fraud or scam',
      'inappropriate': 'Inappropriate content',
      'other': 'Something else',
    };
    String reason = 'spam';
    final detailsCtrl = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: const Text('Report member'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadioGroup<String>(
                  groupValue: reason,
                  onChanged: (v) => setD(() => reason = v ?? reason),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final e in reasons.entries)
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: e.key,
                          title: Text(e.value),
                        ),
                    ],
                  ),
                ),
                TextField(
                  controller: detailsCtrl,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: 'Add details (optional)'),
                ),
                const Text('Reporting also blocks this member.', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(d, true), child: const Text('Report')),
          ],
        ),
      ),
    );
    final details = detailsCtrl.text.trim();
    detailsCtrl.dispose();
    if (submit != true) return;
    try {
      final res = await ApiService().post('messages/$id/report', data: {
        'reason': reason,
        'details': details,
        'block': true,
      });
      if (!mounted) return;
      final okStatus = (res.statusCode ?? 500) < 300;
      if (okStatus) setState(() => _activeChat = {...?_activeChat, 'blocked': true});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(okStatus
            ? 'Thank you. The Secretariat will review this report.'
            : 'Could not send the report. Please try again.'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send the report. Please try again.')),
      );
    }
  }

  Widget _buildChat(Color primary, {required bool isWide}) {
    final initials = _getInitials(_activeChat);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? const Color(0xFF23140D) : Colors.white;
    final chatBg = isDark ? const Color(0xFF170D08) : const Color(0xFFF7F3EE);
    final borderCol = isDark ? const Color(0xFF3E2417) : const Color(0xFFE5DDD3);
    final textCol = isDark ? Colors.white : CubagColors.ink;
    final subTextCol = isDark ? Colors.white70 : CubagColors.muted;
    final receivedBubbleBg = isDark ? const Color(0xFF281710) : Colors.white;
    final receivedBubbleBorder =
        isDark ? const Color(0xFF3D251A) : const Color(0xFFE2D6CB);
    final inputBarBg = isDark ? const Color(0xFF23140D) : Colors.white;
    final inputFieldBg = isDark ? CubagColors.ink : const Color(0xFFF3ECE4);
    final hintCol = isDark ? Colors.white54 : const Color(0xFF5F6B7E);

    return Column(
      children: [
        // Chat Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: headerBg,
            border: Border(bottom: BorderSide(color: borderCol, width: 1.0)),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                if (!isWide)
                  IconButton(
                    tooltip: 'Back',
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: textCol,
                      size: 18,
                    ),
                    onPressed: () => setState(() {
                      _activeChat = null;
                      _messages = [];
                    }),
                  ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [primary, const Color(0xFFD94000)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
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
                        _activeChat!['name']?.toString() ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: textCol,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _activeChat!['company']?.toString() ?? 'CUBAG Member',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: subTextCol,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // UGC safety (Apple 1.2 / Google Play): report & block.
                PopupMenuButton<String>(
                  tooltip: 'More options',
                  icon: Icon(Icons.more_vert_rounded, color: textCol),
                  onSelected: (v) {
                    if (v == 'report') _reportActiveChat();
                    if (v == 'block') _toggleBlockActiveChat(block: true);
                    if (v == 'unblock') _toggleBlockActiveChat(block: false);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'report', child: Text('Report member')),
                    if (_activeChat?['blocked'] == true)
                      const PopupMenuItem(value: 'unblock', child: Text('Unblock member'))
                    else
                      const PopupMenuItem(value: 'block', child: Text('Block member')),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Message List View
        Expanded(
          child: Container(
            color: chatBg,
            child: _loadingChat
                ? Center(child: CircularProgressIndicator(color: primary))
                : _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Say hello to ${(_activeChat!['name']?.toString() ?? 'Member').split(' ').first}!',
                        style: TextStyle(
                          color: subTextCol,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (ctx, constraints) {
                      return ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        itemCount: _messages.length,
                        itemBuilder: (ctx, i) {
                          final msg = _messages[i];
                          final isMe = msg['from'] == 'me';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              mainAxisAlignment: isMe
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth * 0.78,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: isMe
                                        ? LinearGradient(
                                            colors: [
                                              primary,
                                              const Color(0xFFE64A00),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          )
                                        : null,
                                    color: isMe ? null : receivedBubbleBg,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(16),
                                      topRight: const Radius.circular(16),
                                      bottomLeft: isMe
                                          ? const Radius.circular(16)
                                          : const Radius.circular(4),
                                      bottomRight: isMe
                                          ? const Radius.circular(4)
                                          : const Radius.circular(16),
                                    ),
                                    border: isMe
                                        ? null
                                        : Border.all(
                                            color: receivedBubbleBorder,
                                            width: 1.0,
                                          ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withAlpha(isDark ? 20 : 6),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: isMe
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    children: [
                                      SelectableText(
                                        (msg['text']?.toString() ?? '').isEmpty
                                            ? '(empty message)'
                                            : msg['text'].toString(),
                                        style: TextStyle(
                                          color: isMe ? Colors.white : textCol,
                                          fontSize: 14.5,
                                          height: 1.35,
                                          fontWeight: isMe
                                              ? FontWeight.w500
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      if (msg['time'] != null)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            Text(
                                              msg['time'].toString(),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isMe
                                                    ? Colors.white70
                                                    : hintCol,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            if (isMe) ...[
                                              const SizedBox(width: 4),
                                              _buildMessageStatusIndicator(msg),
                                            ],
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ),

        // Message Input Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: inputBarBg,
            border: Border(top: BorderSide(color: borderCol, width: 1.0)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: inputFieldBg,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: borderCol, width: 1.0),
                    ),
                    child: Center(
                      child: TextField(
                        controller: _msgCtrl,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: TextStyle(
                            color: hintCol,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: TextStyle(
                          color: textCol,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  color: primary,
                  shape: const CircleBorder(),
                  child: Semantics(button: true, label: 'Send message', child: InkWell(
                    borderRadius: BorderRadius.circular(100),
                    onTap: _isSending ? null : _send,
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      child: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                    ),
                  )),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 900;
    final dividerCol = isDark
        ? const Color(0xFF3E2417)
        : const Color(0xFFE5DDD3);

    return AppLayout(
      title: 'Messages',
      scrollable: false,
      child: _loading
          ? ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: 8,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, _) => const ShimmerListTile(),
            )
          : isWide
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Row(
                  children: [
                    SizedBox(width: 360, child: _buildList(primary, isWide: true)),
                    Container(width: 1.0, color: dividerCol),
                    Expanded(
                      child: _activeChat == null
                          ? _buildEmptyChatPlaceholder(primary)
                          : _buildChat(primary, isWide: true),
                    ),
                  ],
                ),
              ),
            )
          : (_activeChat == null
                ? _buildList(primary, isWide: false)
                : _buildChat(primary, isWide: false)),
    );
  }
}
