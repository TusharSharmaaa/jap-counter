import 'package:flutter/material.dart';

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

class _CounterPage extends StatelessWidget {
  const _CounterPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Counter')),
      body: const Center(child: Text('Counter UI stub')),
      bottomNavigationBar: const _BannerReserve(),
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
