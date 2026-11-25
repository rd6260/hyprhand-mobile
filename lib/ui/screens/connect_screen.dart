import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../blocs/session_bloc.dart';
import '../../data/lan_scan.dart';
import '../../data/models.dart';
import '../palette.dart';
import '../widgets.dart';

class _Brand extends StatelessWidget {
  const _Brand(this.sub);
  final String sub;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      children: [
        Icon(
          Icons.bolt,
          size: 64,
          color: p.primary,
          shadows: [
            Shadow(color: p.primary.withValues(alpha: .6), blurRadius: 24),
          ],
        ),
        Text(
          'HYPRHAND',
          style: TextStyle(
            fontFamily: display,
            fontWeight: FontWeight.w700,
            fontSize: 28,
            letterSpacing: 8,
            color: p.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: TextStyle(color: p.onVar),
        ),
      ],
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ),
  );
}

class PickerScreen extends StatefulWidget {
  const PickerScreen(this.hosts, {super.key});
  final List<RigHost> hosts;
  @override
  State<PickerScreen> createState() => _PickerScreenState();
}

class _PickerScreenState extends State<PickerScreen> {
  final _addr = TextEditingController();
  final _found = <RigHost>[];
  StreamSubscription<RigHost>? _scan;
  bool _scanned = false;
  String? _error;

  @override
  void dispose() {
    _scan?.cancel();
    _addr.dispose();
    super.dispose();
  }

  void _startScan() {
    setState(() {
      _found.clear();
      _scanned = false;
    });
    void finish() {
      if (mounted) {
        setState(() {
          _scan = null;
          _scanned = true;
        });
      }
    }

    _scan = scanLan().listen(
      (h) => setState(() => _found.add(h)),
      onDone: finish,
      onError: (_) => finish(),
    );
    setState(() {});
  }

  void _choose(RigHost h) => context.read<SessionBloc>().add(HostChosen(h));

  void _connect() {
    final h = RigHost.parse(_addr.text);
    if (h == null) {
      setState(
        () =>
            _error = 'Enter an address like 192.168.1.20 or rig.tailnet.ts.net',
      );
      return;
    }
    _choose(h);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget tile(RigHost h, {bool saved = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => _choose(h),
        child: Panel(
          padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
          child: Row(
            children: [
              Icon(
                h.insecure ? Icons.lan : Icons.lock,
                size: 18,
                color: p.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      h.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      h.url,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.onVar),
                    ),
                  ],
                ),
              ),
              if (saved)
                IconButton(
                  tooltip: 'Forget ${h.label}',
                  onPressed: () async {
                    final b = context.read<SessionBloc>();
                    if (await confirm(
                      context,
                      'Forget ${h.label}?',
                      'Forget',
                    )) {
                      b.add(HostForgotten(h));
                    }
                  },
                  icon: Icon(Icons.close, size: 18, color: p.onVar),
                )
              else
                const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
    final fresh = _found.where(
      (f) => widget.hosts.every((h) => h.url != f.url),
    );
    return _Frame(
      children: [
        const _Brand('Pick the rig you want in your hand'),
        const SizedBox(height: 28),
        if (widget.hosts.isNotEmpty) ...[
          const SectionLabel('Your rigs'),
          for (final h in widget.hosts) tile(h, saved: true),
          const SizedBox(height: 12),
        ],
        const SectionLabel('On this network'),
        for (final h in fresh) tile(h),
        if (_scanned && fresh.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Nothing new found. The server only answers here if its bind '
              'address is 0.0.0.0 and the phone is on the same network.',
              style: TextStyle(fontSize: 12, height: 1.4, color: p.onVar),
            ),
          ),
        DeckButton(
          _scan != null ? 'Scanning…' : 'Scan Wi-Fi',
          icon: Icons.radar,
          busy: _scan != null,
          onTap: _startScan,
        ),
        const SizedBox(height: 24),
        const SectionLabel('By address'),
        TextField(
          controller: _addr,
          autocorrect: false,
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _connect(),
          decoration: InputDecoration(
            hintText: '192.168.1.20 or rig.tailnet.ts.net',
            errorText: _error,
            errorMaxLines: 2,
          ),
        ),
        const SizedBox(height: 10),
        DeckButton('Connect', tone: Tone.primary, onTap: _connect),
      ],
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen(this.state, {super.key});
  final SessionLogin state;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pin = TextEditingController();
  bool _show = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _submit() {
    if (_pin.text.isNotEmpty) {
      context.read<SessionBloc>().add(PinSubmitted(_pin.text));
    }
  }

  @override
  void didUpdateWidget(LoginScreen old) {
    super.didUpdateWidget(old);
    if (widget.state.error != null && old.state.busy) _pin.clear();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = widget.state;
    return _Frame(
      children: [
        _Brand(s.host.label),
        const SizedBox(height: 28),
        TextField(
          controller: _pin,
          autofocus: true,
          obscureText: !_show,
          enabled: !s.busy,
          textAlign: TextAlign.center,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontSize: 22, letterSpacing: 6),
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'PIN',
            errorText: s.error,
            errorMaxLines: 3,
            suffixIcon: IconButton(
              tooltip: _show ? 'Hide PIN' : 'Show PIN',
              onPressed: () => setState(() => _show = !_show),
              icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
            ),
          ),
        ),
        const SizedBox(height: 12),
        DeckButton('Unlock', tone: Tone.primary, busy: s.busy, onTap: _submit),
        const SizedBox(height: 10),
        DeckButton(
          'Choose another rig',
          onTap: s.busy
              ? null
              : () => context.read<SessionBloc>().add(const SwitchRigPressed()),
        ),
        const SizedBox(height: 18),
        Text(
          'No PIN yet? Run  hyprhand set-pin <PIN>  on the rig.'
          '${s.host.insecure ? '\n\nThis rig uses plain HTTP. Only log in on a network you trust.' : ''}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.5, color: p.onVar),
        ),
      ],
    );
  }
}
