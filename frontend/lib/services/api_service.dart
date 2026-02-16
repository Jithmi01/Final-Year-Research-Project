// lib/services/api_service.dart - INTEGRATED WITH VOICE RECOGNITION
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class ApiService {
  // IMPORTANT: Update this IP address to match your integrated project's IP
  static const String baseUrl = 'http://192.168.1.100:5000/api';
  static const String serverUrl = 'http://192.168.1.100:5000';
  
  // Timeout settings
  static const Duration timeout = Duration(seconds: 30);
  static const Duration longTimeout = Duration(seconds: 60);
  static const Duration voiceTimeout = Duration(seconds: 120);

  // =====================================================================
  // FACE DETECTION ENDPOINTS (EXISTING - UNCHANGED)
  // =====================================================================
  
  /// Quick face detection for voice feedback
  static Future<Map<String, dynamic>> quickFaceDetect(File imageFile) async {
    try {
      if (!await imageFile.exists()) {
        throw Exception('Image file does not exist');
      }
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/integrated-face/quick-detect'),
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
        throw Exception(error['error'] ?? 'Quick detection failed');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
  
  /// Complete face analysis when user taps screen
  static Future<Map<String, dynamic>> analyzeFace(File imageFile) async {
    try {
      if (!await imageFile.exists()) {
        throw Exception('Image file does not exist');
      }
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/integrated-face/analyze'),
      );
      
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );
      
      print('📤 Sending face analysis request...');
      
      var streamedResponse = await request.send().timeout(longTimeout);
      var response = await http.Response.fromStream(streamedResponse);
      
      print('📥 Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        var error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Face analysis failed');
      }
    } catch (e) {
      print('❌ Face analysis error: $e');
      throw Exception('Network error: $e');
    }
  }

  // Age & Gender Detection
  static Future<Map<String, dynamic>> detectAgeGender(File imageFile) async {
    try {
      if (!await imageFile.exists()) {
        throw Exception('Image file does not exist');
      }
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/age-gender/detect'),
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
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
   
  // Face Recognition - Register Person (IMAGES ONLY)
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
  
  // Face Recognition - Get Registered People (FACES ONLY)
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
  
  // Face Recognition - Delete Person (FACE)
  static Future<void> deletePerson(String personId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/face-recognition/person/$personId'),
      ).timeout(timeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to delete person');
      }
    } on TimeoutException {
      throw Exception('Connection timeout');
    } on SocketException {
      throw Exception('Cannot connect to server');
    } catch (e) {
      throw Exception('Error deleting person: $e');
    }
  }

  // Face Recognition - Update Person Name
  static Future<void> updatePersonName(String personId, String newName) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/face-recognition/person/$personId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'name': newName}),
      ).timeout(timeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to update person');
      }
    } on TimeoutException {
      throw Exception('Connection timeout');
    } on SocketException {
      throw Exception('Cannot connect to server');
    } catch (e) {
      throw Exception('Error updating person: $e');
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
  
  // =====================================================================
  // ⭐ VOICE RECOGNITION ENDPOINTS (NEW)
  // =====================================================================
  
  /// Register new user with voice samples
  static Future<Map<String, dynamic>> registerVoiceUser({
    required String name,
    required List<String> audioFilePaths,
  }) async {
    try {
      print('📤 Registering voice user: $name');
      print('📊 Audio files: ${audioFilePaths.length}');
      
      final uri = Uri.parse('$baseUrl/voice/register');
      final request = http.MultipartRequest('POST', uri);
      
      // Add user name
      request.fields['name'] = name;
      
      // Add audio files
      for (int i = 0; i < audioFilePaths.length; i++) {
        print('📁 Adding file ${i + 1}: ${audioFilePaths[i]}');
        
        final file = File(audioFilePaths[i]);
        
        if (!await file.exists()) {
          print('❌ File not found: ${audioFilePaths[i]}');
          throw Exception('Audio file not found: ${audioFilePaths[i]}');
        }
        
        final multipartFile = await http.MultipartFile.fromPath(
          'audio_files',
          file.path,
          filename: 'sample_$i.wav',
        );
        request.files.add(multipartFile);
      }
      
      print('⏳ Sending voice registration request...');
      
      final streamedResponse = await request.send().timeout(voiceTimeout);
      final response = await http.Response.fromStream(streamedResponse);
      
      print('📥 Response status: ${response.statusCode}');
      
      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        print('✅ Voice registration successful!');
        return data;
      } else {
        final errorData = json.decode(response.body);
        print('❌ Voice registration failed: ${errorData['error']}');
        throw Exception(errorData['error'] ?? 'Voice registration failed');
      }
    } on SocketException {
      throw Exception('Cannot connect to server');
    } on TimeoutException {
      throw Exception('Request timeout');
    } catch (e) {
      throw Exception('Voice registration error: $e');
    }
  }
  
  /// Identify speaker from voice sample
  static Future<Map<String, dynamic>> identifyVoiceSpeaker({
    required String audioFilePath,
    double? threshold,
  }) async {
    try {
      print('📤 Identifying speaker...');
      print('📁 Audio file: $audioFilePath');
      
      final uri = Uri.parse('$baseUrl/voice/identify');
      final request = http.MultipartRequest('POST', uri);
      
      final file = File(audioFilePath);
      
      if (!await file.exists()) {
        throw Exception('Audio file not found');
      }
      
      final multipartFile = await http.MultipartFile.fromPath(
        'audio_file',
        file.path,
        filename: 'identify.wav',
      );
      request.files.add(multipartFile);
      
      if (threshold != null) {
        request.fields['threshold'] = threshold.toString();
      }
      
      print('⏳ Sending identification request...');
      
      final streamedResponse = await request.send().timeout(longTimeout);
      final response = await http.Response.fromStream(streamedResponse);
      
      print('📥 Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Identification completed');
        return data;
      } else {
        final errorData = json.decode(response.body);
        print('❌ Identification failed: ${errorData['error']}');
        throw Exception(errorData['error'] ?? 'Identification failed');
      }
    } on SocketException {
      throw Exception('Cannot connect to server');
    } on TimeoutException {
      throw Exception('Request timeout');
    } catch (e) {
      throw Exception('Identification error: $e');
    }
  }
  
  /// Get all registered voice users
  static Future<Map<String, dynamic>> getRegisteredVoiceUsers() async {
    try {
      print('📤 Fetching voice users...');
      
      final uri = Uri.parse('$baseUrl/voice/users');
      final response = await http.get(uri).timeout(timeout);
      
      print('📥 Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Found ${data['total']} voice users');
        return data;
      } else {
        throw Exception('Failed to fetch voice users');
      }
    } on SocketException {
      throw Exception('Cannot connect to server');
    } catch (e) {
      throw Exception('Error fetching voice users: $e');
    }
  }
  
  /// Delete voice user by name
  static Future<void> deleteVoiceUser(String name) async {
    try {
      final uri = Uri.parse('$baseUrl/voice/users/${Uri.encodeComponent(name)}');
      final response = await http.delete(uri).timeout(timeout);
      
      if (response.statusCode != 200) {
        throw Exception('Failed to delete voice user');
      }
    } catch (e) {
      throw Exception('Error deleting voice user: $e');
    }
  }
  
  /// Verify speaker identity
  static Future<Map<String, dynamic>> verifyVoiceSpeaker({
    required String audioFilePath,
    required String claimedName,
    double? threshold,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/voice/verify');
      final request = http.MultipartRequest('POST', uri);
      
      request.fields['claimed_name'] = claimedName;
      if (threshold != null) {
        request.fields['threshold'] = threshold.toString();
      }
      
      final file = File(audioFilePath);
      final multipartFile = await http.MultipartFile.fromPath(
        'audio_file',
        file.path,
        filename: 'verify.wav',
      );
      request.files.add(multipartFile);
      
      final streamedResponse = await request.send().timeout(longTimeout);
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Verification failed');
      }
    } catch (e) {
      throw Exception('Verification error: $e');
    }
  }
  
  // =====================================================================
  // HEALTH CHECK
  // =====================================================================
  
  // Health Check
  static Future<bool> checkHealth() async {
    try {
      var response = await http.get(
        Uri.parse('$serverUrl/health'),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        return data['status'] == 'healthy';
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }
  
  // Test connection with detailed error messages
  static Future<Map<String, dynamic>> testConnection() async {
    try {
      var response = await http.get(
        Uri.parse('$serverUrl/health'),
      ).timeout(const Duration(seconds: 5));
      
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
            '3. IP address is correct'
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e'
      };
    }
  }
}