import 'package:xlru/xlru.dart';

// A pure Dart stand-in for a scene feed owned by a Flutter application.
class SceneFeed {
  SceneFeed(this.scene);
  final String scene;

  void dispose() => print('Disposed $scene');
}

void main() {
  final feeds = LruCache<String, SceneFeed>(
    maxSize: 2,
    onRemove: (key, feed, cause) {
      print('$key: ${cause.name}');
      feed.dispose();
    },
  );

  SceneFeed open(String scene) =>
      feeds.putIfAbsent(scene, () => SceneFeed(scene));

  open('forest');
  feeds.pin('forest'); // The drawer is using this feed.
  open('desert');
  open('ocean'); // Disposes desert; forest is protected.
  print(feeds.keys.toList()); // [ocean, forest]
  print(feeds.peek('forest')?.scene); // Does not promote forest.

  feeds.unpin('forest'); // The drawer has closed.
  open('mountain'); // Disposes forest, the least recently used feed.
  feeds.clear(); // Disposes ocean, then mountain.
}
