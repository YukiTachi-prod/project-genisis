import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../providers/chat_provider.dart';

class EmbeddedBrowserWidget extends StatefulWidget {
  final ChatProvider chat;
  const EmbeddedBrowserWidget({super.key, required this.chat});

  @override
  State<EmbeddedBrowserWidget> createState() => _EmbeddedBrowserWidgetState();
}

class _EmbeddedBrowserWidgetState extends State<EmbeddedBrowserWidget> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _inputController.text = widget.chat.browserUrl;
  }

  @override
  void didUpdateWidget(covariant EmbeddedBrowserWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.chat.browserUrl != oldWidget.chat.browserUrl) {
      _inputController.text = widget.chat.browserUrl;
      // Scroll back to top on new page load
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submitInput(String value) {
    widget.chat.navigateBrowser(value);
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;

    return Container(
      color: const Color(0xFF040416),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Browser Header Bar ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: const Color(0xFF0C0C34),
            child: Row(
              children: [
                // Navigation buttons
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 16),
                  color: const Color(0xFFAEB2D1),
                  tooltip: 'Go Back',
                  onPressed: chat.browserGoBack,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  color: const Color(0xFFAEB2D1),
                  tooltip: 'Go Forward',
                  onPressed: chat.browserGoForward,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                IconButton(
                  icon: const Icon(Icons.home, size: 16),
                  color: const Color(0xFFAEB2D1),
                  tooltip: 'Go Home',
                  onPressed: chat.browserGoHome,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                const SizedBox(width: 6),

                // Address bar
                Expanded(
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF040416),
                      border: Border.all(color: const Color(0xFF2E2E5D), width: 1.0),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search, size: 14, color: Color(0xFF6E6E8A)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _inputController,
                            onSubmitted: _submitInput,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Colors.white,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Enter URL or search query...',
                              hintStyle: TextStyle(color: Color(0xFF4C566A)),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        if (chat.browserLoading)
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF5B6EF5)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Close button
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  color: const Color(0xFF6E6E8A),
                  tooltip: 'Close Browser',
                  onPressed: chat.toggleBrowser,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
              ],
            ),
          ),

          // ── Browser Body Content ────────────────────────────────────────
          Expanded(
            child: chat.browserLoading && chat.browserPageMarkdown.isEmpty && chat.browserSearchResults.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          strokeWidth: 2.0,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF5B6EF5)),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'RETRIEVING WEB CONTENT...',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFAEB2D1),
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  )
                : chat.browserError != null
                    ? _buildErrorScreen(chat.browserError!)
                    : _buildPageContent(chat),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorScreen(String error) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF140810),
          border: Border.all(color: const Color(0xFFFF5F57).withValues(alpha: 0.5), width: 1.0),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline, color: Color(0xFFFF5F57), size: 18),
                SizedBox(width: 8),
                Text(
                  'BROWSER ERROR',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF5F57),
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              error,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Color(0xFFD6DBFF),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0B0B2E),
                foregroundColor: const Color(0xFF5B6EF5),
                side: const BorderSide(color: Color(0xFF5B6EF5), width: 1.0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              onPressed: widget.chat.browserGoHome,
              child: const Text(
                'GO HOME',
                style: TextStyle(fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageContent(ChatProvider chat) {
    switch (chat.browserPageMode) {
      case BrowserPageMode.home:
        return _buildHomeScreen();
      case BrowserPageMode.search:
        return _buildSearchResultsScreen(chat);
      case BrowserPageMode.page:
        return _buildReaderScreen(chat);
    }
  }

  Widget _buildHomeScreen() {
    final searchController = TextEditingController();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          // ASCII Logo
          const Text(
            ' _ _  ___  ___  _ _  ___  ___\n'
            '| | |/ __>| _ \\| | |/ __>| __>\n'
            '| \' |\\__ \\|  _/| \' |\\__ \\| _>\n'
            '|__/ <___/|_|  |__/ <___/|___>',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5B6EF5),
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'CYBER-TERM READER BROWSER',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: Color(0xFFAEB2D1),
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 48),

          // Central Search input box
          Container(
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: const Color(0xFF0C0C34),
              border: Border.all(color: const Color(0xFF5B6EF5), width: 1.0),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF5B6EF5).withValues(alpha: 0.15),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: TextField(
              controller: searchController,
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) {
                  _submitInput(val);
                }
              },
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: Colors.white,
              ),
              decoration: InputDecoration(
                hintText: 'Search DuckDuckGo or enter URL...',
                hintStyle: const TextStyle(color: Color(0xFF6E6E8A), fontSize: 11),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(12),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search, color: Color(0xFF5B6EF5)),
                  onPressed: () {
                    if (searchController.text.trim().isNotEmpty) {
                      _submitInput(searchController.text);
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 48),

          // Quick Links
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'QUICK DIRECTORY:',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6E6E8A),
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 3.5,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              _quickLinkCard('Wikipedia', 'wikipedia.org', Icons.menu_book),
              _quickLinkCard('GitHub', 'github.com', Icons.code),
              _quickLinkCard('Hacker News', 'news.ycombinator.com', Icons.trending_up),
              _quickLinkCard('Flutter Dev', 'flutter.dev', Icons.flutter_dash),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickLinkCard(String title, String domain, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF080824),
        border: Border.all(color: const Color(0xFF1E1E3F), width: 1.0),
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        onTap: () => _submitInput(domain),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF5B6EF5), size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      domain,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        color: Color(0xFF6E6E8A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResultsScreen(ChatProvider chat) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: chat.browserSearchResults.length,
      itemBuilder: (context, index) {
        final result = chat.browserSearchResults[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          color: const Color(0xFF080824),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFF1E1E3F), width: 1.0),
            borderRadius: BorderRadius.circular(4),
          ),
          child: InkWell(
            onTap: () => chat.navigateBrowser(result.url),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFC8D0FF),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    result.url,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: Color(0xFF28C840),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    result.snippet,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFFAEB2D1),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReaderScreen(ChatProvider chat) {
    if (chat.browserPageMarkdown.isEmpty) {
      return const Center(
        child: Text(
          'Processing content...',
          style: TextStyle(fontFamily: 'monospace', color: Color(0xFFAEB2D1)),
        ),
      );
    }

    return SelectionArea(
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: MarkdownBody(
          data: chat.browserPageMarkdown,
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Color(0xFFF5F5FA),
              height: 1.4,
            ),
            h1: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.4,
            ),
            h2: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.4,
            ),
            h3: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.4,
            ),
            code: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              backgroundColor: Color(0xFF0C0C34),
              color: Color(0xFFC8D0FF),
            ),
            codeblockPadding: const EdgeInsets.all(8),
            codeblockDecoration: BoxDecoration(
              color: const Color(0xFF06061A),
              border: Border.all(color: const Color(0xFF1E1E3F), width: 1.0),
              borderRadius: BorderRadius.circular(4),
            ),
            blockquote: const TextStyle(
              fontFamily: 'monospace',
              color: Color(0xFFAEB2D1),
              fontStyle: FontStyle.italic,
            ),
            blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
            blockquoteDecoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: Color(0xFF5B6EF5), width: 3.0),
              ),
            ),
            listBullet: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Color(0xFF5B6EF5),
            ),
            a: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Color(0xFF5B6EF5),
              decoration: TextDecoration.underline,
            ),
          ),
          onTapLink: (text, href, title) {
            if (href != null) {
              chat.navigateBrowser(href);
            }
          },
        ),
      ),
    );
  }
}
