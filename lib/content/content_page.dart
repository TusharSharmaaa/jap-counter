import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

class ContentPage extends StatefulWidget {
  const ContentPage({super.key});

  @override
  State<ContentPage> createState() => _ContentPageState();
}

class _ContentPageState extends State<ContentPage> with TickerProviderStateMixin {
  late final TabController _tabs;
  int _quoteIndex = 0;

  // Placeholder quotes (Premanand Maharaj Ji vibe)
  static const _quotes = [
    "ख़ामोशी में ही सबसे गहरी प्रार्थना होती है।",
    "जप की डोरी पकड़ लो, मन अपने आप शांत हो जाएगा।",
    "जो मिला है, वही प्रभु का प्रसाद है — कृतज्ञ रहो।",
    "हर साँस में राधा-नाम, हर क्षण में माधुर्य।",
    "चलते-फिरते, उठते-बैठते — जप रुकना नहीं चाहिए।",
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _prevQuote() {
    setState(() => _quoteIndex = (_quoteIndex - 1) < 0 ? _quotes.length - 1 : _quoteIndex - 1);
  }

  void _nextQuote() {
    setState(() => _quoteIndex = (_quoteIndex + 1) % _quotes.length);
  }

  Future<void> _shareQuote() async {
    final text = "🌸 ${_quotes[_quoteIndex]}\n— Radha Jap Counter";
    await Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Content"),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: "Quotes"),
            Tab(text: "Gita"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          // QUOTES TAB
          Column(
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Text(
                    _quotes[_quoteIndex],
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _prevQuote,
                        icon: const Icon(Icons.chevron_left),
                        label: const Text("Previous"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _nextQuote,
                        icon: const Icon(Icons.chevron_right),
                        label: const Text("Next"),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: _shareQuote,
                    icon: const Icon(Icons.share),
                    label: const Text("Share on WhatsApp"),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Native Ad reserved slot (we'll wire the real native ad later)
              _NativeAdReserve(),
            ],
          ),

          // GITA TAB (placeholder content)
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text("Chapter 1, Verse 1", style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text(
                "धृतराष्ट्र उवाच ।\nधर्मक्षेत्रे कुरुक्षेत्रे समवेता युयुत्सवः ।\nमामकाः पाण्डवाश्चैव किमकुर्वत सञ्जय ॥१॥",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                "अनुवाद (Hindi): धृतराष्ट्र बोले — हे संजय! धर्मभूमि कुरुक्षेत्र में युद्ध की इच्छा से एकत्रित हुए मेरे पुत्रों और पाण्डु के पुत्रों ने क्या किया?",
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.chevron_left),
                      label: const Text("Previous"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.chevron_right),
                      label: const Text("Next"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  onPressed: () async {
                    await Share.share("Chapter 1, Verse 1 — Radha Jap Counter");
                  },
                  icon: const Icon(Icons.share),
                  label: const Text("Share"),
                ),
              ),
              const SizedBox(height: 16),
              _NativeAdReserve(),
            ],
          ),
        ],
      ),
    );
  }
}

class _NativeAdReserve extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: const Center(child: Text("Native Ad (reserved)")),
    );
  }
}
