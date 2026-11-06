import 'package:flutter/material.dart';
import 'package:kodev_ui/kodev_ui.dart';
import 'package:koracle_engine/koracle_engine.dart';

/// Set when building: --dart-define=KORACLE_SERVER_URL=wss://...
const serverUrl = String.fromEnvironment('KORACLE_SERVER_URL', defaultValue: 'ws://localhost:7880');

/// An invite code is a LiveKit token, a JWT with three parts.
bool looksLikeInvite(String code) {
  final parts = code.trim().split('.');
  return parts.length == 3 && parts.every((part) => part.isNotEmpty);
}

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.room});

  final KoracleRoom room;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _code = TextEditingController(text: const String.fromEnvironment('KORACLE_INVITE'));
  bool _joining = false;
  String? _error;

  Future<void> _join() async {
    final code = _code.text.trim();
    if (!looksLikeInvite(code)) {
      setState(() => _error = 'Esse código não parece um convite. Copie ele inteiro.');
      return;
    }
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      await widget.room.join(url: serverUrl, token: code);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = 'Não foi possível entrar. Confira o código e a internet.\n$error';
      });
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = KODevColors.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(KODevSpace.space6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: KODevKoalita(size: 72, decorative: true)),
                const SizedBox(height: KODevSpace.space6),
                Text('KOracle', textAlign: TextAlign.center, style: text.headlineMedium),
                const SizedBox(height: KODevSpace.space2),
                Text(
                  'Cole o código de convite para entrar na sala.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: colors.inkMuted),
                ),
                const SizedBox(height: KODevSpace.space6),
                TextField(
                  controller: _code,
                  enabled: !_joining,
                  autofocus: true,
                  onSubmitted: (_) => _join(),
                  decoration: const InputDecoration(hintText: 'Código de convite'),
                ),
                const SizedBox(height: KODevSpace.space3),
                FilledButton(
                  onPressed: _joining ? null : _join,
                  child: Text(_joining ? 'Entrando...' : 'Entrar'),
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: KODevSpace.space3),
                  Text(error, style: text.bodySmall?.copyWith(color: colors.danger)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
