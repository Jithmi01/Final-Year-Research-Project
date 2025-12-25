// lib/widgets/voice_test_widget.dart
// Optional: Add this to any page to test voice navigation independently

import 'package:flutter/material.dart';
import '../services/voice_navigation_service.dart';

class VoiceTestWidget extends StatefulWidget {
  const VoiceTestWidget({Key? key}) : super(key: key);

  @override
  State<VoiceTestWidget> createState() => _VoiceTestWidgetState();
}

class _VoiceTestWidgetState extends State<VoiceTestWidget> {
  final VoiceNavigationService _voiceService = VoiceNavigationService();
  int _commandCount = 0;
  String _lastCommand = 'None';
  String _lastRoute = 'None';
  bool _isProcessing = false;
  List<String> _commandHistory = [];

  @override
  void initState() {
    super.initState();
    _initVoice();
  }

  Future<void> _initVoice() async {
    await _voiceService.initialize();
    setState(() {});
  }

  void _testVoice() async {
    if (_isProcessing || _voiceService.isListening) {
      print('⚠️ Already processing');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    await _voiceService.startListening(
      onResult: (command) async {
        setState(() {
          _commandCount++;
          _lastCommand = command;
          _commandHistory.insert(0, '${DateTime.now().toString().substring(11, 19)}: $command');
          if (_commandHistory.length > 10) _commandHistory.removeLast();
        });

        String? route = _voiceService.parseNavigationCommand(command);
        setState(() {
          _lastRoute = route ?? 'No match';
          _isProcessing = false;
        });

        if (route != null) {
          await _voiceService.speak("Command recognized: ${_voiceService.getRouteName(route)}");
        } else {
          await _voiceService.speak("Command not recognized");
        }
      },
      onError: (error) {
        setState(() {
          _isProcessing = false;
          _commandHistory.insert(0, '${DateTime.now().toString().substring(11, 19)}: ERROR - $error');
        });
      },
    );

    // Timeout safety
    Future.delayed(Duration(seconds: 10), () {
      if (mounted && _isProcessing) {
        setState(() => _isProcessing = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'Voice Navigation Test',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            
            Divider(height: 24),
            
            // Stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStat('Commands', _commandCount.toString(), Colors.blue),
                _buildStat('Status', _voiceService.isListening ? 'Listening' : 'Ready', 
                    _voiceService.isListening ? Colors.red : Colors.green),
                _buildStat('Initialized', _voiceService.isInitialized ? 'Yes' : 'No',
                    _voiceService.isInitialized ? Colors.green : Colors.red),
              ],
            ),
            
            SizedBox(height: 16),
            
            // Last command info
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Last Command:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(_lastCommand, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('Parsed Route:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(_lastRoute, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            
            SizedBox(height: 16),
            
            // Test button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_isProcessing || _voiceService.isListening) ? null : _testVoice,
                icon: Icon(_voiceService.isListening ? Icons.mic : Icons.mic_none),
                label: Text(_voiceService.isListening ? 'Listening...' : 'Test Voice Command'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _voiceService.isListening ? Colors.red : Colors.blue,
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            
            SizedBox(height: 16),
            
            // Command history
            Text(
              'Command History:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[700]!),
              ),
              child: _commandHistory.isEmpty
                  ? Center(
                      child: Text(
                        'No commands yet',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _commandHistory.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Text(
                            _commandHistory[index],
                            style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
                          ),
                        );
                      },
                    ),
            ),
            
            SizedBox(height: 16),
            
            // Test commands
            ExpansionTile(
              title: Text('Test Commands', style: TextStyle(fontSize: 14)),
              children: [
                _buildCommandChip('currency'),
                _buildCommandChip('AR currency detector'),
                _buildCommandChip('bill scanner'),
                _buildCommandChip('wallet'),
                _buildCommandChip('face detection'),
                _buildCommandChip('age gender'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey)),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildCommandChip(String command) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Chip(
        label: Text('Say: "$command"'),
        backgroundColor: Colors.blue[900],
      ),
    );
  }

  @override
  void dispose() {
    _voiceService.dispose();
    super.dispose();
  }
}

// Usage: Add to any page
// Add this in your page's build method:
// VoiceTestWidget(),