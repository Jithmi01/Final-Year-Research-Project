// lib/wallet_qa_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:http/http.dart' as http;
import '../../main.dart';

class WalletQAPage extends StatefulWidget {
  const WalletQAPage({Key? key}) : super(key: key);

  @override
  _WalletQAPageState createState() => _WalletQAPageState();
}

class _WalletQAPageState extends State<WalletQAPage> {
  FlutterTts flutterTts = FlutterTts();
  SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  String _lastWords = "";
  String _currentAnswer = "";
  bool _isLoadingAnswer = false;

  final TextEditingController _textController = TextEditingController();

  final List<String> _helpQuestions = [
    "What is my balance?",
    "How much did I spend today?",
    "How much did I spend this week?",
    "What is my total income?",
    "Show my recent transactions",
  ];

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _setupTts();
  }

  void _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onError: (error) {
          print('STT Error: $error');
          if (mounted) {
            setState(() => _lastWords = "Speech error occurred");
          }
        },
        onStatus: (status) {
          print('STT Status: $status');
          if (status == 'done' && mounted) {
            setState(() {});
          }
        },
      );
      
      if (_speechEnabled) {
        _speak("Wallet Q and A ready. Tap the mic to ask a question.");
      } else {
        _speak("Speech recognition not available.");
      }
    } catch (e) {
      print("Error initializing speech: $e");
      _speak("Could not start speech recognition.");
    }
    
    if (mounted) setState(() {});
  }

  void _setupTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setVolume(1.0);
  }

  Future<void> _speak(String text) async {
    if (mounted) {
      setState(() => _currentAnswer = text);
    }
    await flutterTts.speak(text);
  }

  void _startListening() async {
    if (!_speechEnabled) {
      _speak("Speech recognition is not enabled.");
      return;
    }
    
    // Stop any current speech
    await flutterTts.stop();
    
    if (mounted) {
      setState(() {
        _lastWords = "Listening...";
        _currentAnswer = "";
      });
    }
    
    await _speechToText.listen(
      onResult: _onSpeechResult,
      listenFor: Duration(seconds: 10),
      pauseFor: Duration(seconds: 3),
      partialResults: true, // Changed to true for better feedback
      localeId: "en_US",
      cancelOnError: true,
      listenMode: ListenMode.confirmation,
    );
  }

  void _onSpeechResult(result) {
    if (!mounted) return;
    
    setState(() {
      _lastWords = result.recognizedWords;
    });
    
    if (result.finalResult && _lastWords.isNotEmpty) {
      print("Final recognized words: $_lastWords");
      _askWalletQuestion(_lastWords);
    } else if (result.finalResult && _lastWords.isEmpty) {
      _speak("I didn't catch that. Please try again.");
    }
  }

  Future<void> _askWalletQuestion(String question) async {
    if (question.isEmpty) return;

    setState(() {
      _isLoadingAnswer = true;
      _currentAnswer = "Thinking...";
    });

    String endpoint = "$API_URL/ask_wallet_question";
    bool isGetRequest = false;
    String? queryParams;

    // Route to specific endpoints
    String questionLower = question.toLowerCase();
    
    if (questionLower.contains("balance")) {
      endpoint = "$API_URL/get_wallet_balance";
      isGetRequest = true;
    } else if (questionLower.contains("recent") || 
               questionLower.contains("last transaction") || 
               questionLower.contains("history")) {
      endpoint = "$API_URL/get_recent_transactions";
      queryParams = "?limit=3";
      isGetRequest = true;
    }

    try {
      http.Response response;
      
      if (isGetRequest) {
        final fullUrl = queryParams != null ? "$endpoint$queryParams" : endpoint;
        response = await http.get(Uri.parse(fullUrl));
      } else {
        response = await http.post(
          Uri.parse(endpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'question': question}),
        );
      }

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        String answer = "";
        
        if (endpoint.contains("balance")) {
          double balance = data['balance']?.toDouble() ?? 0.0;
          answer = "Your balance is ${balance.toStringAsFixed(2)} rupees.";
        } else if (endpoint.contains("recent")) {
          List<dynamic> transactions = data['transactions'] ?? [];
          if (transactions.isNotEmpty) {
            answer = "Your recent transactions are: ";
            List<String> details = [];
            for (var t in transactions) {
              String type = t['type'] ?? 'unknown';
              double amount = t['amount']?.toDouble() ?? 0.0;
              String date = t['date']?.substring(0, 10) ?? 'unknown date';
              details.add("$type of ${amount.toStringAsFixed(2)} rupees on $date");
            }
            answer += details.join(". ") + ".";
          } else {
            answer = "You have no recent transactions.";
          }
        } else {
          answer = data['answer'] ?? "Sorry, I couldn't process that.";
        }
        
        _speak(answer);
      } else {
        throw Exception('Server returned ${response.statusCode}: ${response.body}');
      }

    } catch (e) {
      print("Error asking wallet question: $e");
      _speak("Sorry, I encountered an error. Please check your connection.");
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAnswer = false;
          _lastWords = "";
        });
      }
    }
  }

  @override
  void dispose() {
    _speechToText.stop();
    flutterTts.stop();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Wallet Q & A")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _speechToText.isListening ? Icons.mic : Icons.mic_none,
                        size: 64,
                        color: _speechEnabled ? Colors.blue : Colors.grey,
                      ),
                      SizedBox(height: 20),
                      Text(
                        _isLoadingAnswer
                            ? "Thinking..."
                            : _currentAnswer.isNotEmpty
                                ? _currentAnswer
                                : (_speechToText.isListening
                                    ? "Listening..."
                                    : "Tap mic to ask"),
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      if (_lastWords.isNotEmpty && _speechToText.isListening)
                        Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: Text(
                            "You're saying: $_lastWords",
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: TextField(
                controller: _textController,
                decoration: InputDecoration(
                  hintText: 'Or type your question here',
                  border: OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.send),
                    onPressed: () {
                      if (_textController.text.isNotEmpty) {
                        _askWalletQuestion(_textController.text);
                        _textController.clear();
                      }
                    },
                  ),
                ),
                onSubmitted: (value) {
                  if (value.isNotEmpty) {
                    _askWalletQuestion(value);
                    _textController.clear();
                  }
                },
              ),
            ),

            TextButton.icon(
              icon: Icon(Icons.help_outline),
              label: Text("Sample Questions"),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text("Sample Questions"),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _helpQuestions.map((q) => ListTile(
                          title: Text(q),
                          onTap: () {
                            Navigator.of(context).pop();
                            _askWalletQuestion(q);
                          },
                        )).toList(),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text("Close"),
                      )
                    ],
                  ),
                );
              },
            ),

            Padding(
              padding: const EdgeInsets.only(bottom: 20.0, top: 10.0),
              child: FloatingActionButton.extended(
                onPressed: !_speechEnabled
                    ? null
                    : (_speechToText.isListening ? null : _startListening),
                icon: Icon(_speechToText.isListening ? Icons.mic_off : Icons.mic),
                label: Text(_speechToText.isListening ? "Listening..." : "Ask"),
                backgroundColor: _speechEnabled
                    ? (_speechToText.isListening ? Colors.red : Colors.blue)
                    : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}