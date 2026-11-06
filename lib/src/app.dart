import 'package:flutter/material.dart';
import 'package:koracle_engine/koracle_engine.dart';

import 'join_screen.dart';
import 'room_screen.dart';
import 'theme.dart';

class KOracleApp extends StatefulWidget {
  const KOracleApp({super.key});

  @override
  State<KOracleApp> createState() => _KOracleAppState();
}

class _KOracleAppState extends State<KOracleApp> {
  final _room = KoracleRoom();

  @override
  void dispose() {
    _room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KOracle',
      debugShowCheckedModeBanner: false,
      theme: koracleTheme(),
      home: ListenableBuilder(
        listenable: _room,
        builder: (context, _) => _room.isConnected ? RoomScreen(room: _room) : JoinScreen(room: _room),
      ),
    );
  }
}
