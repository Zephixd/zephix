import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/zephix_colors.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/artwork.dart';
import '../../shared/widgets/common.dart';

/// Asks for a playlist name. Returns (name, description) or null.
Future<(String, String?)?> showPlaylistNameDialog(
  BuildContext context, {
  String title = 'Nueva playlist',
  String? initialName,
  String? initialDescription,
  String confirm = 'Crear',
}) {
  final name = TextEditingController(text: initialName);
  final desc = TextEditingController(text: initialDescription);
  final formKey = GlobalKey<FormState>();
  return showDialog<(String, String?)>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: name,
              autofocus: true,
              maxLength: 120,
              decoration: const InputDecoration(hintText: 'Nombre'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe un nombre' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: desc,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'Descripción (opcional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            final d = desc.text.trim();
            Navigator.pop(c, (name.text.trim(), d.isEmpty ? null : d));
          },
          child: Text(confirm),
        ),
      ],
    ),
  );
}

/// Lets the user pick (or create) a playlist and adds [trackIds] to it.
Future<void> showAddToPlaylistSheet(BuildContext context, WidgetRef ref, List<int> trackIds) async {
  final db = ref.read(databaseProvider);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => Consumer(builder: (context, ref, _) {
      final playlists = ref.watch(playlistsProvider).value ?? const [];
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Añadir a playlist', style: context.tt.titleLarge),
            ),
            ListTile(
              leading: Icon(Icons.add_rounded, color: context.zc.primary),
              title: const Text('Nueva playlist'),
              onTap: () async {
                final r = await showPlaylistNameDialog(context);
                if (r == null) return;
                final id = await db.createPlaylist(r.$1, description: r.$2);
                await db.addTracksToPlaylist(id, trackIds);
                if (sheet.mounted) Navigator.pop(sheet);
                if (context.mounted) showSnack(context, 'Añadido a “${r.$1}”');
              },
            ),
            for (final p in playlists)
              ListTile(
                leading: SizedBox(
                  width: 44,
                  height: 44,
                  child: Artwork(path: p.artPath, seed: p.playlist.name, size: 44, icon: Icons.queue_music_rounded),
                ),
                title: Text(p.playlist.name),
                subtitle: Text(plural(p.trackCount, 'canción', 'canciones'), style: context.tt.bodySmall),
                onTap: () async {
                  await db.addTracksToPlaylist(p.playlist.id, trackIds);
                  if (sheet.mounted) Navigator.pop(sheet);
                  if (context.mounted) showSnack(context, 'Añadido a “${p.playlist.name}”');
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      );
    }),
  );
}
