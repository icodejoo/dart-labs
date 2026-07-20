import 'package:flutter/material.dart';
import '../helpers.dart';
import '../manager.dart';

class ConditionsPage extends StatefulWidget {
  const ConditionsPage({super.key});

  @override
  State<ConditionsPage> createState() => _ConditionsPageState();
}

class _ConditionsPageState extends State<ConditionsPage> {
  bool _whenEnabled = false;
  bool _authEnabled = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          pageHeader(context, 'Conditions',
              'Overlays can be conditional: route checks the current route, '
              'when is a custom bool predicate, requiresAuth checks the auth context. '
              'dismissWhenUnmet auto-closes a shown overlay when its condition stops holding. '
              'setContext updates context and triggers re-evaluation.'),
          pageSection(
            context,
            'route — only show on a specific route',
            [
              demoButton('btn-cond-promo', 'open with route: "/promo"', () {
                openEntry('cond-promo',
                    text: 'ROUTE /promo',
                    route: '/promo',
                    dismissWhenUnmet: true,
                    hint: 'Only visible on /promo.\n'
                        'Leaving /promo auto-dismisses this card.');
              }),
              demoButton('btn-goto-promo', '→ navigate to /promo', () {
                Navigator.of(context).push(MaterialPageRoute<void>(
                  settings: const RouteSettings(name: '/promo'),
                  builder: (_) => const _PromoPage(),
                ));
              }),
            ],
            subtitle:
                '1. Tap "open with route: /promo" (card queues, invisible here)\n'
                '2. Navigate to /promo → card activates\n'
                '3. Navigate back → dismissWhenUnmet closes the card',
          ),
          pageSection(
            context,
            'route with RegExp — pattern matching',
            [
              demoButton('btn-cond-regex', 'route: RegExp(r"^/promo")', () {
                openEntry('cond-regex',
                    text: 'REGEX route',
                    route: RegExp(r'^/promo'),
                    hint: 'Matches any route starting with /promo');
              }),
            ],
          ),
          pageSection(
            context,
            'route with List — multiple eligible routes',
            [
              demoButton('btn-cond-list', 'route: ["/promo", "/zone"]', () {
                openEntry('cond-list',
                    text: 'LIST route',
                    route: const ['/promo', '/zone'],
                    hint: 'Eligible on /promo OR /zone');
              }),
            ],
          ),
          pageSection(
            context,
            'when — custom bool predicate',
            [
              Row(
                children: [
                  const Text('when() returns: ', style: TextStyle(fontSize: 13)),
                  Switch(
                    value: _whenEnabled,
                    onChanged: (v) => setState(() => _whenEnabled = v),
                  ),
                  Text(_whenEnabled ? 'true (eligible)' : 'false (waiting)',
                      style: TextStyle(
                          color: _whenEnabled ? Colors.green : Colors.orange)),
                ],
              ),
              const SizedBox(height: 8),
              demoButton('btn-cond-when', 'open with when: (ctx) => toggle', () {
                openCard('cond-when',
                    text: 'WHEN',
                    when: (_) => _whenEnabled,
                    hint: 'Only activates when the toggle above is ON');
              }),
              demoButton('btn-cond-nudge', 'setContext (trigger re-eval)', () {
                om.setContext({});
              }),
            ],
            subtitle:
                'when: (ctx) => bool overrides route/requiresAuth. ctx is the current setContext map. '
                'Toggle OFF then open → entry waits. Toggle ON then tap setContext → activates.',
          ),
          pageSection(
            context,
            'requiresAuth — gated by context["auth"]',
            [
              Row(
                children: [
                  const Text('auth context: ', style: TextStyle(fontSize: 13)),
                  Switch(
                    value: _authEnabled,
                    onChanged: (v) {
                      setState(() => _authEnabled = v);
                      om.setContext({'auth': v});
                    },
                  ),
                  Text(_authEnabled ? 'authenticated' : 'not authenticated',
                      style: TextStyle(
                          color: _authEnabled ? Colors.green : Colors.orange)),
                ],
              ),
              const SizedBox(height: 8),
              demoButton('btn-cond-auth', 'open with requiresAuth: true', () {
                openCard('cond-auth',
                    text: 'AUTH REQUIRED',
                    requiresAuth: true,
                    hint: 'Only activates when context["auth"] == true');
              }),
            ],
            subtitle:
                'requiresAuth: true checks context["auth"] == true. '
                'Toggle the switch → setContext({"auth": true/false}) automatically.',
          ),
          pageSection(
            context,
            'dismissWhenUnmet: false — stay shown even if condition breaks',
            [
              demoButton('btn-cond-stay', 'open route:/promo + dismissWhenUnmet:false', () {
                openEntry('cond-stay',
                    text: 'STAYS',
                    route: '/promo',
                    dismissWhenUnmet: false,
                    hint: 'route:/promo but dismissWhenUnmet:false\n'
                        'Navigating away does NOT auto-close this');
              }),
            ],
            subtitle:
                'Normally leaving /promo dismisses the card. '
                'With dismissWhenUnmet: false it stays until manually closed.',
          ),
          pageSection(
            context,
            'setContext — manual context update',
            [
              demoButton('btn-ctx-set-home', 'setContext route: "/home"', () {
                om.setContext({'route': '/home'});
              }),
              demoButton('btn-ctx-set-promo', 'setContext route: "/promo"', () {
                om.setContext({'route': '/promo'});
              }),
              demoButton('btn-ctx-empty', 'setContext {} (nudge/re-eval)', () {
                om.setContext({});
              }),
            ],
            subtitle:
                'setContext merges into existing context and re-evaluates all conditions. '
                'LayermanNavigatorObserver calls this automatically on navigation.',
          ),
        ],
      ),
    );
  }
}

class _PromoPage extends StatelessWidget {
  const _PromoPage();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('/promo')),
        body: const Center(
          child: Text(
            '/promo page\n\nCondition overlays with route: "/promo"\nare eligible here.\n\nPop back to trigger dismissWhenUnmet.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}
