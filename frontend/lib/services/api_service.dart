// lib/services/api_service.dart
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class ApiService {
  // IMPORTANT: Update this IP address to your computer's local IP
  // Windows: Open CMD and type 'ipconfig' -> look for IPv4 Address
  // Mac/Linux: Open Terminal and type 'ifconfig' -> look for inet
  static const String baseUrl = 'http://192.168.43.98:5000/api';
  
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
          // Optionally specify content type
          // contentType: MediaType('image', 'jpeg'),
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
          '1. Server is running on $baseUrl\n'
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
  
  // Health Check
  static Future<bool> checkHealth() async {
    try {
      var response = await http.get(
        Uri.parse('http://192.168.43.98:5000/health'),
      ).timeout(const Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
  
  // Test connection with detailed error messages
  static Future<Map<String, dynamic>> testConnection() async {
    try {
      var response = await http.get(
        Uri.parse('http://192.168.43.98:5000/health'),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': 'Connected to server successfully',
          'data': json.decode(response.body)
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
            '1. Server is running\n'
            '2. Both devices on same WiFi\n'
            '3. IP address is correct (192.168.43.98)'
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e'
      };
    }
  }
}