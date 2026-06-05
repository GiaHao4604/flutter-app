import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/chat_models.dart';
import 'package:flutter_application_1/screens/chat_detail_screen.dart';
import 'package:flutter_application_1/services/chat_api_service.dart';
import 'package:google_fonts/google_fonts.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key, required this.currentUserId});

  final int currentUserId;

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final ChatApiService _chatApiService = ChatApiService();
  List<ChatConversation> _conversations = [];
  bool _isLoading = true;
  String? _error;

  String _formatDate(String isoString) {
    if (isoString.isEmpty) return '';
    final dt = DateTime.tryParse(isoString);
    if (dt == null) return isoString.replaceFirst('T', ' ').split('.').first;
    final localDt = dt.toLocal();
    return '${localDt.hour.toString().padLeft(2, '0')}:${localDt.minute.toString().padLeft(2, '0')} ${localDt.day.toString().padLeft(2, '0')}/${localDt.month.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final result = await _chatApiService.getConversations();
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _error = result.message;
        _conversations = [];
        _isLoading = false;
      });
      return;
    }

    final rawData = result.data;
    final items = <ChatConversation>[];
    if (rawData is List) {
      for (final element in rawData) {
        if (element is Map<String, dynamic>) {
          items.add(ChatConversation.fromJson(element));
        }
      }
    }

    setState(() {
      _conversations = items;
      _isLoading = false;
    });
  }

  void _openConversation(ChatConversation conversation) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            currentUserId: widget.currentUserId,
            conversationId: conversation.conversationId,
            recipientId: conversation.partner.id,
            recipientName: conversation.partner.name,
            recipientAvatarUrl: conversation.partner.avatarUrl,
          ),
        ))
        .then((_) => _loadConversations());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 18),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Tin nhắn',
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        GestureDetector(
          onTap: _showNewChatDialog,
          child: Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF5B4BFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.edit_rounded, color: Colors.white, size: 20),
          ),
        ),
        GestureDetector(
          onTap: _loadConversations,
          child: const Icon(Icons.refresh, color: Colors.white),
        ),
      ],
    );
  }

  void _showNewChatDialog() {
    final searchController = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];
    bool isSearching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> doSearch(String query) async {
              if (query.trim().length < 2) {
                setSheetState(() {
                  searchResults = [];
                  isSearching = false;
                });
                return;
              }
              setSheetState(() => isSearching = true);
              final result = await _chatApiService.searchUsers(query.trim());
              final items = <Map<String, dynamic>>[];
              if (result.success && result.data is List) {
                for (final item in result.data) {
                  if (item is Map<String, dynamic>) items.add(item);
                }
              }
              setSheetState(() {
                searchResults = items;
                isSearching = false;
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Tin nhắn mới',
                        style: GoogleFonts.manrope(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: searchController,
                        autofocus: true,
                        style: GoogleFonts.manrope(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Tìm kiếm theo tên hoặc email...',
                          hintStyle: GoogleFonts.manrope(color: Colors.white38),
                          prefixIcon: const Icon(Icons.search, color: Colors.white54),
                          filled: true,
                          fillColor: const Color(0xFF1B1B1B),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (val) => doSearch(val),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: isSearching
                          ? const Center(child: CircularProgressIndicator(color: Colors.white))
                          : searchResults.isEmpty
                              ? Center(
                                  child: Text(
                                    'Nhập ít nhất 2 ký tự để tìm kiếm',
                                    style: GoogleFonts.manrope(color: Colors.white38),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: searchResults.length,
                                  itemBuilder: (_, i) {
                                    final user = searchResults[i];
                                    final userId = int.tryParse(user['id']?.toString() ?? '') ?? 0;
                                    final name = user['name']?.toString() ?? 'Người dùng';
                                    final avatarUrl = user['avatar_url']?.toString();
                                    return ListTile(
                                      leading: CircleAvatar(
                                        radius: 22,
                                        backgroundColor: const Color(0xFF222222),
                                        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                                        child: avatarUrl == null
                                            ? Text(
                                                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                                style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.w700),
                                              )
                                            : null,
                                      ),
                                      title: Text(name, style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.w600)),
                                      onTap: () {
                                        Navigator.pop(sheetContext);
                                        _openNewConversation(userId, name, avatarUrl);
                                      },
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openNewConversation(int recipientId, String recipientName, String? avatarUrl) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            currentUserId: widget.currentUserId,
            conversationId: null,
            recipientId: recipientId,
            recipientName: recipientName,
            recipientAvatarUrl: avatarUrl,
          ),
        ))
        .then((_) => _loadConversations());
  }


  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: GoogleFonts.manrope(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.white24),
            const SizedBox(height: 12),
            Text(
              'Chưa có cuộc trò chuyện nào.\nNhấn vào một cuộc trò chuyện để bắt đầu.',
              style: GoogleFonts.manrope(color: Colors.white60),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _conversations.length,
      separatorBuilder: (context, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final conversation = _conversations[index];
        return GestureDetector(
          onTap: () => _openConversation(conversation),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: const Color(0xFF222222),
                  backgroundImage: conversation.partner.avatarUrl != null
                      ? NetworkImage(conversation.partner.avatarUrl!)
                      : null,
                  child: conversation.partner.avatarUrl == null
                      ? Text(
                          conversation.partner.name.isEmpty
                              ? 'U'
                              : conversation.partner.name[0].toUpperCase(),
                          style: GoogleFonts.manrope(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              conversation.partner.name,
                              style: GoogleFonts.manrope(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(conversation.lastMessageTime),
                            style: GoogleFonts.manrope(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        conversation.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          color: const Color(0xA3FFFFFF),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (conversation.unreadCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFC700),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          conversation.unreadCount.toString(),
                          style: GoogleFonts.manrope(
                            color: Colors.black,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 16),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
