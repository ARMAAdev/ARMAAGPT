import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ChatPage extends StatefulWidget {
  final String selectedLLM;
  const ChatPage({required this.selectedLLM, super.key});

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ScrollController _chatScrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final List<Map<String, dynamic>> _chatMessages = [];
  bool _isLoading = false;

  @override
  void dispose() {
    _chatScrollController.dispose();
    super.dispose();
  }

  Future<void> _sendToChatAPI() async {
    if (_textController.text.isEmpty) return;

    String llmModel = widget.selectedLLM;
    String message = _textController.text;

    print('Sending to API:');
    print('LLM Model: llmModel');
    print('Message: message');

    setState(() {
      _isLoading = true;
      _chatMessages.add({'isUserMessage': true, 'message': message});
      _textController.clear();
    });

    try {
      final response = await http.post(
        Uri.parse('https://armaagpt-a42506af0b04.herokuapp.com/chat'),
        headers: <String, String>{
          'Content-Type': 'application/json',
        },
        body: jsonEncode(<String, String>{
          'model': llmModel,
          'prompt': message,
        }),
      );

      if (response.statusCode == 200) {
        String apiResponse = jsonDecode(response.body)['response'];
        setState(() {
          _chatMessages.add({'isUserMessage': false, 'message': apiResponse});
        });
      } else {
        setState(() {
          _chatMessages.add({'isUserMessage': false, 'message': 'Failed to get response from API.'});
        });
      }
    } catch (e) {
      print('Error sending to API: $e');
      setState(() {
        _chatMessages.add({'isUserMessage': false, 'message': 'Failed to send message.'});
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _chatScrollController,
              itemCount: _chatMessages.length,
              itemBuilder: (context, index) {
                bool isUserMessage = _chatMessages[index]['isUserMessage'];
                String message = _chatMessages[index]['message'];
                return Container(
                  padding: const EdgeInsets.only(left: 250.0, top: 14.0, bottom: 14.0, right: 250.0),
                  alignment: isUserMessage ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUserMessage ? Colors.lightBlue[700] : Colors.grey[800],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      message,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                );
              },
            ),
          ),
          _buildInputField(context),
        ],
      ),
    );
  }

  Widget _buildInputField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 250.0, top: 15.0, bottom: 15.0, right: 250.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[850],
          borderRadius: BorderRadius.circular(30),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
        child: Row(
          children: [
            SizedBox(width: 15),
            Expanded(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: 150,
                ),
                child: RawScrollbar(
                  thumbVisibility: true,
                  thickness: 8.0,
                  radius: Radius.circular(10),
                  thumbColor: Colors.white54,
                  child: SingleChildScrollView(
                    primary: true,
                    scrollDirection: Axis.vertical,
                    reverse: true,
                    child: TextField(
                      controller: _textController,
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: 'Enter your message',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                      ),
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            _isLoading
                ? IconButton(
                    icon: Icon(Icons.cancel, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _isLoading = false;
                      });
                    },
                  )
                : IconButton(
                    icon: Icon(Icons.send, color: Colors.white),
                    onPressed: _sendToChatAPI,
                  ),
          ],
        ),
      ),
    );
  }
}
