import 'package:flutter/material.dart';
// Import the screens you will create

import 'screens/people_detection_screen.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 2; // Start on People Detection screen

  // List of screens for the bottom navigation
  // Each screen corresponds to a tab in the BottomNavigationBar
  static final List<Widget> _widgetOptions = <Widget>[
 
    const PeopleDetectionScreen(),

  ];

  // Method to handle BottomNavigationBar item taps
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vision Assistant'),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      // --- BOTTOM NAVIGATION BAR ---
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[

          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'People',
          ),

        
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).primaryColor,
        unselectedItemColor: Colors.grey,
        // Ensure large, readable labels
        selectedLabelStyle: const TextStyle(fontSize: 16),
        unselectedLabelStyle: const TextStyle(fontSize: 14),
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed, // Show all labels
      ),
    );
  }
}