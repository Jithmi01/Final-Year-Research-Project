// lib/screens/face_detection/people_dashboard_screen.dart - WITH VOICE USERS
import 'package:flutter/material.dart';
import '/services/api_service.dart';
import 'person_registration_screen.dart';

class PeopleDashboardScreen extends StatefulWidget {
  const PeopleDashboardScreen({super.key});

  @override
  State<PeopleDashboardScreen> createState() => _PeopleDashboardScreenState();
}

class _PeopleDashboardScreenState extends State<PeopleDashboardScreen> {
  List<Map<String, dynamic>> faceUsers = [];
  List<Map<String, dynamic>> voiceUsers = [];
  bool isLoading = true;
  int currentTab = 0; // 0 = All, 1 = Face, 2 = Voice
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAllUsers();
  }

  Future<void> _loadAllUsers() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    
    try {
      // Load face users
      final faceResponse = await ApiService.getRegisteredPeople();
      faceUsers = List<Map<String, dynamic>>.from(faceResponse['people'] ?? []);
      
      // Load voice users
      try {
        final voiceResponse = await ApiService.getRegisteredVoiceUsers();
        voiceUsers = List<Map<String, dynamic>>.from(voiceResponse['users'] ?? []);
      } catch (e) {
        print('Voice users not available: $e');
        voiceUsers = [];
      }
      
      setState(() => isLoading = false);
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load users: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<Map<String, dynamic>> _getFilteredUsers() {
    if (currentTab == 1) {
      return faceUsers;
    } else if (currentTab == 2) {
      return voiceUsers;
    } else {
      // Combine both, removing duplicates by name
      final Map<String, Map<String, dynamic>> combined = {};
      
      for (var face in faceUsers) {
        combined[face['name']] = {
          ...face,
          'hasFace': true,
          'hasVoice': false,
        };
      }
      
      for (var voice in voiceUsers) {
        if (combined.containsKey(voice['name'])) {
          combined[voice['name']]!['hasVoice'] = true;
          combined[voice['name']]!['voiceData'] = voice;
        } else {
          combined[voice['name']] = {
            ...voice,
            'hasFace': false,
            'hasVoice': true,
          };
        }
      }
      
      return combined.values.toList();
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final hasFace = user['hasFace'] ?? (currentTab == 1 || currentTab == 0);
    final hasVoice = user['hasVoice'] ?? (currentTab == 2);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2C2C2C),
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete User', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'Delete ${user['name']}?\n\n'
          '${hasFace && hasVoice ? 'Both face and voice data will be deleted.' : hasFace ? 'Face data will be deleted.' : 'Voice data will be deleted.'}',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => isLoading = true);
              
              try {
                if (hasFace && faceUsers.any((u) => u['name'] == user['name'])) {
                  await ApiService.deletePerson(user['id'] ?? user['name']);
                }
                
                if (hasVoice && voiceUsers.any((u) => u['name'] == user['name'])) {
                  await ApiService.deleteVoiceUser(user['name']);
                }
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('User deleted successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
                
                await _loadAllUsers();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to delete: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
                setState(() => isLoading = false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredUsers = _getFilteredUsers();
    final totalFace = faceUsers.length;
    final totalVoice = voiceUsers.length;
    
    return Scaffold(
      backgroundColor: Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: Color(0xFF1E1E1E),
        title: Text('People Dashboard', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadAllUsers,
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Stats Cards
                Container(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          icon: Icons.face,
                          label: 'Face Users',
                          value: totalFace.toString(),
                          color: Colors.blue,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          icon: Icons.mic,
                          label: 'Voice Users',
                          value: totalVoice.toString(),
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),

                // Tab Selector
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Color(0xFF3C3C3C),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _buildTab('All', 0)),
                      Expanded(child: _buildTab('Face', 1)),
                      Expanded(child: _buildTab('Voice', 2)),
                    ],
                  ),
                ),

                SizedBox(height: 16),

                // User List
                Expanded(
                  child: filteredUsers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline, size: 80, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'No registered users',
                                style: TextStyle(color: Colors.grey, fontSize: 18),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filteredUsers.length,
                          itemBuilder: (context, index) {
                            final user = filteredUsers[index];
                            final hasFace = user['hasFace'] ?? (user.containsKey('images'));
                            final hasVoice = user['hasVoice'] ?? (user.containsKey('num_samples'));
                            
                            return Card(
                              color: Color(0xFF2C2C2C),
                              margin: EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: Colors.orange[700],
                                          radius: 28,
                                          child: Text(
                                            user['name'][0].toUpperCase(),
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                user['name'],
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  if (hasFace) ...[
                                                    Icon(Icons.face, color: Colors.blue, size: 16),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      '${user['images'] ?? 0} photos',
                                                      style: TextStyle(color: Colors.grey[400], fontSize: 14),
                                                    ),
                                                    SizedBox(width: 12),
                                                  ],
                                                  if (hasVoice) ...[
                                                    Icon(Icons.mic, color: Colors.green, size: 16),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      '${user['num_samples'] ?? user['voiceData']?['num_samples'] ?? 0} voice',
                                                      style: TextStyle(color: Colors.grey[400], fontSize: 14),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          icon: Icon(Icons.more_vert, color: Colors.white),
                                          color: Color(0xFF3C3C3C),
                                          onSelected: (value) {
                                            if (value == 'delete') {
                                              _deleteUser(user);
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.delete, color: Colors.red, size: 20),
                                                  SizedBox(width: 8),
                                                  Text('Delete', style: TextStyle(color: Colors.white)),
                                                ],
                                              ),
                                            ),
                                          ],
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
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => PersonRegistrationScreen()),
          );
          if (result == true) _loadAllUsers();
        },
        backgroundColor: Colors.orange[700],
        icon: Icon(Icons.person_add),
        label: Text('Register'),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.8), color.withOpacity(0.6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 32),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isSelected = currentTab == index;
    return GestureDetector(
      onTap: () => setState(() => currentTab = index),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange[700] : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}