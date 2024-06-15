import 'package:flutter/material.dart';
import 'chat.dart';
import 'fileanalysis.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  bool isChatMode = true;
  String selectedLLM = "Microsoft Phi-3";
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _logEvent();
  }

  Future<void> _logEvent() async {
    try {
      await _analytics.logEvent(
        name: 'home_page_opened',
        parameters: <String, Object>{
          'string_param': 'string',
          'int_param': 42,
          'long_param': 12345678910,
          'double_param': 42.0,
          'bool_param': true.toString(),
        },
      );
    } catch (e) {
      print("Failed to log event: $e");
    }
  }

  void _showCustomDropdown(BuildContext context) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);

    OverlayEntry? overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: renderBox.size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, renderBox.size.height),
          child: Material(
            elevation: 4.0,
            color: Colors.transparent,
            child: Container(
              color: Colors.black87,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: ['Microsoft Phi-3', 'Meta Llama-3', 'GPT-3.5', 'Mistral-7B'].map((String item) {
                  return ListTile(
                    title: Text(item, style: TextStyle(color: Colors.white, fontSize: 14.0)),
                    onTap: () {
                      setState(() {
                        selectedLLM = item;
                      });
                      overlayEntry?.remove();
                    },
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context)!.insert(overlayEntry);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Column(
          children: [
            SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.menu_book_rounded, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      isChatMode = false;
                    });
                  },
                ),
                SizedBox(width: 250),
                CompositedTransformTarget(
                  link: _layerLink,
                  child: GestureDetector(
                    onTap: () => _showCustomDropdown(context),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.grey[850],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            selectedLLM,
                            style: TextStyle(color: Colors.white, fontSize: 14.0),
                          ),
                          Icon(Icons.arrow_drop_down, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 250),
                IconButton(
                  icon: Icon(Icons.create_outlined, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      isChatMode = true;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      body: Container(
        color: Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 30.0),
        child: Column(
          children: [
            Expanded(
              child: isChatMode
                  ? ChatPage(
                      selectedLLM: selectedLLM,
                    )
                  : FileAnalysisPage(
                      selectedLLM: selectedLLM,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

void showOverlay({
  required BuildContext context,
  required List<String> items,
  required void Function(String) onItemSelected,
}) {
  final OverlayState overlayState = Overlay.of(context)!;
  final RenderBox renderBox = context.findRenderObject() as RenderBox;
  final Size size = renderBox.size;

  OverlayEntry? overlayEntry;

  overlayEntry = OverlayEntry(
    builder: (context) => Positioned(
      width: size.width,
      child: CompositedTransformFollower(
        link: layerLink,
        showWhenUnlinked: false,
        offset: Offset(0, size.height),
        child: Material(
          elevation: 4.0,
          color: Colors.transparent,
          child: Container(
            color: Colors.black87,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: items.map((String item) {
                return ListTile(
                  title: Text(item, style: TextStyle(color: Colors.white, fontSize: 14.0)),
                  onTap: () {
                    onItemSelected(item);
                    overlayEntry?.remove();
                  },
                );
              }).toList(),
            ),
          ),
        ),
      ),
    ),
  );

  overlayState.insert(overlayEntry);
}
