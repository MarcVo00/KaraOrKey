import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:app/config.dart';

class YoutubeSearchDialog extends StatefulWidget {
  final Function(String, String) onDownload;
  const YoutubeSearchDialog({super.key, required this.onDownload});
  @override
  State<YoutubeSearchDialog> createState() => _YoutubeSearchDialogState();
}

class _YoutubeSearchDialogState extends State<YoutubeSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> results = [];
  bool isSearching = false;

  Future<void> _searchYoutube() async {
    if (_searchController.text.isEmpty) return;
    setState(() => isSearching = true);
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/search?q=${Uri.encodeComponent(_searchController.text)}'));
      if (response.statusCode == 200 && mounted) {
        setState(() => results = json.decode(response.body));
      }
    } catch (_) {}
    if (mounted) setState(() => isSearching = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Chercher sur YouTube"),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Artiste - Titre",
                suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _searchYoutube),
              ),
              onSubmitted: (_) => _searchYoutube(),
            ),
            const SizedBox(height: 20),
            if (isSearching) const CircularProgressIndicator(),
            if (!isSearching && results.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final video = results[index];
                    return ListTile(
                      leading: const Icon(Icons.ondemand_video, color: Colors.red),
                      title: Text(video['title'], maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        icon: const Icon(Icons.download, color: Colors.green),
                        onPressed: () {
                          widget.onDownload(video['url'], video['title']);
                          Navigator.pop(context);
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Fermer"))],
    );
  }
}
