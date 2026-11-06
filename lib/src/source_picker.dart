import 'package:flutter/material.dart';
import 'package:kodev_ui/kodev_ui.dart';
import 'package:koracle_engine/koracle_engine.dart';

/// Lets the user choose what to share. Screens come first.
class SourcePicker extends StatelessWidget {
  const SourcePicker({super.key, required this.sources});

  final List<KoracleSource> sources;

  @override
  Widget build(BuildContext context) {
    final colors = KODevColors.of(context);
    final sorted = [...sources.where((s) => s.isScreen), ...sources.where((s) => !s.isScreen)];
    return AlertDialog(
      title: const Text('O que você quer transmitir?'),
      content: SizedBox(
        width: 720,
        height: 480,
        child: GridView.extent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: KODevSpace.space3,
          crossAxisSpacing: KODevSpace.space3,
          children: [
            for (final source in sorted)
              KODevCard(
                semanticLabel: source.name,
                onTap: () => Navigator.pop(context, source),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: source.thumbnail == null
                          ? Icon(source.isScreen ? Icons.monitor : Icons.web_asset, color: colors.inkMuted, size: 40)
                          : Image.memory(source.thumbnail!, fit: BoxFit.contain),
                    ),
                    const SizedBox(height: KODevSpace.space2),
                    Text(source.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      ],
    );
  }
}
