import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/admin_api_service.dart';
import 'package:flutter_application_1/services/post_api_service.dart';

class ReportedPostsScreen extends StatefulWidget {
  const ReportedPostsScreen({super.key});

  @override
  State<ReportedPostsScreen> createState() => _ReportedPostsScreenState();
}

class _ReportedPostsScreenState extends State<ReportedPostsScreen> {
  final AdminApiService _apiService = AdminApiService();
  List<Map<String, dynamic>> _reports = <Map<String, dynamic>>[];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    final result = await _apiService.getReportedPosts();
    if (result.success) {
      final List<dynamic> data = result.data ?? [];
      _reports = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      _errorMessage = result.message;
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _resolveReport(int reportId) async {
    setState(() => _isLoading = true);
    final result = await _apiService.resolveReport(reportId);
    if (!mounted) return;
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã bỏ qua báo cáo thành công')),
      );
      _loadReports();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: ${result.message}')),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deletePost(int postId, int reportId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa bài viết vi phạm?'),
        content: const Text('Hành động này sẽ xóa bài viết vĩnh viễn và hủy bỏ mọi dữ liệu lịch, ngân sách liên quan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa bài', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      // Delete post (this will cascade delete associated calendar and transaction data)
      final deleteResult = await _apiService.deletePost(postId);
      if (!mounted) return;
      if (deleteResult.success) {
        // Also mark this report as resolved
        await _apiService.resolveReport(reportId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa bài viết và dữ liệu tài chính liên quan thành công')),
        );
        _loadReports();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xóa bài viết: ${deleteResult.message}')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          title: const Text('Quản lý Báo cáo Bài viết', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: _isLoading && _reports.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage.isNotEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text(_errorMessage, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _loadReports, child: const Text('Thử lại')),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadReports,
                    child: _reports.isEmpty
                        ? const Center(
                            child: Text(
                              'Không có báo cáo nào chưa xử lý.',
                              style: TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _reports.length,
                            itemBuilder: (context, index) {
                              final report = _reports[index];
                              final reportId = int.tryParse(report['report_id']?.toString() ?? '') ?? 0;
                              final postId = int.tryParse(report['post_id']?.toString() ?? '') ?? 0;
                              final reason = report['reason']?.toString() ?? 'Không có lý do';
                              final caption = report['caption']?.toString() ?? '';
                              final imageUrl = PostApiService.resolveMediaUrl(report['image_url']?.toString());
                              final reporterName = report['reporter_name']?.toString() ?? 'Ẩn danh';
                              final authorName = report['author_name']?.toString() ?? 'Người dùng';
                              final status = report['status']?.toString() ?? 'pending';

                              return Card(
                                margin: const EdgeInsets.only(bottom: 16),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Người đăng: $authorName',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: status == 'pending' ? Colors.orange.shade100 : Colors.green.shade100,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              status == 'pending' ? 'Chờ duyệt' : 'Đã xử lý',
                                              style: TextStyle(
                                                color: status == 'pending' ? Colors.orange.shade800 : Colors.green.shade800,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Người báo cáo: $reporterName',
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                      ),
                                      const Divider(height: 24),
                                      Text(
                                        'Lý do báo cáo:',
                                        style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        reason,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      const Divider(height: 24),
                                      if (caption.isNotEmpty) ...[
                                        Text(
                                          caption,
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                      if (imageUrl.isNotEmpty) ...[
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(
                                            imageUrl,
                                            height: 200,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              return Container(
                                                height: 150,
                                                color: Colors.grey.shade200,
                                                alignment: Alignment.center,
                                                child: const Icon(Icons.broken_image, size: 48, color: Colors.grey),
                                              );
                                            },
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                      ],
                                      if (status == 'pending')
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            TextButton.icon(
                                              onPressed: () => _resolveReport(reportId),
                                              icon: const Icon(Icons.check, color: Colors.green),
                                              label: const Text('Bỏ qua', style: TextStyle(color: Colors.green)),
                                            ),
                                            const SizedBox(width: 8),
                                            ElevatedButton.icon(
                                              onPressed: () => _deletePost(postId, reportId),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red,
                                                foregroundColor: Colors.white,
                                              ),
                                              icon: const Icon(Icons.delete_forever),
                                              label: const Text('Xóa bài viết'),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
      ),
    );
  }
}
