import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/admin_api_service.dart';
import 'package:flutter_application_1/services/auth_api_service.dart';
import 'package:flutter_application_1/services/auth_session_service.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final AdminApiService _apiService = AdminApiService();
  final AuthSessionService _sessionService = AuthSessionService();
  final AuthApiService _authApiService = AuthApiService();
  
  bool _isLoading = true;
  List<dynamic> _users = [];
  String _errorMessage = '';
  String _currentUserRole = 'admin';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() { _isLoading = true; _errorMessage = ''; });
    
    // Lấy thông tin tài khoản hiện tại trước
    final token = await _sessionService.getToken();
    if (token != null) {
      final meResult = await _authApiService.getMe(token: token);
      if (meResult.success) {
        _currentUserRole = meResult.data?['role'] ?? 'admin';
      }
    }

    final result = await _apiService.getAllUsers();
    
    if (result.success && result.data != null) {
      _users = List.from(result.data);
      _users.sort((a, b) {
        final Map<String, int> roleWeight = {
          'director_admin': 3,
          'admin': 2,
          'user': 1,
        };
        final roleA = a['role'] ?? 'user';
        final roleB = b['role'] ?? 'user';
        final weightA = roleWeight[roleA] ?? 0;
        final weightB = roleWeight[roleB] ?? 0;
        
        if (weightA != weightB) {
          return weightB.compareTo(weightA);
        }
        
        final nameA = (a['name'] ?? '').toString().toLowerCase();
        final nameB = (b['name'] ?? '').toString().toLowerCase();
        return nameA.compareTo(nameB);
      });
    } else {
      _errorMessage = result.message;
    }
    
    if (mounted) setState(() { _isLoading = false; });
  }

  Future<void> _toggleRole(int userId, String currentRole) async {
    final result = await _apiService.toggleUserRole(userId);
    _showSnackBar(result.message);
    if (result.success) _loadUsers();
  }

  Future<void> _toggleBan(int userId, int isBanned) async {
    final result = await _apiService.toggleUserBan(userId);
    _showSnackBar(result.message);
    if (result.success) _loadUsers();
  }

  Future<void> _deleteUser(int userId, String userName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc chắn muốn xóa vĩnh viễn tài khoản "$userName"? Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      )
    );

    if (confirm == true) {
      final result = await _apiService.deleteUser(userId);
      _showSnackBar(result.message);
      if (result.success) _loadUsers();
    }
  }

  Future<void> _transferDirector(int userId, String userName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chuyển giao quyền Giám đốc'),
        content: Text('Bạn có chắc chắn muốn chuyển giao toàn quyền Giám đốc (Director Admin) cho "$userName"?\n\nSau khi chuyển giao, tài khoản của bạn sẽ bị giáng cấp xuống thành Admin Xanh.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Đồng ý', style: TextStyle(color: Colors.red)),
          ),
        ],
      )
    );

    if (confirm == true) {
      final result = await _apiService.transferDirectorAdmin(userId);
      _showSnackBar(result.message);
      if (result.success) {
        // Tự động load lại danh sách và quyền
        _loadUsers();
      }
    }
  }

  void _showSnackBar(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Quản lý Người Dùng', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadUsers),
        ],
      ),
      body: Theme(
        data: ThemeData.light(),
        child: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
            ? Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)))
            : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                final bool isDirector = user['role'] == 'director_admin';
                final bool isAdmin = user['role'] == 'admin';
                final bool isBanned = user['is_banned'] == 1;
                
                final bool iAmDirector = _currentUserRole == 'director_admin';
                // Nếu mình là Admin Xanh, mình ko có quyền sửa Admin Đỏ
                final bool canEdit = !(isDirector && !iAmDirector);
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundImage: user['avatar_url'] != null ? NetworkImage(user['avatar_url']) : null,
                      backgroundColor: isDirector ? Colors.red[100] : (isAdmin ? Colors.blue[100] : Colors.grey[300]),
                      child: user['avatar_url'] == null 
                          ? Icon(
                              isDirector ? Icons.shield : (isAdmin ? Icons.admin_panel_settings : Icons.person), 
                              color: isDirector ? Colors.red : (isAdmin ? Colors.blue : Colors.grey)
                            )
                          : null,
                    ),
                    title: Row(
                      children: [
                        Expanded(child: Text(user['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold))),
                        if (isDirector || isAdmin)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: isDirector ? Colors.red : Colors.blue, borderRadius: BorderRadius.circular(10)),
                            child: const Text('ADMIN', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        if (isBanned)
                          Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
                            child: const Text('BANNED', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          )
                      ],
                    ),
                    subtitle: Text(user['email'] ?? ''),
                    trailing: !canEdit ? null : PopupMenuButton<String>(
                      onSelected: (val) {
                        if (val == 'role') {
                          _toggleRole(user['id'], user['role']);
                        } else if (val == 'ban') {
                          _toggleBan(user['id'], user['is_banned']);
                        } else if (val == 'delete') {
                          _deleteUser(user['id'], user['name']);
                        } else if (val == 'transfer') {
                          _transferDirector(user['id'], user['name']);
                        }
                      },
                      itemBuilder: (ctx) => [
                        if (iAmDirector && isAdmin)
                          PopupMenuItem(
                            value: 'transfer',
                            child: Row(
                              children: [
                                const Icon(Icons.star, color: Colors.red, size: 20),
                                const SizedBox(width: 8),
                                const Text('Chuyển giao Giám đốc', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        if (iAmDirector && isAdmin) const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'role',
                          child: Row(
                            children: [
                              Icon(isAdmin ? Icons.arrow_downward : Icons.arrow_upward, color: isAdmin ? Colors.orange : Colors.blue, size: 20),
                              const SizedBox(width: 8),
                              Text(isAdmin ? 'Thu hồi quyền Admin' : 'Cấp quyền Admin'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'ban',
                          child: Row(
                            children: [
                              Icon(isBanned ? Icons.lock_open : Icons.lock, color: isBanned ? Colors.green : Colors.red, size: 20),
                              const SizedBox(width: 8),
                              Text(isBanned ? 'Mở khóa tài khoản' : 'Khóa tài khoản'),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_forever, color: Colors.red, size: 20),
                              SizedBox(width: 8),
                              Text('Xóa vĩnh viễn', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      ),
    );
  }
}
