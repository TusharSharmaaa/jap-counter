import 'package:flutter/material.dart';
import 'ads/test_banner.dart';


class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  int _index = 0;

  final _pages = const [
    _CounterPage(),
    _StatsPage(),
    _ContentPage(),
    _TimerPage(),
    _SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Radha Jap Counter',
      home: Scaffold(
        body: _pages[_index],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.touch_app), label: 'Counter'),
            NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Stats'),
            NavigationDestination(icon: Icon(Icons.menu_book), label: 'Content'),
            NavigationDestination(icon: Icon(Icons.timer), label: 'Timer'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _BannerReserve extends StatelessWidget {
  const _BannerReserve();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52, // reserved space for a standard banner
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(width: 0.5, color: Theme.of(context).dividerColor)),
        ),
        child: const Center(child: Text('Ad Banner (reserved)')),
      ),
    );
  }
}

class _CounterPage extends StatefulWidget {
  const _CounterPage();

  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int _japs = 0; // today's japs (temporary, memory-only for now)

  void _inc() => setState(() => _japs++);

  int get _malas => _japs ~/ 108;         // 108 = 1 mala
  int get _lifetimeMalas => _malas;       // placeholder until we add persistence

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Counter')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(child: _StatTile(title: "Today's Japs", value: _japs.toString())),
                const SizedBox(width: 8),
                Expanded(child: _StatTile(title: "Malas", value: _malas.toString())),
                const SizedBox(width: 8),
                Expanded(child: _StatTile(title: "Lifetime Malas", value: _lifetimeMalas.toString())),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: _inc,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.25)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Tap to Count', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      Text('$_japs', style: Theme.of(context).textTheme.displaySmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const TestBanner(), // keep the test banner on Counter only
    );
  }
}

class _StatTile extends StatelessWidget {
  final String title;
  final String value;
  const _StatTile({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const Spacer(),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}


class _StatsPage extends StatelessWidget {
  const _StatsPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
      body: const Center(child: Text('Stats UI stub')),
      bottomNavigationBar: const _BannerReserve(),
    );
  }
}

class _ContentPage extends StatelessWidget {
  const _ContentPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Content')),
      body: const Center(child: Text('Content UI stub')),
      bottomNavigationBar: const _BannerReserve(),
    );
  }
}

class _TimerPage extends StatelessWidget {
  const _TimerPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timer')),
      body: const Center(child: Text('Timer UI stub')),
      bottomNavigationBar: const _BannerReserve(),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(child: Text('Settings UI stub')),
      bottomNavigationBar: const _BannerReserve(),
    );
  }
}
