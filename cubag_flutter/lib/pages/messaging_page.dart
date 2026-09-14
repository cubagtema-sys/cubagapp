import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../services/api_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';

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
      // Find existing conversation or create a temporary one for the UI
      final existing = _conversations.firstWhere(
        (c) =>
            (c as Map?)?['id']?.toString() == widget.initialUserId.toString(),
        orElse: () => null,
      );

      if (existing != null) {
        _openChat(Map<String, dynamic>.from(existing as Map));
      } else {
        // If no existing conversation, we start one with whatever data we have
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

  /// Fetches the full message thread for _activeChat instantly using offline cache + background revalidation.
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
      'time': 'Sending...',
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
        // Safely convert res.data to a Map before spreading
        final Map<String, dynamic> serverMsg = (res.data is Map)
            ? Map<String, dynamic>.from(res.data as Map)
            : {};
        // Merge server data with 'sent' status — keep local text as fallback
        final mergedMsg = {
          'id': serverMsg['id'] ?? tempId,
          'from': serverMsg['from'] ?? 'me',
          'text': serverMsg['text'] ?? text, // always show the message text
          'time': serverMsg['time'] ?? '',
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
        // Bust conversations cache and refresh list so latest message shows
        _bustConversationsCache();
        _fetchConversations(showLoading: false);
        // Re-fetch full thread directly from server without overwriting state with stale cache
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
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Removes the conversations list from Hive cache so the next fetch is always fresh.
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
        ? Colors.white.withAlpha(180)
        : status == 'failed'
        ? const Color(0xFFfecaca)
        : const Color(0xFFFF5000);
    final iconColor = status == 'failed'
        ? const Color(0xFFf8fafc)
        : Colors.white;

    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(child: Icon(icon, size: 10, color: iconColor)),
    );
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
      color: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFf8fafc),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: primary.withAlpha(15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 48,
                color: primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Your Messages',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF281710),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a conversation from the list\nto start messaging.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: isDark ? Colors.white70 : const Color(0xFF64748b),
                fontSize: 15,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(Color primary, {required bool isWide}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
    final inputBg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFf1f5f9);
    final borderCol = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFcbd5e1).withAlpha(120);
    final dividerCol = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFf1f5f9);
    final textCol = isDark ? Colors.white : const Color(0xFF281710);
    final subTextCol = isDark ? Colors.white70 : const Color(0xFF64748b);
    final hintCol = isDark ? Colors.white54 : const Color(0xFF94a3b8);

    return Container(
      color: cardBg,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Search box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: inputBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderCol, width: 1.2),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _applySearch(v)),
              decoration: InputDecoration(
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: hintCol,
                  size: 20,
                ),
                hintText: 'Search conversations...',
                hintStyle: GoogleFonts.outfit(
                  color: hintCol,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                suffixIcon: _search.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() => _applySearch(''));
                        },
                        child: Icon(
                          Icons.clear_rounded,
                          color: hintCol,
                          size: 18,
                        ),
                      )
                    : null,
              ),
              style: GoogleFonts.outfit(
                color: textCol,
                fontSize: 15.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Conversation list items
          if (_filteredConversations.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: primary.withAlpha(10),
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
                      _search.isEmpty ? 'No messages' : 'No results found',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: textCol,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _search.isEmpty
                          ? 'Connect with members via the directory.'
                          : 'Try a different keyword search.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: subTextCol,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: _filteredConversations.length,
                separatorBuilder: (ctx, i) =>
                    Divider(height: 1, color: dividerCol),
                itemBuilder: (ctx, i) {
                  final conv = _filteredConversations[i];
                  final initials = _getInitials(
                    Map<String, dynamic>.from(conv),
                  );
                  final unread = (conv['unread'] ?? 0) as int;
                  final isActive =
                      _activeChat?['id']?.toString() == conv['id']?.toString();

                  return Container(
                    decoration: BoxDecoration(
                      color: isActive && isWide
                          ? primary.withAlpha(isDark ? 30 : 12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      onTap: () => _openChat(Map<String, dynamic>.from(conv)),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: isActive && isWide
                            ? primary
                            : primary.withAlpha(200),
                        child: Text(
                          initials,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      title: Text(
                        conv['name']?.toString() ?? '',
                        style: GoogleFonts.outfit(
                          fontWeight: unread > 0
                              ? FontWeight.w900
                              : FontWeight.w700,
                          fontSize: 15.5,
                          color: textCol,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          conv['lastMsg']?.toString() ?? 'No messages yet',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            color: unread > 0 ? textCol : subTextCol,
                            fontWeight: unread > 0
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (unread > 0)
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: Color(0xFFef4444),
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              child: Center(
                                child: Text(
                                  '$unread',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            )
                          else if (conv['time'] != null)
                            Text(
                              conv['time'].toString(),
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: hintCol,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
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

  Widget _buildChat(Color primary, {required bool isWide}) {
    final initials = _getInitials(_activeChat);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? const Color(0xFF281710) : Colors.white;
    final chatBg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFf8fafc);
    final borderCol = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFf1f5f9);
    final textCol = isDark ? Colors.white : const Color(0xFF281710);
    final subTextCol = isDark ? Colors.white70 : const Color(0xFF64748b);
    final receivedBubbleBg = isDark ? const Color(0xFF281710) : Colors.white;
    final receivedBubbleBorder = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFcbd5e1).withAlpha(80);
    final inputBarBg = isDark ? const Color(0xFF281710) : Colors.white;
    final inputFieldBg = isDark
        ? const Color(0xFF1A0F0A)
        : const Color(0xFFf8fafc);
    final inputFieldBorder = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFcbd5e1).withAlpha(100);
    final hintCol = isDark ? Colors.white54 : const Color(0xFF94a3b8);

    return Column(
      children: [
        // Chat Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: headerBg,
            border: Border(bottom: BorderSide(color: borderCol, width: 1.5)),
          ),
          child: Row(
            children: [
              if (!isWide)
                IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: subTextCol,
                    size: 18,
                  ),
                  onPressed: () => setState(() {
                    _activeChat = null;
                    _messages = [];
                  }),
                ),
              CircleAvatar(
                radius: 18,
                backgroundColor: primary,
                child: Text(
                  initials,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
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
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        fontSize: 16.5,
                        color: textCol,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _activeChat!['company']?.toString() ?? 'CUBAG Member',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: subTextCol,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
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
                    child: Text(
                      'Say hello to ${(_activeChat!['name']?.toString() ?? 'Member').split(' ').first}!',
                      style: GoogleFonts.outfit(
                        color: subTextCol,
                        fontWeight: FontWeight.w600,
                        fontSize: 15.5,
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
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              mainAxisAlignment: isMe
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                              children: [
                                Container(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth * 0.75,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isMe ? primary : receivedBubbleBg,
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
                                            width: 1.2,
                                          ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withAlpha(3),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: isMe
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (msg['text']?.toString() ?? '').isEmpty
                                            ? '(empty message)'
                                            : msg['text'].toString(),
                                        style: GoogleFonts.outfit(
                                          color: isMe ? Colors.white : textCol,
                                          fontSize: 15.5,
                                          height: 1.4,
                                          fontWeight: isMe
                                              ? FontWeight.w600
                                              : FontWeight.w500,
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
                                              style: GoogleFonts.outfit(
                                                fontSize: 11,
                                                color: isMe
                                                    ? Colors.white.withAlpha(
                                                        180,
                                                      )
                                                    : hintCol,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (isMe) ...[
                                              const SizedBox(width: 8),
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
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            color: inputBarBg,
            border: Border(top: BorderSide(color: borderCol, width: 1.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: inputFieldBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: inputFieldBorder, width: 1.2),
                  ),
                  child: TextField(
                    controller: _msgCtrl,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: GoogleFonts.outfit(
                        color: hintCol,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    style: GoogleFonts.outfit(
                      color: textCol,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: primary,
                shape: const CircleBorder(),
                child: InkWell(
                  borderRadius: BorderRadius.circular(100),
                  onTap: _isSending ? null : _send,
                  child: Container(
                    width: 38,
                    height: 38,
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
                            size: 16,
                          ),
                  ),
                ),
              ),
            ],
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
        ? const Color(0xFF4D2D20)
        : const Color(0xFFf1f5f9);

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
          ? Row(
              children: [
                SizedBox(width: 320, child: _buildList(primary, isWide: true)),
                Container(width: 1.5, color: dividerCol),
                Expanded(
                  child: _activeChat == null
                      ? _buildEmptyChatPlaceholder(primary)
                      : _buildChat(primary, isWide: true),
                ),
              ],
            )
          : (_activeChat == null
                ? _buildList(primary, isWide: false)
                : _buildChat(primary, isWide: false)),
    );
  }
}
