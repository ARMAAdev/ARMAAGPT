import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

class FileAnalysisPage extends StatefulWidget {
  final String selectedLLM;

  const FileAnalysisPage({super.key, required this.selectedLLM});

  @override
  _FileAnalysisPageState createState() => _FileAnalysisPageState();
}

class _FileAnalysisPageState extends State<FileAnalysisPage> {
  final ScrollController _chatScrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final List<Map<String, dynamic>> _chatMessages = [];
  final List<Map<String, dynamic>> _uploadedFiles = [];
  String? _selectedFileSessionId;
  bool _isLoading = false;
  int _selectedIndex = -1;
  int _hoveredIndex = -1;

  @override
  void dispose() {
    _chatScrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    if (_uploadedFiles.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("You can only upload up to 5 files.")),
      );
      return;
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'csv', 'txt', 'docx'],
    );

    if (result != null) {
      PlatformFile file = result.files.first;

      if (!_isAllowedFileType(file.extension)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid file type. Only PDF, CSV, TXT, and DOCX files are allowed.')),
        );
        return;
      }

      if (_uploadedFiles.any((uploadedFile) => uploadedFile['file'].name == file.name)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("You have already uploaded this file.")),
        );
        return;
      }

      setState(() {
        _uploadedFiles.add({'file': file, 'sessionId': null});
        _selectedIndex = _uploadedFiles.length - 1;
      });
    } else {
      print('User canceled the picker');
    }
  }

  bool _isAllowedFileType(String? extension) {
    const allowedExtensions = ['pdf', 'csv', 'txt', 'docx'];
    return allowedExtensions.contains(extension?.toLowerCase());
  }

  void _selectFile(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _removeFile(int index) {
    setState(() {
      _uploadedFiles.removeAt(index);
      if (_selectedIndex == index) {
        _selectedIndex = -1;
      } else if (_selectedIndex > index) {
        _selectedIndex--;
      }
    });
  }

  Future<void> _sendToFileAnalysisAPI() async {
    if (_textController.text.isEmpty) return;

    if (_selectedIndex == -1) {
      setState(() {
        _chatMessages.add({
          'isUserMessage': true,
          'message': _textController.text,
        });
        _chatMessages.add({
          'isUserMessage': false,
          'message': "I could not see any files, please select or upload a file first along with your message. If you just want to chat, you can use the chat mode instead.",
        });
        _textController.clear();
      });
      return;
    }

    PlatformFile file = _uploadedFiles[_selectedIndex]['file'];
    String? sessionId = _uploadedFiles[_selectedIndex]['sessionId'];
    String llmModel = widget.selectedLLM;
    String message = _textController.text;

    setState(() {
      _isLoading = true;
      _chatMessages.add({'isUserMessage': true, 'message': message});
      _textController.clear();
    });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('https://armaagpt-a42506af0b04.herokuapp.com/file-analysis'));
      request.fields['model'] = llmModel;
      request.fields['prompt'] = message;
      if (sessionId != null) {
        request.fields['session_id'] = sessionId;
      }
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        file.bytes!,
        filename: file.name,
      ));

      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var jsonResponse = jsonDecode(responseData);

      setState(() {
        _uploadedFiles[_selectedIndex]['sessionId'] ??= jsonResponse['session_id'];
        _chatMessages.add({'isUserMessage': false, 'message': jsonResponse['response']});
      });
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
      child: Row(
        children: [
          _buildSidePanel(context),
          SizedBox(width: 20),
          Expanded(
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
                        padding: const EdgeInsets.only(
                            left: 40.0, top: 14.0, bottom: 14.0, right: 200.0),
                        alignment: isUserMessage
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isUserMessage
                                ? Colors.lightBlue[700]
                                : Colors.grey[800],
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
          ),
        ],
      ),
    );
  }

  Widget _buildInputField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
          left: 30.0, top: 15.0, bottom: 15.0, right: 250.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[850],
          borderRadius: BorderRadius.circular(30),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.upload_file, color: Colors.white),
              onPressed: _pickFile,
            ),
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
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: 'Upload or select a file and ask anything about it',
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
                    onPressed: _sendToFileAnalysisAPI,
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidePanel(BuildContext context) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.black54, Colors.black87],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 30.0),
          ),
          SizedBox(height: 20),
          Expanded(
            child: ListView.builder(
              itemCount: _uploadedFiles.length,
              itemBuilder: (context, index) {
                bool isSelected = _selectedIndex == index;
                return MouseRegion(
                  onEnter: (_) => setState(() => _hoveredIndex = index),
                  onExit: (_) => setState(() => _hoveredIndex = -1),
                  child: GestureDetector(
                    onTap: () => _selectFile(index),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.tealAccent[700] : Colors.transparent,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          if (_hoveredIndex == index && !isSelected)
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.5),
                              spreadRadius: 0,
                              blurRadius: 0,
                              offset: Offset(0, 0),
                            ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                          vertical: 15.0, horizontal: 20.0),
                      margin: EdgeInsets.symmetric(
                          vertical: 10.0, horizontal: 10.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _uploadedFiles[index]['file'].name,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, color: Colors.white),
                            onPressed: () => _removeFile(index),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
