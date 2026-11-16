import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/routes.dart';
import '../../app/theme/zephix_colors.dart';
import '../../core/utils/format.dart';
import '../../data/database/app_database.dart';
import '../../data/sources/music_source_provider.dart';
import '../../data/sources/musicbrainz_client.dart';
import '../../data/sources/source_registry.dart';
import '../../domain/entities/track_x.dart';
import '../../features/playlists/playlist_dialogs.dart';
import 'artwork.dart';
import 'common.dart';

class TrackMenuAction {
  const TrackMenuAction(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Playback shortcuts usable from any widget.
extension PlaybackRef on WidgetRef {
  Future<void> playTracks(List<TrackRow> tracks, {int index = 0, bool shuffle = false}) =>
      read(audioHandlerProvider).playTracks(tracks, index: index, shuffle: shuffle);
}

Future<void> showTrackActions(BuildContext context, WidgetRef ref, TrackRow track,
    {List<TrackMenuAction> extra = const []}) {
  final handler = ref.read(audioHandlerProvider);
  final db = ref.read(databaseProvider);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) {
      final isFav = ref.read(favoriteIdsProvider).value?.contains(track.id) ?? false;
      void close() => Navigator.pop(sheet);
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: SizedBox(
                  width: 52,
                  height: 52,
                  child: Artwork(path: track.artPath, url: track.artUrl, seed: '${track.album}${track.artist}', size: 52),
                ),
                title: Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.tt.titleMedium),
                subtitle: Text('${track.artist} · ${track.album}', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const Divider(),
              for (final a in extra)
                ListTile(leading: Icon(a.icon), title: Text(a.label), onTap: () {
                  close();
                  a.onTap();
                }),
              ListTile(
                leading: const Icon(Icons.playlist_play_rounded),
                title: const Text('Reproducir a continuación'),
                onTap: () {
                  close();
                  handler.playNext([track]);
                  showSnack(context, 'Sonará a continuación');
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: const Text('Añadir a la cola'),
                onTap: () {
                  close();
                  handler.enqueue([track]);
                  showSnack(context, 'Añadido a la cola');
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded),
                title: const Text('Añadir a playlist'),
                onTap: () {
                  close();
                  showAddToPlaylistSheet(context, ref, [track.id]);
                },
              ),
              ListTile(
                leading: Icon(isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: isFav ? context.zc.primary : null),
                title: Text(isFav ? 'Quitar de favoritos' : 'Añadir a favoritos'),
                onTap: () {
                  close();
                  db.toggleFavorite(track.id);
                },
              ),
              ListTile(
                leading: const Icon(Icons.album_rounded),
                title: const Text('Ir al álbum'),
                onTap: () {
                  close();
                  context.push(Routes.album(track.album, track.displayArtist));
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_rounded),
                title: const Text('Ir al artista'),
                onTap: () {
                  close();
                  context.push(Routes.artist(track.artist));
                },
              ),
              if (track.isRemote &&
                  (sourceInfoById(track.source)?.can(SourceCapability.download) ?? false))
                ListTile(
                  leading: const Icon(Icons.download_rounded),
                  title: const Text('Descargar'),
                  subtitle: Text(track.license ?? 'Licencia abierta', style: context.tt.bodySmall),
                  onTap: () async {
                    close();
                    showSnack(context, 'Descargando “${track.title}”…');
                    try {
                      final updated = await ref.read(downloadServiceProvider).download(track);
                      handler.refreshTrack(updated);
                      if (context.mounted) showSnack(context, 'Descarga completada');
                    } catch (e) {
                      if (context.mounted) showSnack(context, 'No se pudo descargar: $e');
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.manage_search_rounded),
                title: const Text('Corregir metadatos'),
                subtitle: Text('Buscar en MusicBrainz', style: context.tt.bodySmall),
                onTap: () {
                  close();
                  showMetadataLookup(context, ref, track);
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Detalles'),
                onTap: () {
                  close();
                  _showDetails(context, track);
                },
              ),
              ListTile(
                leading: const Icon(Icons.remove_circle_outline_rounded),
                title: const Text('Quitar de la biblioteca'),
                subtitle: Text('El archivo no se borra del dispositivo', style: context.tt.bodySmall),
                onTap: () async {
                  close();
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('¿Quitar de la biblioteca?'),
                      content: Text(
                          '“${track.title}” se quitará de Zephix junto con su historial y su lugar en playlists. '
                          'El archivo seguirá en tu dispositivo y volverá a aparecer si reescaneas su carpeta.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Quitar')),
                      ],
                    ),
                  );
                  if (ok == true) await db.deleteTrack(track.id);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

void _showDetails(BuildContext context, TrackRow t) {
  final rows = <(String, String?)>[
    ('Título', t.title),
    ('Artista', t.artist),
    ('Álbum', t.album),
    ('Artista del álbum', t.albumArtist),
    ('Género', t.genre),
    ('Año', t.year?.toString()),
    ('Pista', t.trackNumber?.toString()),
    ('Duración', t.durationMs > 0 ? formatMs(t.durationMs) : null),
    ('Fuente', t.source == 'local' ? 'Archivo local' : 'Internet Archive'),
    ('Licencia', t.license),
    ('Tamaño', t.fileSize == null ? null : '${(t.fileSize! / 1048576).toStringAsFixed(1)} MB'),
    ('Ubicación', t.filePath ?? t.uri),
  ];
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Detalles'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (k, v) in rows)
              if (v != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(k.toUpperCase(), style: context.tt.labelSmall),
                      SelectableText(v, style: context.tt.bodyMedium),
                    ],
                  ),
                ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar'))],
    ),
  );
}

/// Searches MusicBrainz for the track and applies the chosen match.
Future<void> showMetadataLookup(BuildContext context, WidgetRef ref, TrackRow track) async {
  final client = ref.read(musicBrainzProvider);
  final db = ref.read(databaseProvider);
  final future = client.searchRecording(track.title,
      artist: track.artist == 'Artista desconocido' ? null : track.artist);
  final chosen = await showModalBottomSheet<MusicBrainzMatch>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.75),
      child: FutureBuilder<List<MusicBrainzMatch>>(
        future: future,
        builder: (c, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasError) {
            return const EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'MusicBrainz no respondió',
                message: 'Comprueba tu conexión e inténtalo de nuevo.');
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return const EmptyState(icon: Icons.search_off_rounded, title: 'Sin coincidencias');
          }
          return ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Coincidencias en MusicBrainz', style: c.tt.titleLarge),
              ),
              for (final m in list)
                ListTile(
                  title: Text(m.title),
                  subtitle: Text([
                    m.artist,
                    if (m.album != null) m.album!,
                    if (m.year != null) '${m.year}',
                    if (m.lengthMs != null) formatMs(m.lengthMs!),
                  ].join(' · ')),
                  trailing: Text('${m.score}%', style: c.tt.labelMedium),
                  onTap: () => Navigator.pop(sheet, m),
                ),
            ],
          );
        },
      ),
    ),
  );
  if (chosen == null) return;
  await (db.update(db.tracks)..where((t) => t.id.equals(track.id))).write(TracksCompanion(
    title: Value(chosen.title),
    artist: Value(chosen.artist.isEmpty ? track.artist : chosen.artist),
    album: Value(chosen.album ?? track.album),
    year: Value(chosen.year ?? track.year),
  ));
  final updated = await db.trackById(track.id);
  if (updated != null) ref.read(audioHandlerProvider).refreshTrack(updated);
  if (context.mounted) showSnack(context, 'Metadatos actualizados');
}
