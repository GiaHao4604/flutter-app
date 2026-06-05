import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_application_1/services/admin_api_service.dart';
import 'package:flutter_application_1/screens/admin/user_management.dart';
// Note: We might need a report management screen later

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final AdminApiService _apiService = AdminApiService();
  
  bool _isLoading = true;
  String _errorMessage = '';
  
  int _totalUsers = 0;
  int _totalAdmins = 0;
  int _totalPosts = 0;
  List<FlSpot> _userSpots = [];
  List<String> _dateLabels = [];
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }
  
  Future<void> _loadData() async {
    setState(() { _isLoading = true; _errorMessage = ''; });
    final result = await _apiService.getDashboardUsersChart();
    
    if (result.success && result.data != null) {
      _totalUsers = result.data['totalUsers'] ?? 0;
      _totalAdmins = result.data['totalAdmins'] ?? 0;
      _totalPosts = result.data['totalPosts'] ?? 0;
      
      final List<dynamic> chartData = result.data['chartData'] ?? [];
      _userSpots.clear();
      _dateLabels.clear();
      
      for (int i = 0; i < chartData.length; i++) {
        final item = chartData[i];
        _userSpots.add(FlSpot(i.toDouble(), (item['count'] as num).toDouble()));
        // Format date string to something shorter, e.g., 'MM/dd'
        String rawDate = item['date'] ?? '';
        if (rawDate.length >= 10) {
          _dateLabels.add(rawDate.substring(5, 10).replaceAll('-', '/'));
        } else {
          _dateLabels.add(rawDate);
        }
      }
    } else {
      _errorMessage = result.message;
    }
    
    if (mounted) setState(() { _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(_errorMessage, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: const Text('Thử lại')),
          ],
        ),
      );
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bảng Điều Khiển Tổng Quan', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          
          // Row of Stat Cards
          Row(
            children: [
              Expanded(child: _buildStatCard('Người Dùng', _totalUsers.toString(), Icons.people, Colors.blue)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard('Quản Trị', _totalAdmins.toString(), Icons.admin_panel_settings, Colors.orange)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard('Bài Viết', _totalPosts.toString(), Icons.post_add, Colors.green)),
            ],
          ),
          
          const SizedBox(height: 32),
          const Text('Tăng trưởng Người Dùng (30 ngày)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          
          // User Growth Chart
          Container(
            height: 250,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: _userSpots.isEmpty 
              ? const Center(child: Text('Chưa có dữ liệu'))
              : _buildUserChart(),
          ),
          
          const SizedBox(height: 32),
          const Text('Quản lý Hệ Thống', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          
          // Navigation Buttons
          ListTile(
            leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.people, color: Colors.white)),
            title: const Text('Quản lý Người Dùng', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Khóa/Xóa hoặc cấp quyền Admin'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const UserManagementScreen()))
                .then((_) => _loadData());
            },
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const CircleAvatar(backgroundColor: Colors.redAccent, child: Icon(Icons.report, color: Colors.white)),
            title: const Text('Bài viết bị Báo cáo', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Duyệt hoặc xóa bài rác/spam'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tính năng quản lý Report đang phát triển')));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontSize: 12, color: color.withOpacity(0.8), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildUserChart() {
    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final int idx = value.toInt();
                if (idx >= 0 && idx < _dateLabels.length) {
                  // Hiển thị cách nhau nếu quá nhiều nhãn
                  if (_dateLabels.length > 7 && idx % (_dateLabels.length ~/ 5) != 0) {
                    return const SizedBox();
                  }
                  return Text(_dateLabels[idx], style: const TextStyle(fontSize: 10, color: Colors.grey));
                }
                return const SizedBox();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10, color: Colors.grey))),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: 0,
        lineBarsData: [
          LineChartBarData(
            spots: _userSpots,
            isCurved: true,
            color: Colors.blueAccent,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: Colors.blueAccent.withOpacity(0.2)),
          ),
        ],
      ),
    );
  }
}
