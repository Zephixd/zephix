<div align="center">

# 🎧 Zephix Music

**Reproductor de música para Android, por GreenKnow Systems**

Tu biblioteca local y el catálogo en línea en una sola app, con letras sincronizadas,
ecualizador y estadísticas de escucha.

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![Riverpod](https://img.shields.io/badge/Riverpod-3-00B4D8?style=for-the-badge)
![SQLite](https://img.shields.io/badge/Drift-SQLite-003B57?style=for-the-badge&logo=sqlite&logoColor=white)
![Android](https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)

</div>

---

## Funcionalidades

### Reproducción
- ▶️ Reproducción en segundo plano con controles en notificación y pantalla de bloqueo (`audio_service`).
- 📜 Cola de reproducción editable y reproductor a pantalla completa.
- 🎚️ Ecualizador y ⏲️ temporizador de apagado.
- 🎨 Colores de la interfaz extraídos dinámicamente de la portada del tema.

### Biblioteca
- 📁 Escaneo de carpetas locales con lectura de metadatos de los archivos de audio.
- 🌐 Búsqueda y exploración de un catálogo en línea (álbumes, artistas y temas relacionados).
- 🏷️ Metadatos complementarios desde MusicBrainz.
- ⬇️ Descargas para escuchar sin conexión.
- ❤️ Favoritos, álbumes, artistas e historial de búsqueda.

### Playlists y letras
- 📝 Creación y edición de playlists, con importación y exportación en formato **M3U**.
- 🎤 Letras sincronizadas (formato LRC) con caché local.

### Estadísticas
- 📊 Historial de escucha, gráficos de uso y motor de recomendaciones propio.
- 💾 Copia de seguridad y restauración de la biblioteca y la configuración.

## Tecnologías

| Capa | Tecnología |
|---|---|
| Framework | Flutter · Dart |
| Estado | Riverpod |
| Navegación | go_router |
| Audio | just_audio · audio_service · audio_session |
| Persistencia | Drift (SQLite) |
| Red | dio |
| Interfaz | flutter_animate · fl_chart · cached_network_image |

## Arquitectura

```
lib/
├── app/             # Router, tema y shell de la aplicación
├── core/            # Servicios (audio handler, descargas) y utilidades
├── data/
│   ├── database/    # Esquema Drift: tracks, playlists, favoritos, historial, letras…
│   └── sources/     # Fuentes de música: biblioteca local, catálogo en línea, MusicBrainz
├── domain/          # Entidades
├── features/        # home · explore · search · library · player · playlists
│                    # lyrics · recommendations · statistics · profile · settings
└── shared/          # Widgets reutilizables
packages/            # Dependencias adaptadas (incluidas en el repositorio)
```

## Cómo ejecutarlo

**Requisitos:** Flutter 3.x y un dispositivo o emulador Android.

```bash
git clone https://github.com/Zephixd/zephix.git
cd zephix
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # genera el código de Drift
flutter run
```

## Créditos

La carpeta `packages/` incluye versiones adaptadas de:

- [`youtube_explode_dart`](https://github.com/Hexer10/youtube_explode_dart), en el fork mantenido
  por el proyecto [Musify](https://github.com/gokadzev/Musify) (licencia BSD, ver su `LICENSE`).
- `youtube_music_explode_dart`.

## Autor

**Mathias Sebastian Britos Griffith** — *GreenKnow*
Estudiante de Ingeniería Informática · Universidad Católica «Nuestra Señora de la Asunción», Unidad Pedagógica San Ignacio Guazú

[![Portfolio](https://img.shields.io/badge/Portfolio-greenknow-00ff9c?style=flat-square&logo=vercel&logoColor=white)](https://greenknow-portfolio.vercel.app)
[![GitHub](https://img.shields.io/badge/GitHub-Zephixd-181717?style=flat-square&logo=github)](https://github.com/Zephixd)
