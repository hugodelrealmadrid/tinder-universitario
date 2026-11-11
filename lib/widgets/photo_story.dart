import 'package:flutter/material.dart';
import 'app_ui.dart';

/// Galería sobre las referencias privadas existentes; nunca obtiene URLs públicas.
class PhotoStory extends StatefulWidget {
  const PhotoStory({
    super.key,
    required this.photos,
    this.allowSwipe = true,
    this.overlay,
    this.photoBuilder,
  });
  final List<String> photos;
  final bool allowSwipe;
  final Widget? overlay;
  final Widget Function(String path)? photoBuilder;
  @override
  State<PhotoStory> createState() => _PhotoStoryState();
}

class _PhotoStoryState extends State<PhotoStory> {
  final _pages = PageController();
  int _index = 0;
  @override
  void didUpdateWidget(covariant PhotoStory old) {
    super.didUpdateWidget(old);
    if (old.photos.join('|') != widget.photos.join('|')) {
      _index = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients) _pages.jumpToPage(0);
      });
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _move(int delta) {
    if (widget.photos.isEmpty) return;
    final next = (_index + delta).clamp(0, widget.photos.length - 1);
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(next);
      return;
    }
    _pages.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (widget.photos.isEmpty)
          const AppPhoto(url: null)
        else
          PageView.builder(
            controller: _pages,
            physics: widget.allowSwipe
                ? const PageScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) =>
                widget.photoBuilder?.call(widget.photos[i]) ??
                AppPhoto(
                  key: ValueKey(widget.photos[i]),
                  url: widget.photos[i],
                ),
          ),
        if (widget.overlay != null) widget.overlay!,
        if (widget.photos.length > 1)
          Positioned(
            top: 14,
            left: 14,
            right: 14,
            child: Row(
              children: [
                for (var i = 0; i < widget.photos.length; i++)
                  Expanded(
                    child: Semantics(
                      label: 'Fotografía ${i + 1} de ${widget.photos.length}',
                      selected: i == _index,
                      child: AnimatedContainer(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i == _index ? Colors.white : Colors.white38,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (widget.photos.length > 1) ...[
          Positioned(
            left: 4,
            top: 80,
            bottom: 100,
            child: Center(
              child: IconButton(
                tooltip: 'Fotografía anterior',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black26,
                  foregroundColor: Colors.white,
                ),
                onPressed: _index > 0 ? () => _move(-1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
            ),
          ),
          Positioned(
            right: 4,
            top: 80,
            bottom: 100,
            child: Center(
              child: IconButton(
                tooltip: 'Fotografía siguiente',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black26,
                  foregroundColor: Colors.white,
                ),
                onPressed: _index < widget.photos.length - 1
                    ? () => _move(1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
