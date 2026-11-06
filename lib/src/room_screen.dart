import 'package:flutter/material.dart';
import 'package:kodev_ui/kodev_ui.dart';
import 'package:koracle_engine/koracle_engine.dart';

import 'source_picker.dart';

const _qualityLabels = {
  KoracleQuality.text: 'Texto · 15 fps',
  KoracleQuality.standard: 'Padrão · 30 fps',
  KoracleQuality.game: 'Jogo · 60 fps',
};

class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.room});

  final KoracleRoom room;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  KoracleQuality _quality = KoracleQuality.game;
  bool _captureAudio = true;
  String? _sharedSource;
  String? _selectedOwner;
  String? _error;

  KoracleRoom get _room => widget.room;

  Future<void> _startShare() async {
    setState(() => _error = null);
    try {
      final sources = await _room.listSources();
      if (!mounted) return;
      final source = await showDialog<KoracleSource>(
        context: context,
        builder: (_) => SourcePicker(sources: sources),
      );
      if (source == null) return;
      await _room.startShare(source, quality: _quality, captureAudio: _captureAudio);
      setState(() => _sharedSource = source.name);
    } catch (error) {
      if (mounted) setState(() => _error = 'Não foi possível transmitir: $error');
    }
  }

  Future<void> _stopShare() async {
    try {
      await _room.stopShare();
    } catch (error) {
      if (mounted) setState(() => _error = 'Não foi possível parar: $error');
    }
  }

  String _describe(KoracleStats stats) {
    final parts = [
      if (stats.mbps case final mbps?) '${mbps.toStringAsFixed(1)} Mbps',
      if (stats.width != null) '${stats.width}x${stats.height}',
      if (stats.fps != null) '${stats.fps} fps',
      if (stats.limit case final limit? when limit != 'none') 'limitado por $limit',
      if (stats.lost case final lost? when lost > 0) '$lost pacotes perdidos',
      ?stats.codec,
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = KODevColors.of(context);
    final text = Theme.of(context).textTheme;
    final streams = _room.streams;
    final selected = streams.where((s) => s.owner == _selectedOwner).firstOrNull ?? streams.firstOrNull;
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Bar(
            border: Border(bottom: BorderSide(color: colors.border)),
            children: [
              const KODevKoalita(size: 24, decorative: true),
              const SizedBox(width: KODevSpace.space2),
              Text('KOracle', style: text.titleMedium),
              const SizedBox(width: KODevSpace.space4),
              Text(
                _room.isReconnecting ? 'Reconectando...' : '${_room.participantCount} na sala',
                style: muted,
              ),
              const SizedBox(width: KODevSpace.space4),
              for (final stream in streams)
                Padding(
                  padding: const EdgeInsets.only(right: KODevSpace.space2),
                  child: OutlinedButton(
                    onPressed: () => setState(() => _selectedOwner = stream.owner),
                    child: Text(stream.owner),
                  ),
                ),
              const Spacer(),
              OutlinedButton(onPressed: _room.leave, child: const Text('Sair')),
            ],
          ),
          Expanded(
            child: ColoredBox(
              color: Colors.black,
              child: selected != null
                  ? KoracleStreamView(selected, key: ValueKey(selected.owner))
                  : Center(
                      child: Text(
                        _room.isSharing ? 'Você está transmitindo.' : 'Ninguém está transmitindo ainda.',
                        style: text.bodyLarge?.copyWith(color: colors.inkMuted),
                      ),
                    ),
            ),
          ),
          _Bar(
            border: Border(top: BorderSide(color: colors.border)),
            children: [
              DropdownButton<KoracleQuality>(
                value: _quality,
                underline: const SizedBox.shrink(),
                onChanged: _room.isSharing ? null : (value) => setState(() => _quality = value!),
                items: [
                  for (final entry in _qualityLabels.entries)
                    DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                ],
              ),
              const SizedBox(width: KODevSpace.space4),
              Checkbox(
                value: _captureAudio,
                onChanged: _room.isSharing ? null : (value) => setState(() => _captureAudio = value!),
              ),
              Tooltip(
                message: 'Vai todo o áudio do computador, inclusive uma call no Discord.',
                child: Text('Áudio do sistema', style: text.bodyMedium),
              ),
              const Spacer(),
              if (_room.isSharing) ...[
                Flexible(
                  child: Text(
                    'Transmitindo ${_sharedSource ?? ''}${_room.isSharingAudio ? ' com áudio' : ' sem áudio'}',
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: colors.inkAccent),
                  ),
                ),
                const SizedBox(width: KODevSpace.space3),
              ],
              FilledButton(
                onPressed: _room.isSharing ? _stopShare : _startShare,
                child: Text(_room.isSharing ? 'Parar' : 'Transmitir'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(KODevSpace.space4, 0, KODevSpace.space4, KODevSpace.space2),
            child: Text(
              [
                ?_error,
                if (_room.sendStats case final stats?) 'Enviando: ${_describe(stats)}',
                if (_room.receiveStats case final stats? when selected != null) 'Recebendo: ${_describe(stats)}',
              ].join('   '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _error == null ? muted : text.bodySmall?.copyWith(color: colors.danger),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.border, required this.children});

  final Border border;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(border: border),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: KODevSpace.space4, vertical: KODevSpace.space2),
        child: Row(children: children),
      ),
    );
  }
}
