// lib/services/audio_service.dart
// Audio recording service for voice recognition

import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  
  /// Request microphone permission
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }
  
  /// Check if microphone permission is granted
  Future<bool> hasPermission() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }
  
  /// Check microphone permission status
  Future<String> getPermissionStatus() async {
    final status = await Permission.microphone.status;
    
    if (status.isGranted) {
      return 'granted';
    } else if (status.isDenied) {
      return 'denied';
    } else if (status.isPermanentlyDenied) {
      return 'permanently_denied';
    } else {
      return 'not_requested';
    }
  }
  
  /// Open app settings
  Future<void> openSettings() async {
    await openAppSettings();
  }
  
  /// Start recording audio
  Future<bool> startRecording() async {
    try {
      print('🎤 Starting recording...');
      
      if (!await hasPermission()) {
        print('⚠️ No microphone permission');
        final granted = await requestPermission();
        if (!granted) {
          print('❌ Permission denied');
          return false;
        }
      }
      
      if (await _recorder.isRecording()) {
        print('⚠️ Already recording, stopping first');
        await _recorder.stop();
      }
      
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${directory.path}/recording_$timestamp.wav';
      
      print('📁 Recording path: $path');
      
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          bitRate: 128000,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: path,
      );
      
      print('✅ Recording started');
      return true;
      
    } catch (e) {
      print('❌ Error starting recording: $e');
      return false;
    }
  }
  
  /// Stop recording and return file path
  Future<String?> stopRecording() async {
    try {
      print('Stopping recording...');
      
      if (!await _recorder.isRecording()) {
        print('⚠️ Not currently recording');
        return null;
      }
      
      final path = await _recorder.stop();
      
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          final size = await file.length();
          print('Recording saved: ${size / 1024} KB');
          print('Path: $path');
        } else {
          print('Recording file not found');
          return null;
        }
      }
      
      return path;
      
    } catch (e) {
      print('Error stopping recording: $e');
      return null;
    }
  }
  
  /// Check if currently recording
  Future<bool> isRecording() async {
    try {
      return await _recorder.isRecording();
    } catch (e) {
      return false;
    }
  }
  
  /// Dispose recorder
  Future<void> dispose() async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
      await _recorder.dispose();
      print('Audio recorder disposed');
    } catch (e) {
      print('Error disposing recorder: $e');
    }
  }
  
  /// Delete audio file
  Future<void> deleteAudioFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        print('🗑️ Deleted audio file: $path');
      }
    } catch (e) {
      print(' Error deleting file: $e');
    }
  }
  
  /// Get audio file size in KB
  Future<double> getFileSize(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.length();
        return bytes / 1024;
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }
  
  /// Check if file exists
  Future<bool> fileExists(String path) async {
    try {
      final file = File(path);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }
}