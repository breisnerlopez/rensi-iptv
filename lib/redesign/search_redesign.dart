import 'package:flutter/material.dart';
import 'package:rensi_iptv/models/category_view_model.dart';
import 'package:rensi_iptv/models/playlist_content_model.dart';
import 'package:rensi_iptv/redesign/rensi_widgets.dart';

/// Full-screen catalogue search (redesign). Searches titles across the
/// movie + series categories locally — no TMDb key required.
class SearchRedesign extends StatefulWidget {
  const SearchRedesign({
    super.key,
    required this.movieCategories,
    required this.seriesCategories,
    required this.onOpen,
  });

  final List<CategoryViewModel> movieCategories;
  final List<CategoryViewModel> seriesCategories;
  final void Function(ContentItem) onOpen;

  @override
  State<SearchRedesign> createState() => _SearchRedesignState();
}

class _SearchRedesignState extends State<SearchRedesign> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _query = '';
  late final List<ContentItem> _all;

  @override
  void initState() {
    super.initState();
    final seen = <String>{};
    _all = [
      for (final c in [...widget.movieCategories, ...widget.seriesCategories])
        for (final it in c.contentItems)
          if (seen.add(it.id)) it,
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = rensi(context);
    final cross = MediaQuery.of(context).size.width >= 900 ? 6 : 3;
    final q = _query.trim().toLowerCase();
    final results = q.isEmpty
        ? const <ContentItem>[]
        : _all.where((it) => it.name.toLowerCase().contains(q)).take(60).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: r.surface2,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 20, color: r.text3),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focus,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              onChanged: (v) => setState(() => _query = v),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isCollapsed: true,
                                hintText: 'Buscar películas, series…',
                              ),
                            ),
                          ),
                          if (_query.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _controller.clear();
                                setState(() => _query = '');
                              },
                              child: Icon(Icons.close, size: 18, color: r.text3),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: q.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search, size: 56, color: r.surface3),
                          const SizedBox(height: 12),
                          Text('Busca en tu catálogo',
                              style: TextStyle(color: r.text3, fontSize: 14)),
                        ],
                      ),
                    )
                  : results.isEmpty
                      ? Center(
                          child: Text('Sin resultados para "${_query.trim()}"',
                              style: TextStyle(color: r.text3)))
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cross,
                            childAspectRatio: 1 / 1.48,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: results.length,
                          itemBuilder: (_, i) => RensiPoster(
                            item: results[i],
                            width: double.infinity,
                            onTap: () => widget.onOpen(results[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
