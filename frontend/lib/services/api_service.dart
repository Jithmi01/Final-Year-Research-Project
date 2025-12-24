// frontend/lib/services/api_service.dart
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class ApiService {
  // ✅ CORRECT IP ADDRESS - Your server IP
  static const String baseUrl = 'http://192.168.8.143:5000/api';
  static const String serverUrl = 'http://192.168.8.143:5000';
  
  // Timeout settings
  static const Duration timeout = Duration(seconds: 30);
  
  // Age & Gender Detection
  static Future<Map<String, dynamic>> detectAgeGender(File imageFile) async {
    try {
      // Validate file exists
      if (!await imageFile.exists()) {
        throw Exception('Image file does not exist');
      }
      
      // Create multipart request
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/age-gender/detect'),
      );
      
      // Add image file
      request.files.add(
        await http.MultipartFile.fromPath(
          'image', 
          imageFile.path,
        ),
      );
      
      // Send request with timeout
      var streamedResponse = await request.send().timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException('Request timed out after ${timeout.inSeconds} seconds');
        },
      );
      
      // Get response
      var response = await http.Response.fromStream(streamedResponse);
      
      // Parse response
      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        
        // Validate response structure
        if (!data.containsKey('gender') || !data.containsKey('age_group')) {
          throw Exception('Invalid response format from server');
        }
        
        return data;
      } else if (response.statusCode == 400) {
        var error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Detection failed');
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } on TimeoutException catch (e) {
      throw Exception('Connection timeout. Please check your network.');
    } on SocketException catch (e) {
      throw Exception('Cannot connect to server. Please check:\n'
          '1. Server is running on $serverUrl\n'
          '2. Phone and computer are on same WiFi\n'
          '3. IP address is correct');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
  
  // Face Recognition - Register Person
  static Future<Map<String, dynamic>> registerPerson(
    String name,
    List<File> images,
  ) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/face-recognition/register'),
      );
      
      request.fields['name'] = name;
      
      for (int i = 0; i < images.length; i++) {
        if (await images[i].exists()) {
          request.files.add(
            await http.MultipartFile.fromPath('image${i + 1}', images[i].path),
          );
        }
      }
      
      var streamedResponse = await request.send().timeout(timeout);
      var response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        var error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Registration failed');
      }
    } on TimeoutException {
      throw Exception('Connection timeout');
    } on SocketException {
      throw Exception('Cannot connect to server');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
  
  // Face Recognition - Recognize Person
  static Future<Map<String, dynamic>> recognizePerson(File imageFile) async {
    try {
      if (!await imageFile.exists()) {
        throw Exception('Image file does not exist');
      }
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/face-recognition/recognize'),
      );
      
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );
      
      var streamedResponse = await request.send().timeout(timeout);
      var response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        var error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Recognition failed');
      }
    } on TimeoutException {
      throw Exception('Connection timeout');
    } on SocketException {
      throw Exception('Cannot connect to server');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
  
  // Face Recognition - Get Registered People
  static Future<Map<String, dynamic>> getRegisteredPeople() async {
    try {
      var response = await http.get(
        Uri.parse('$baseUrl/face-recognition/people'),
      ).timeout(timeout);
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        var error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to fetch people');
      }
    } on TimeoutException {
      throw Exception('Connection timeout');
    } on SocketException {
      throw Exception('Cannot connect to server');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
  
  // Attributes Detection
  static Future<Map<String, dynamic>> detectAttributes(File imageFile) async {
    try {
      if (!await imageFile.exists()) {
        throw Exception('Image file does not exist');
      }
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/attributes/detect'),
      );
      
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );
      
      var streamedResponse = await request.send().timeout(timeout);
      var response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        var error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Detection failed');
      }
    } on TimeoutException {
      throw Exception('Connection timeout');
    } on SocketException {
      throw Exception('Cannot connect to server');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
  
  // ✅ FIXED: Health Check - Now checks the correct endpoint
  static Future<bool> checkHealth() async {
    try {
      print('Checking health at: $serverUrl/health');
      
      var response = await http.get(
        Uri.parse('$serverUrl/health'),
      ).timeout(const Duration(seconds: 5));
      
      print('Health check response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        // Parse the response to verify services are active
        var data = json.decode(response.body);
        print('Health data: $data');
        
        // Check if blind_assistant services are active
        if (data.containsKey('systems') && 
            data['systems'].containsKey('blind_assistant')) {
          var services = data['systems']['blind_assistant']['services'];
          print('Blind Assistant services: $services');
          
          // Check if at least one service is active
          if (services is List && services.isNotEmpty) {
            return true;
          }
        }
        
        // Fallback: if we got 200, server is running
        return true;
      }
      
      return false;
    } catch (e) {
      print('Health check error: $e');
      return false;
    }
  }
  
  // ✅ FIXED: Test connection with detailed error messages
  static Future<Map<String, dynamic>> testConnection() async {
    try {
      print('Testing connection to: $serverUrl/health');
      
      var response = await http.get(
        Uri.parse('$serverUrl/health'),
      ).timeout(const Duration(seconds: 5));
      
      print('Test connection response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        
        return {
          'success': true,
          'message': 'Connected to server successfully',
          'data': data
        };
      } else {
        return {
          'success': false,
          'message': 'Server returned error: ${response.statusCode}'
        };
      }
    } on TimeoutException {
      return {
        'success': false,
        'message': 'Connection timeout. Server may be down or unreachable.'
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'Cannot connect to server.\n'
            'Please check:\n'
            '1. Server is running at $serverUrl\n'
            '2. Both devices on same WiFi\n'
            '3. IP address is correct (192.168.8.143)'
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e'
      };
    }
  }
}