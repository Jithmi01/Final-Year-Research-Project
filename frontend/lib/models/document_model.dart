// lib/models/document_model.dart
// Document Reading Data Models

class ContinuousReadResult {
  final bool success;
  final String text;
  final String newText;
  final bool shouldSpeak;
  final String voicePrompt;
  final double confidence;
  final int regions;

  ContinuousReadResult({
    required this.success,
    required this.text,
    required this.newText,
    required this.shouldSpeak,
    required this.voicePrompt,
    this.confidence = 0.0,
    this.regions = 0,
  });

  factory ContinuousReadResult.fromJson(Map<String, dynamic> json) {
    return ContinuousReadResult(
      success: json['success'] ?? false,
      text: json['text'] ?? '',
      newText: json['new_text'] ?? '',
      shouldSpeak: json['should_speak'] ?? false,
      voicePrompt: json['voice_prompt'] ?? '',
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      regions: json['regions'] ?? 0,
    );
  }
}

class DocumentData {
  final bool success;
  final String? error;
  final String voicePrompt;
  final String documentId;
  final String text;
  final List<String> lines;
  final DocumentMetadata metadata;
  final int lineCount;

  DocumentData({
    required this.success,
    this.error,
    required this.voicePrompt,
    required this.documentId,
    required this.text,
    required this.lines,
    required this.metadata,
    required this.lineCount,
  });

  factory DocumentData.fromJson(Map<String, dynamic> json) {
    return DocumentData(
      success: json['success'] ?? false,
      error: json['error'],
      voicePrompt: json['voice_prompt'] ?? '',
      documentId: json['document_id'] ?? '',
      text: json['text'] ?? '',
      lines: List<String>.from(json['lines'] ?? []),
      metadata: DocumentMetadata.fromJson(json['metadata'] ?? {}),
      lineCount: json['line_count'] ?? 0,
    );
  }
}

class DocumentMetadata {
  final List<String> dates;
  final List<String> amounts;
  final List<String> emails;
  final List<String> phones;
  final List<String> keywords;

  DocumentMetadata({
    required this.dates,
    required this.amounts,
    required this.emails,
    required this.phones,
    required this.keywords,
  });

  factory DocumentMetadata.fromJson(Map<String, dynamic> json) {
    return DocumentMetadata(
      dates: List<String>.from(json['dates'] ?? []),
      amounts: List<String>.from(json['amounts'] ?? []),
      emails: List<String>.from(json['emails'] ?? []),
      phones: List<String>.from(json['phones'] ?? []),
      keywords: List<String>.from(json['keywords'] ?? []),
    );
  }

  factory DocumentMetadata.empty() {
    return DocumentMetadata(
      dates: [],
      amounts: [],
      emails: [],
      phones: [],
      keywords: [],
    );
  }
}

class QuestionAnswer {
  final bool success;
  final String answer;
  final double confidence;
  final String voicePrompt;
  final int? foundInLine;

  QuestionAnswer({
    required this.success,
    required this.answer,
    required this.confidence,
    required this.voicePrompt,
    this.foundInLine,
  });

  factory QuestionAnswer.fromJson(Map<String, dynamic> json) {
    return QuestionAnswer(
      success: json['success'] ?? false,
      answer: json['answer'] ?? '',
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      voicePrompt: json['voice_prompt'] ?? '',
      foundInLine: json['found_in_line'],
    );
  }
}