import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../app/router/routes.dart';
import '../../app/theme/zephix_colors.dart';
import '../../app/theme/zephix_theme.dart';
import '../../core/constants/app_info.dart';
import '../../data/sources/music_source_provider.dart';
import '../../data/sources/source_registry.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/zephix_logo.dart';
import 'app_settings.dart';
import 'backup_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final db = ref.read(databaseProvider);
    final zc = context.zc;

    Future<void> confirm(String title, String body, Future<void> Function() action, String done) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar')),
          ],
        ),
      );
      if (ok != true) return;
      await action();
      if (context.mounted) showSnack(context, done);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          const _Group('Apariencia'),
          ListTile(
            title: const Text('Tema'),
            trailing: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), tooltip: 'Oscuro'),
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), tooltip: 'Claro'),
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), tooltip: 'Sistema'),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => n.update((x) => x.copyWith(themeMode: v.first)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(ZSpace.page, 4, ZSpace.page, 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final a in AccentChoice.values)
                  Semantics(
                    button: true,
                    selected: s.accent == a,
                    label: 'Color de acento ${a.label}',
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => n.update((x) => x.copyWith(accent: a)),
                      child: Column(
                        children: [
                          AnimatedContainer(
                            duration: ZMotion.fast,
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark ? a.dark : a.light,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: s.accent == a ? zc.textPrimary : Colors.transparent, width: 2.5),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(a.label, style: context.tt.labelMedium),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Resumen semanal en Inicio'),
            value: s.showStatsOnHome,
            onChanged: (v) => n.update((x) => x.copyWith(showStatsOnHome: v)),
          ),
          const _Group('Reproducción'),
          SwitchListTile(
            title: const Text('Omitir silencios'),
            subtitle: const Text('Salta los tramos sin sonido al inicio y final de las pistas'),
            value: s.skipSilence,
            onChanged: (v) => n.update((x) => x.copyWith(skipSilence: v)),
          ),
          ListTile(
            title: const Text('Ecualizador'),
            subtitle: Text(s.eqEnabled ? 'Activado' : 'Desactivado'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(Routes.equalizer),
          ),
          ListTile(
            title: const Text('Calidad de streaming'),
            subtitle: const Text('Para el catálogo abierto. Los archivos locales se reproducen siempre en su calidad original.'),
            trailing: DropdownButton<StreamQuality>(
              value: s.streamQuality,
              underline: const SizedBox.shrink(),
              onChanged: (v) => n.update((x) => x.copyWith(streamQuality: v)),
              items: const [
                DropdownMenuItem(value: StreamQuality.standard, child: Text('MP3')),
                DropdownMenuItem(value: StreamQuality.lossless, child: Text('FLAC si existe')),
              ],
            ),
          ),
          const _Group('Biblioteca'),
          ListTile(
            title: const Text('Carpetas de música'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(Routes.folders),
          ),
          ListTile(
            title: const Text('Reescanear biblioteca'),
            subtitle: const Text('Busca archivos nuevos, cambiados o eliminados'),
            onTap: () {
              ref.read(scanProvider.notifier).scan();
              showSnack(context, 'Escaneando…');
            },
          ),
          ListTile(
            title: const Text('Reconstruir metadatos'),
            subtitle: const Text('Vuelve a leer las etiquetas de todos los archivos'),
            onTap: () {
              ref.read(scanProvider.notifier).scan(force: true);
              showSnack(context, 'Reconstruyendo…');
            },
          ),
          ListTile(
            title: const Text('Ignorar archivos cortos'),
            subtitle: Text('Menos de ${s.minTrackSeconds} s (tonos y notificaciones)'),
            trailing: DropdownButton<int>(
              value: s.minTrackSeconds,
              underline: const SizedBox.shrink(),
              onChanged: (v) => n.update((x) => x.copyWith(minTrackSeconds: v)),
              items: const [
                DropdownMenuItem(value: 0, child: Text('No')),
                DropdownMenuItem(value: 10, child: Text('10 s')),
                DropdownMenuItem(value: 20, child: Text('20 s')),
                DropdownMenuItem(value: 45, child: Text('45 s')),
              ],
            ),
          ),
          const _Group('Letras'),
          SwitchListTile(
            title: const Text('Buscar letras en línea'),
            subtitle: const Text('Consulta LRCLIB cuando el archivo no trae letra'),
            value: s.onlineLyrics,
            onChanged: (v) => n.update((x) => x.copyWith(onlineLyrics: v)),
          ),
          ListTile(
            title: const Text('Borrar letras guardadas'),
            onTap: () => confirm('¿Borrar letras guardadas?', 'Se volverán a descargar cuando las abras.',
                db.clearLyricsCache, 'Letras borradas'),
          ),
          const _Group('Fuentes y descargas'),
          SwitchListTile(
            title: const Text('YouTube Music'),
            subtitle: const Text('Busca y reproduce el catálogo completo como audio directo, sin anuncios'),
            value: s.openCatalogs,
            onChanged: (v) => n.update((x) => x.copyWith(openCatalogs: v)),
          ),
          ListTile(
            title: const Text('Fuentes musicales'),
            subtitle: const Text('Capacidades y restricciones de cada fuente'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(Routes.sources),
          ),
          ListTile(
            title: const Text('Descargas'),
            subtitle: const Text('Pistas con licencia abierta guardadas para escuchar sin conexión'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(Routes.libraryList('downloads')),
          ),
          const _Group('Privacidad'),
          SwitchListTile(
            title: const Text('Guardar historial de escucha'),
            subtitle: const Text('Necesario para estadísticas y mezclas. Nunca sale del dispositivo.'),
            value: s.historyEnabled,
            onChanged: (v) => n.update((x) => x.copyWith(historyEnabled: v)),
          ),
          ListTile(
            title: const Text('Borrar historial de escucha'),
            onTap: () => confirm('¿Borrar historial?',
                'Se eliminarán tus estadísticas y las mezclas se reiniciarán. No se puede deshacer.',
                db.clearHistory, 'Historial borrado'),
          ),
          ListTile(
            title: const Text('Borrar búsquedas recientes'),
            onTap: () => confirm('¿Borrar búsquedas?', 'Se eliminará el historial de búsquedas.',
                db.clearSearchHistory, 'Búsquedas borradas'),
          ),
          ListTile(
            title: const Text('Comunicaciones externas'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(Routes.privacy),
          ),
          ListTile(
            title: const Text('Permisos de la app'),
            subtitle: const Text('Abre los ajustes del sistema'),
            onTap: openAppSettings,
          ),
          const _Group('Copias de seguridad'),
          ListTile(
            leading: const Icon(Icons.upload_file_rounded),
            title: const Text('Exportar copia'),
            subtitle: const Text('Playlists, favoritos, historial y preferencias en JSON'),
            onTap: () async {
              final json = await BackupService(db).export();
              final dir = await getTemporaryDirectory();
              final stamp = DateTime.now().toIso8601String().substring(0, 10);
              final f = File(p.join(dir.path, 'zephix-backup-$stamp.json'));
              await f.writeAsString(json, flush: true);
              await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/json')]));
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: const Text('Restaurar copia'),
            subtitle: const Text('Combina la copia con tus datos actuales'),
            onTap: () async {
              final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['json']);
              if (files.isEmpty || files.first.path == null) return;
              try {
                final r = await BackupService(db).import(await File(files.first.path!).readAsString());
                if (!context.mounted) return;
                showSnack(context,
                    'Restauradas ${r.playlists} playlists, ${r.favorites} favoritos y ${r.history} reproducciones'
                    '${r.unmatched > 0 ? ' · ${r.unmatched} canciones no encontradas' : ''}');
              } catch (e) {
                if (context.mounted) showSnack(context, 'No se pudo restaurar: $e');
              }
            },
          ),
          const _Group('Información'),
          ListTile(
            title: Text('Acerca de ${AppInfo.commercialName}'),
            subtitle: const Text('Versión ${AppInfo.version}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(Routes.about),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.xl, ZSpace.page, ZSpace.xs),
        child: Text(title.toUpperCase(), style: context.tt.labelSmall?.copyWith(color: context.zc.primary)),
      );
}

class FoldersScreen extends ConsumerWidget {
  const FoldersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(libraryFoldersProvider).value ?? const [];
    final db = ref.read(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Carpetas de música')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (!await ScanNotifier.ensurePermission()) {
            if (context.mounted) showSnack(context, 'Concede acceso a tu música primero.');
            return;
          }
          final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Carpeta de música');
          if (dir == null) return;
          await db.addLibraryFolder(dir);
          await ref.read(scanProvider.notifier).scan();
        },
        icon: const Icon(Icons.create_new_folder_rounded),
        label: const Text('Añadir carpeta'),
      ),
      body: folders.isEmpty
          ? const EmptyState(
              icon: Icons.folder_open_rounded,
              title: 'Sin carpetas',
              message: 'Al escanear por primera vez se usan Música y Descargas. Puedes añadir otras aquí.',
            )
          : ListView(
              children: [
                for (final f in folders)
                  ListTile(
                    leading: const Icon(Icons.folder_rounded),
                    title: Text(f.path),
                    trailing: IconButton(
                      tooltip: 'Quitar carpeta',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('¿Quitar carpeta?'),
                            content: const Text(
                                'Sus canciones se quitarán de la biblioteca. Los archivos no se borran del dispositivo.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Quitar')),
                            ],
                          ),
                        );
                        if (ok == true) await db.removeLibraryFolder(f.path);
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}

class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = [localSourceInfo, ...audioSourceInfos];
    return Scaffold(
      appBar: AppBar(title: const Text('Fuentes musicales')),
      body: ListView(
        padding: const EdgeInsets.all(ZSpace.page),
        children: [
          for (final s in sources) ...[_SourceCard(info: s), const SizedBox(height: ZSpace.md)],
          Text(
            'YouTube Music se consulta mediante sus interfaces de cliente (InnerTube) y se reproduce el '
            'archivo de audio que el propio servidor entrega, sin el reproductor web que inyecta anuncios. '
            'Zephix no descifra DRM ni guarda esos archivos; MusicBrainz y LRCLIB se siguen usando solo para '
            'metadatos y letras.',
            style: context.tt.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.info});
  final SourceInfo info;

  @override
  Widget build(BuildContext context) {
    final zc = context.zc;
    String cap(SourceCapability c) => switch (c) {
          SourceCapability.search => 'Búsqueda',
          SourceCapability.stream => 'Reproducción',
          SourceCapability.download => 'Descarga',
          SourceCapability.offline => 'Sin conexión',
        };
    return Container(
      padding: const EdgeInsets.all(ZSpace.lg),
      decoration: BoxDecoration(
        color: zc.surface,
        borderRadius: BorderRadius.circular(ZRadius.md),
        border: Border.all(color: zc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(info.name, style: context.tt.titleLarge),
          const SizedBox(height: 4),
          Text(info.description, style: context.tt.bodyMedium),
          const SizedBox(height: ZSpace.md),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in info.capabilities) Pill(cap(c).toUpperCase(), color: zc.primary),
            if (info.requiresNetwork) Pill('REQUIERE INTERNET', color: zc.secondary),
          ]),
          if (info.restrictions.isNotEmpty) ...[
            const SizedBox(height: ZSpace.md),
            for (final r in info.restrictions)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $r', style: context.tt.bodySmall),
              ),
          ],
        ],
      ),
    );
  }
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('LRCLIB (lrclib.net)', 'Título, artista, álbum y duración de la canción cuya letra abres.',
          'Solo si “Buscar letras en línea” está activado.'),
      ('MusicBrainz (musicbrainz.org)', 'Título y artista de la canción.',
          'Solo cuando pulsas “Corregir metadatos”.'),
      ('YouTube Music (youtubei + googlevideo)',
          'Tus términos de búsqueda, los identificadores de vídeo que reproduces y tu dirección IP '
          '(los servidores de Google la registran).',
          'Solo con “YouTube Music” activado.'),
      ('Imágenes de portada', 'Peticiones de imagen a los servidores de miniaturas de YouTube.', 'Se guardan en caché.'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Privacidad')),
      body: ListView(
        padding: const EdgeInsets.all(ZSpace.page),
        children: [
          Text('Sin cuenta, sin anuncios, sin rastreo', style: context.tt.headlineSmall),
          const SizedBox(height: ZSpace.sm),
          Text(
            'Zephix no incluye publicidad, SDK de anuncios, analítica ni telemetría. Tu biblioteca, historial, '
            'estadísticas y playlists se guardan solo en este dispositivo y no se sincronizan con ningún servidor.',
            style: context.tt.bodyMedium,
          ),
          const SizedBox(height: ZSpace.xl),
          Text('Comunicaciones externas', style: context.tt.titleLarge),
          const SizedBox(height: ZSpace.sm),
          for (final (who, what, cond) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: ZSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(who, style: context.tt.titleSmall),
                  Text('Envía: $what', style: context.tt.bodySmall),
                  Text(cond, style: context.tt.bodySmall),
                ],
              ),
            ),
          Text(
            'Cada petición se identifica como “${AppInfo.userAgent}”, sin datos personales. '
            'No se envían identificadores del dispositivo ni tu historial.',
            style: context.tt.bodySmall,
          ),
        ],
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acerca de')),
      body: ListView(
        padding: const EdgeInsets.all(ZSpace.page),
        children: [
          const SizedBox(height: ZSpace.xl),
          Center(child: ZephixMark(size: 112, background: context.zc.surfaceElevated)),
          const SizedBox(height: ZSpace.lg),
          Center(child: Text(AppInfo.commercialName, style: context.tt.headlineLarge)),
          Center(child: Text('Versión ${AppInfo.version} · ${AppInfo.developer}', style: context.tt.bodySmall)),
          const SizedBox(height: ZSpace.xl),
          Text(
            'Un reproductor musical independiente, sin publicidad, sin suscripciones y sin registro.',
            style: context.tt.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: ZSpace.xl),
          OutlinedButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: AppInfo.commercialName,
              applicationVersion: AppInfo.version,
              applicationLegalese: '© ${DateTime.now().year} ${AppInfo.developer}',
            ),
            child: const Text('Licencias de código abierto'),
          ),
        ],
      ),
    );
  }
}
