import 'package:flutter/material.dart';
import '../services/voice_navigation_service.dart';

class HelpScreen extends StatefulWidget {
  final VoiceNavigationService voiceService;

  const HelpScreen({
    Key? key,
    required this.voiceService,
  }) : super(key: key);

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  bool _isNarrating = false;

  final List<HelpItem> helpItems = [
    HelpItem(
      title: 'Getting Started',
      description: 'Welcome to Smart Assistant! This app helps you with currency detection, bill scanning, and face recognition using voice commands.',
      icon: Icons.start,
    ),
    HelpItem(
      title: 'Voice Navigation',
      description: 'Tap the microphone button in the top right or bottom right corner. Speak commands like currency, face detection, or wallet to navigate.',
      icon: Icons.mic,
    ),
    HelpItem(
      title: 'Currency & Bills',
      description: 'Detect currency denominations using AR. Scan bills. Or manage your smart wallet. Say currency to access this feature.',
      icon: Icons.monetization_on,
    ),
    HelpItem(
      title: 'Face Detection',
      description: 'Recognize faces. Detect age and gender. Or analyze facial attributes. Say face detection to start.',
      icon: Icons.face,
    ),
    HelpItem(
      title: 'How to Use Voice Commands',
      description: 'After tapping the microphone, wait for Listening to appear in red. Speak clearly and wait for confirmation.',
      icon: Icons.record_voice_over,
    ),
    HelpItem(
      title: 'Tips & Tricks',
      description: 'Speak slowly and clearly. Use feature names like currency home, bill scanner, or wallet question and answer for specific functions.',
      icon: Icons.lightbulb,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _startNarration();
  }

  Future<void> _startNarration() async {
    setState(() {
      _isNarrating = true;
    });

    try {
      // Welcome message
      await widget.voiceService.speak(
        'Welcome to the Help Guide. This app provides voice controlled access to currency detection, bill scanning, and face recognition features.'
      );

      // Pause between welcome and help items
      await Future.delayed(Duration(milliseconds: 800));

      // Narrate each help item
      for (int i = 0; i < helpItems.length; i++) {
        if (!mounted) return;

        HelpItem item = helpItems[i];
        
        // Speak title
        await widget.voiceService.speak('Topic ${i + 1}. ${item.title}');
        
        // Pause between title and description
        await Future.delayed(Duration(milliseconds: 700));
        
        // Speak description - split by period or comma for better delivery
        String description = item.description;
        
        // Split by '. ' first, then by ', ' if needed
        List<String> parts = description.split(RegExp(r'(?<=[.!?,])\s+'));
        
        for (String part in parts) {
          if (part.trim().isNotEmpty) {
            String textToSpeak = part.trim();
            // Add period if missing
            if (!textToSpeak.endsWith('.') && 
                !textToSpeak.endsWith('!') && 
                !textToSpeak.endsWith('?')) {
              textToSpeak += '.';
            }
            
            await widget.voiceService.speak(textToSpeak);
            await Future.delayed(Duration(milliseconds: 400));
          }
        }
        
        // Pause between items
        await Future.delayed(Duration(milliseconds: 1000));
      }

      // Final message
      if (mounted) {
        await widget.voiceService.speak(
          'End of help guide. Tap the back button to return to the home screen.'
        );
        
        setState(() {
          _isNarrating = false;
        });
      }
    } catch (e) {
      print('Error during narration: $e');
      if (mounted) {
        setState(() {
          _isNarrating = false;
        });
      }
    }
  }

  void _repeatNarration() {
    _startNarration();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('📖 Help & Guide', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Narration Status
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isNarrating 
                    ? Colors.blue[900]?.withOpacity(0.3)
                    : Colors.green[900]?.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isNarrating ? Colors.blue : Colors.green,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isNarrating ? Icons.volume_up : Icons.check_circle,
                    color: _isNarrating ? Colors.blue : Colors.green,
                    size: 24,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isNarrating 
                          ? '🔊 Speaking Help Instructions...'
                          : '✅ Narration Complete',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 20),
            
            // Repeat Button
            ElevatedButton.icon(
              onPressed: _repeatNarration,
              icon: Icon(Icons.replay),
              label: Text('Repeat Narration'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            
            SizedBox(height: 24),
            
            // Help Items
            Text(
              'Help Topics',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            
            SizedBox(height: 16),
            
            ...helpItems.map((item) => _buildHelpCard(item)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpCard(HelpItem item) {
    return Card(
      elevation: 4,
      margin: EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.grey[800]!, Colors.grey[900]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue[700]?.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      item.icon,
                      color: Colors.blue[400],
                      size: 28,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                item.description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

class HelpItem {
  final String title;
  final String description;
  final IconData icon;

  HelpItem({
    required this.title,
    required this.description,
    required this.icon,
  });
}
