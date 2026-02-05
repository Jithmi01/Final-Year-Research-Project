// lib/services/document_service.dart
// Document Reading API Service

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/document_model.dart';

class DocumentService {
  static const String baseUrl = 'http://192.168.8.143:5000'; // Change to your backend IP
  
  // ========================================================================
  // CONTINUOUS READING
  // ========================================================================
  
  Future<ContinuousReadResult> readContinuous(File imageFile) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/document/read_continuous'),
      );

      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('Continuous read response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ContinuousReadResult.fromJson(data);
      } else {
        final error = json.decode(response.body);
        return ContinuousReadResult(
          success: false,
          text: '',
          newText: '',
          shouldSpeak: false,
          voicePrompt: error['voice_prompt'] ?? 'Error reading document',
        );
      }
    } catch (e) {
      print('Continuous read error: $e');
      return ContinuousReadResult(
        success: false,
        text: '',
        newText: '',
        shouldSpeak: false,
        voicePrompt: 'Network error',
      );
    }
  }

  // ========================================================================
  // CAPTURE DOCUMENT
  // ========================================================================
  
  Future<DocumentData> captureDocument(File imageFile) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/document/capture'),
      );

      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('Capture document response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return DocumentData.fromJson(data);
      } else {
        final error = json.decode(response.body);
        return DocumentData(
          success: false,
          error: error['error'] ?? 'Capture failed',
          voicePrompt: error['voice_prompt'] ?? 'Failed to capture document',
          documentId: '',
          text: '',
          lines: [],
          metadata: DocumentMetadata.empty(),
          lineCount: 0,
        );
      }
    } catch (e) {
      print('Capture document error: $e');
      return DocumentData(
        success: false,
        error: e.toString(),
        voicePrompt: 'Network error',
        documentId: '',
        text: '',
        lines: [],
        metadata: DocumentMetadata.empty(),
        lineCount: 0,
      );
    }
  }

  // ========================================================================
  // VOICE Q&A
  // ========================================================================
  
  Future<QuestionAnswer> askQuestion(String question) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/document/ask'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'question': question}),
      );

      print('Ask question response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return QuestionAnswer.fromJson(data);
      } else {
        final error = json.decode(response.body);
        return QuestionAnswer(
          success: false,
          answer: error['error'] ?? 'No answer found',
          confidence: 0.0,
          voicePrompt: error['voice_prompt'] ?? 'Could not answer question',
          foundInLine: null,
        );
      }
    } catch (e) {
      print('Ask question error: $e');
      return QuestionAnswer(
        success: false,
        answer: 'Network error',
        confidence: 0.0,
        voicePrompt: 'Network error',
        foundInLine: null,
      );
    }
  }

  // ========================================================================
  // DOCUMENT MANAGEMENT
  // ========================================================================
  
  Future<DocumentData?> getCurrentDocument() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/document/get_current'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['has_document'] == true) {
          return DocumentData.fromJson(data['document']);
        }
        return null;
      }
      return null;
    } catch (e) {
      print('Get current document error: $e');
      return null;
    }
  }

  Future<bool> clearDocument() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/document/clear'),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Clear document error: $e');
      return false;
    }
  }
}