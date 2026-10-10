import 'dart:async';
import 'dart:convert';

import 'package:extension_bridge/extension_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The App Group shared with the app extensions.
///
/// On iOS it has to be added to the App Groups capability of the app and of
/// every extension. Other platforms use it as a namespace.
const appGroup = 'group.com.nikodembernat.extensionBridgeExample';

/// The bridge used by the app, its home screen widget and its background
/// callback.
const bridge = ExtensionBridge(appGroup: appGroup);

/// The native feature registered by the example in `MainActivity.kt`,
/// `AppDelegate.swift` (iOS) and `AppDelegate.swift` (macOS).
final example = bridge.feature('example');

/// The key of the counter shown by the app and its home screen widget.
const counterKey = 'counter';

/// Handles events native code dispatches while the app may be closed, for
/// example when the "+" button of the Android home screen widget is tapped.
@pragma('vm:entry-point')
Future<Object?> onBackgroundEvent(BackgroundEvent event) async {
  switch (event.name) {
    case 'increment':
      final counter = (await bridge.storage.get<int>(counterKey) ?? 0) + 1;
      await bridge.storage.set(counterKey, counter);
      await example.invoke<void>('reloadWidgets');
      return counter;
    case 'echo':
      return event.arguments;
    default:
      throw UnsupportedError('Unknown background event ${event.name}');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (await ExtensionBridge.isBackgroundExecutionSupported) {
    await ExtensionBridge.registerBackgroundCallback(onBackgroundEvent);
  }
  runApp(const ExampleApp());
}

/// The example app.
class const ExampleApp({super.key}) extends StatelessWidget {
  /// Creates the example app.
  this;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'extension_bridge',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: const CounterPage(),
    );
  }
}

/// Shows a counter shared with the home screen widget and the extension
/// links that opened the app.
class const CounterPage({super.key}) extends StatefulWidget {
  /// Creates the counter page.
  this;

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState()
    extends State<CounterPage>
    with WidgetsBindingObserver {
  int _counter = 0;
  final _links = <ExtensionLink>[];
  StreamSubscription<ExtensionLink>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    if (!kIsWeb) {
      _linkSubscription = ExtensionBridge.links.listen(_onLink);
      unawaited(
        ExtensionBridge.initialLink.then((link) {
          if (link != null) {
            _onLink(link);
          }
        }),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_linkSubscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The widget may have changed the counter while the app was paused.
    if (state == AppLifecycleState.resumed) {
      unawaited(_load());
    }
  }

  void _onLink(ExtensionLink link) {
    setState(() => _links.insert(0, link));
  }

  Future<void> _load() async {
    final counter = await bridge.storage.get<int>(counterKey) ?? 0;
    if (mounted) {
      setState(() => _counter = counter);
    }
  }

  Future<void> _save(int counter) async {
    await bridge.storage.set(counterKey, counter);
    await bridge.storage.setJson('lastUpdate', {
      'counter': counter,
      'at': DateTime.now().toIso8601String(),
    });
    await _guard(() => example.invoke<void>('reloadWidgets'));
    setState(() => _counter = counter);
  }

  Future<void> _incrementInBackground() => _guard(() async {
    final counter = await example.invoke<int>('dispatchBackground', {
      'name': 'increment',
    });
    _showMessage('The background isolate incremented the counter to $counter');
    await _load();
  });

  Future<void> _saveFile() => _guard(() async {
    final path = await bridge.files.write(
      'counter.txt',
      utf8.encode('Counter: $_counter'),
    );
    _showMessage('Saved $path');
  });

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on ExtensionBridgeException catch (error) {
      _showMessage('${error.code}: ${error.message}');
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('extension_bridge')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Shared counter', style: textTheme.titleMedium),
          Text('$_counter', style: textTheme.displayLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => _save(_counter + 1),
                child: const Text('Increment'),
              ),
              OutlinedButton(
                onPressed: () => _save(0),
                child: const Text('Reset'),
              ),
              OutlinedButton(
                onPressed: _incrementInBackground,
                child: const Text('Increment in background'),
              ),
              OutlinedButton(
                onPressed: _saveFile,
                child: const Text('Save file'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Extension links', style: textTheme.titleMedium),
          if (_links.isEmpty)
            const Text(
              'Tap the home screen widget to open the app with a link.',
            ),
          for (final link in _links)
            ListTile(
              title: Text(link.uri.toString()),
              subtitle: Text('source: ${link.source}'),
            ),
        ],
      ),
    );
  }
}
