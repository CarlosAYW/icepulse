# Eiskarte

Tägliche Eiskarte für Eisfälle in Nordtirol, basierend auf dem Modell der Masterarbeit.

**Karte:** https://carlosayw.github.io/eiskarte/

## Täglicher Ablauf

`.github/workflows/build_site.yml` läuft jeden Tag um 15:00 UTC und veröffentlicht das Ergebnis auf GitHub Pages:

1. `scripts/00_roll_sun_tables.R`: datiert die Sonnentabellen (Saison 2025/26, 1.11. bis 30.4.) auf die laufende Saison um
2. `scripts/00_build_plots_all.R`: rechnet das Modell für jede Route ab dem 1. Oktober der laufenden Saison
3. `scripts/02_build_list_page.R`: erzeugt die Routenliste und die Detailseiten
4. `scripts/01_build_map.R`: erzeugt die Karte aus den INCA-Feldern

Wetterdaten werden bei jedem Lauf von GeoSphere Austria und dem Lawinenwarndienst Tirol geladen. Generierte Dateien liegen nicht in Git. Die INCA-Felder liegen im Actions-Cache.

Schlagen mehr als 10 % der Routen fehl, wird nichts veröffentlicht und die Karte vom Vortag bleibt online.

## Manuell starten

```bash
gh workflow run build_site.yml
```

Ein Testlauf mit einzelnen Routen wird nicht veröffentlicht. Das Ergebnis liegt als Artefakt am Lauf:

```bash
gh workflow run build_site.yml -f uids=1,48
```

## Neue Eisfälle

Zeilen in `add_new/new_icefalls.csv` eintragen und dann `Rscript scripts/add_new_icefalls.R` ausführen. Die dafür nötigen großen Höhenmodelle liegen nicht in diesem Repo, sondern nur lokal in `ice-waterfalls/data/DEM`. Details stehen in `add_new/README.md`.

## Herkunft

Der Code stammt aus [CarlosAYW/ice-waterfalls](https://github.com/CarlosAYW/ice-waterfalls) (Stand `0f85d2d`), also inklusive der nach der Abgabe korrigierten Solarterm-Indizierung. Der Modellstand der Arbeit selbst ist dort unter dem Tag `thesis-submission` eingefroren. Einstieg für die Begutachtung der Arbeit ist [CarlosAYW/waterfall-ice-thesis](https://github.com/CarlosAYW/waterfall-ice-thesis).

Änderungen gegenüber `ice-waterfalls` in `scripts/01_build_map.R`:

- Der Saisonstart wird aus dem Datum berechnet und ist nicht mehr fest auf den 1.10.2025 gesetzt.
- Es werden nur noch die vier verwendeten INCA-Variablen geladen (T2M, RH2M, UU, VV).
- Die letzten Tage werden neu geladen, damit unvollständige Downloads nicht im Cache bleiben.

## Copyright und Nutzung

Copyright (c) 2026. All rights reserved.

Dieses Repository entstand im Rahmen einer Masterarbeit. Code, Modelle, Skripte, Texte, Grafiken und weitere Inhalte sind urheberrechtlich geschützt. Kopieren, Weitergabe, Veröffentlichung, Bearbeitung, abgeleitete Werke, die Nutzung in anderen Projekten oder Lehrmaterialien sowie kommerzielle Nutzung sind ohne vorherige schriftliche Erlaubnis nicht gestattet.
