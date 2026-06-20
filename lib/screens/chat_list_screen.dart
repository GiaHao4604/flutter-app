import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/chat_models.dart';
import 'package:flutter_application_1/screens/chat_detail_screen.dart';
import 'package:flutter_application_1/services/chat_api_service.dart';
import 'package:google_fonts/google_fonts.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key, required this.currentUserId, this.onBack});

  final int currentUserId;
  final VoidCallback? onBack;

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ChatApiService _chatApiService = ChatApiService();
  List<ChatConversation> _conversations = [];
  bool _isLoading = true;
  String? _error;

  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearchingUsers = false;

  String _formatDate(String isoString) {
    if (isoString.isEmpty) return '';
    final dt = DateTime.tryParse(isoString);
    if (dt == null) return isoString.replaceFirst('T', ' ').split('.').first;
    final localDt = dt.toLocal();
    final now = DateTime.now();

    final hours = localDt.hour.toString().padLeft(2, '0');
    final minutes = localDt.minute.toString().padLeft(2, '0');

    if (localDt.year == now.year && localDt.month == now.month && localDt.day == now.day) {
      return '$hours:$minutes';
    } else {
      return '$hours:$minutes, ${localDt.day} THG ${localDt.month}';
    }
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
    super.build(context);
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

  Future<void> _doSearch(String query) async {
    if (query.trim().length < 2) {
      setState(() {
        _searchResults = [];
        _isSearchingUsers = false;
      });
      return;
    }
    setState(() => _isSearchingUsers = true);
    final result = await _chatApiService.searchUsers(query.trim());
    final items = <Map<String, dynamic>>[];
    if (result.success && result.data is List) {
      for (final item in result.data) {
        if (item is Map<String, dynamic>) items.add(item);
      }
    }
    if (!mounted) return;
    setState(() {
      _searchResults = items;
      _isSearchingUsers = false;
    });
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: widget.onBack,
            ),
            Text(
              'Chat - MoneyLife',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          style: GoogleFonts.manrope(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Tìm kiếm theo tên...',
            hintStyle: GoogleFonts.manrope(color: Colors.white38),
            prefixIcon: const Icon(Icons.search, color: Colors.white54),
            filled: true,
            fillColor: const Color(0xFF1B1B1B),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          onChanged: (val) => _doSearch(val),
        ),
      ],
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
    if (_searchController.text.trim().isNotEmpty) {
      if (_isSearchingUsers) {
        return const Center(child: CircularProgressIndicator(color: Colors.white));
      }
      if (_searchResults.isEmpty) {
         return Center(
            child: Text(
              'Không tìm thấy kết quả',
              style: GoogleFonts.manrope(color: Colors.white38),
            ),
          );
      }
      return ListView.builder(
        itemCount: _searchResults.length,
        itemBuilder: (_, i) {
          final user = _searchResults[i];
          final userId = int.tryParse(user['id']?.toString() ?? '') ?? 0;
          final name = user['name']?.toString() ?? 'Người dùng';
          final avatarUrl = user['avatar_url']?.toString();
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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
              FocusScope.of(context).unfocus();
              _searchController.clear();
              _openNewConversation(userId, name, avatarUrl);
            },
          );
        },
      );
    }

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
                                fontWeight: conversation.unreadCount > 0 ? FontWeight.w800 : FontWeight.w700,
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
                          color: conversation.unreadCount > 0 ? Colors.white : const Color(0xA3FFFFFF),
                          fontWeight: conversation.unreadCount > 0 ? FontWeight.w700 : FontWeight.w400,
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
