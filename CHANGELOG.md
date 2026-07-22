# Changelog — Nidus (app SwiftUI)

Registro de lo añadido, descartado y decidido, tramo a tramo.
Formato humano. La extensión Raycast lleva su propio changelog aparte (otro codebase).

---

## La extensión de Raycast entra al repo · Miércoles, 22 de julio de 2026

Estaba construida y funcionando desde el 9 de julio, pero vivía **fuera del repo**: ni en el README ni en
Releases. Existía sin ser encontrable, que para algo open source es casi lo mismo que no existir.

- **`raycast/`** — el código de la extensión, sin `node_modules` ni build. Verificado en limpio: copia
  aparte, `npm ci` + `npm run build` desde cero, para asegurar que lo que se publica basta por sí solo y
  no dependía de ficheros que solo existían en la carpeta original.
- **Licencia unificada a AGPL-3.0** (decisión del usuario). El `package.json` venía con el `MIT` que pone
  la plantilla de `create-raycast-extension`; heredar eso por descuido habría metido una subcarpeta
  permisiva en un repo AGPL sin que nadie lo decidiera.
- **README**: la extensión sube al primer párrafo junto a la app y la PWA — *tres formas de entrar,
  las tres escribiendo en los mismos ficheros Markdown* — con su propia sección, la gramática de captura
  (`--`, `t-`, alias) y la instalación manual.
- **No va a la Raycast Store todavía** (decisión del usuario): no hay binario instalable para una
  extensión de Raycast, así que la vía es clonar → `npm install && npm run dev` → *Import Extension*.
  Confirmado en la documentación de Raycast, no de memoria.
- Se queda **fuera** `HANDOFF.md`: es andamiaje escrito para quien construyó la extensión, y su §2 describe
  la carpeta como "plantilla recién creada sin modificar" — dejó de ser verdad el primer día. Publicar
  documentación que miente sobre el estado actual es peor que no publicarla.
- `npm audit` da 2 avisos de severidad baja en esbuild vía `@raycast/api`; afectan al dev server **en
  Windows** y esto es solo macOS. Arreglarlos degradaría `@raycast/api`, así que se quedan.

---

## v1.0.1 · Icono, aviso de actualización y atajos documentados · Miércoles, 22 de julio de 2026

Tres cosas que el usuario detectó mirando la release publicada.

- **El icono nunca llegó a la app.** `AppIcon.appiconset/Contents.json` era el andamiaje vacío de Xcode:
  trece slots declarados y **ni un solo `filename`**. Compilaba sin un aviso y sin `.icns` en el bundle, así
  que el fallo era completamente silencioso. Ahora `nidusicon1024x1024.png` genera los diez tamaños de macOS
  (un fichero por slot) más el de iOS, y las tres versiones opacas de la PWA.
  - Ojo con el diagnóstico: el `.icns` del bundle SOLO trae cuatro tamaños y eso **no es el bug**. En macOS 26
    el icono real vive en `Assets.car` (vía `CFBundleIconName`) — ahí están los diez. El `.icns` es un fallback
    heredado. Verificado renderizando el icono con `NSWorkspace.icon(forFile:)`, que es literalmente lo que
    dibujan Finder y el Dock: correcto, y el sistema le pone su propio margen y sombra.
- **Aviso de versión nueva (`UpdateChecker.swift`).** Al activarse la ventana, como mucho una vez al día,
  Nidus le pregunta a la API pública de GitHub si hay release más reciente y, si la hay, muestra una tira
  discreta en el Greeting Panel con enlace. **No se actualiza solo** — Nidus es un `.app` que moviste tú a
  Aplicaciones, y una app que se reescribe el binario sola es justo lo que este proyecto no hace. No manda
  nada, no identifica a nadie, la × silencia esa versión y el menú contextual apaga la comprobación para
  siempre. Comparación de versiones numérica y por componentes, con tests (4/4): `1.10` es posterior a `1.9`,
  y `1.1.0` no es una versión nueva para quien tiene `1.1`.
- **Atajos en el README.** Faltaban por completo. Documentados contra el código, no de memoria: `⌘E`
  Customize, `F` / `⌘F` buscar, `Espacio` abrir la card bajo el cursor, `Esc`, `⌘N`, `⌘W`, y las quick
  actions por herramienta (`T` tarea, `I` idea, `N` nota) **reasignables por instancia** desde Customize —
  dos copias de la misma herramienta pueden responder a teclas distintas.

*(Nota: quien esté en 1.0 no recibirá aviso de esta versión, porque 1.0 aún no llevaba el comprobador.
Funciona de 1.0.1 en adelante.)*

---

## Fase 12.3 · Borrar en el móvil borra de verdad · Miércoles, 22 de julio de 2026

**Bug real, encontrado usándolo.** Creas una tarea → se sincroniza → la borras en el móvil → abres Nidus y
la tarea aparece igualmente. Borrar solo quitaba la copia local; lo que ya estaba subido seguía en el buzón,
y Nidus hacía su trabajo: archivar lo que hay. El bug no era de Nidus, era que el móvil nunca se retractaba.

- `deleteRecord` ahora deja una **lápida** (`tombstones`, persistida) con el id de lo borrado que ya se había
  subido, y lanza un sync inmediato. Si el registro nunca llegó a subirse no hay nada que retractar.
- `sync()` vacía las lápidas **lo primero**, antes de empujar o recoger nada, y un id solo sale de la lista
  cuando el relay confirma. Así borrar sin cobertura también funciona: la retractación espera y se aplica sola.
- Al desemparejar (o emparejar con otro ordenador) las lápidas se tiran: son ids de otro buzón.
- Verificado con el camino real de código contra un relay simulado: borrar con red (desaparece al instante),
  borrar sin red (queda la lápida, el relay lo conserva) y recuperar red (el siguiente sync lo retracta), y
  en ningún caso acaba en "Already in Nidus" — porque no lo archivó Nidus, lo tiraste tú.

---

## Fase 12.2 · Retoques de la PWA + calendario propio · Miércoles, 22 de julio de 2026

- **Calendario propio (`DeadlinePicker.svelte`)** en vez del `input[type=date]` nativo. El nativo solo sabe
  decir "día", así que usarlo tiraba a la basura dos tercios de la función: en Nidus una fecha límite es una
  fecha **y lo estricta que es**. El scope sale del gesto — toca un día (día), tócalo otra vez (su semana),
  toca el nombre del mes (el mes entero). Semana empezando en lunes, igual que `Calendar.startOfWeek` de la
  app, y las ventanas (semana/mes) se pintan más suaves que una fecha dura porque son otra cosa. Plegado
  por defecto: casi ninguna captura lleva deadline.
- **"Already in Nidus"** con cuerpo: contenedor de cristal, separadores y un punto de acento por línea.
  Siguen siendo 3 y sigue siendo un recibo, no una lista de trabajo.
- **"Sync manually"** pasa a ser el botón protagonista del pie; **"Unpair this phone"** baja a enlace discreto
  debajo, con el rojo pero sin botón grande: desemparejar no compite con sincronizar.
- **Botón "?"** abre una hoja explicando qué es Nidus, qué hace (y qué NO hace) esta webapp, y el aviso de
  iOS: una app instalada tiene almacén propio, así que hay que pegarle el código de emparejamiento una vez.
- **Botón de GitHub** propio al lado, que es quien debe llevar al repo.
- Verificado en navegador: los tres scopes del calendario (día / semana Jul 6–12 / mes), limpiar, y ambos
  temas. Build de la PWA sin avisos.

*(Nota: el auto-sync ya estaba — `pullUp` + `pushDown` al activarse la ventana, `pushDown` en cuanto cambia
la lista de proyectos, y `pullUp` cada 20 min mientras Nidus está abierto.)*

---

## Fase 12.1 · El lenguaje de diseño de Nidus en el móvil · Miércoles, 22 de julio de 2026

La estructura de la PWA estaba bien, pero estéticamente no era Nidus: paneles grises planos, acento naranja
que la app no usa, e iniciales de colores en cuadraditos donde deberían ir los iconos reales. Pasada completa
de lenguaje visual, con la app como única fuente de verdad.

- **Iconos reales de proyecto.** Nidus renderiza cada glifo con `ImageRenderer` (metaball, Bauhaus, iconos
  del bundle, logo importado — todos salen de `ProjectGlyph`, la misma vista que dibuja el escritorio) y lo
  manda como silueta blanca. El teléfono la pinta como **máscara CSS** teñida con `currentColor`, así que una
  sola imagen sirve para claro y oscuro. El móvil no reimplementa nada: no puede desviarse de la app.
  - El *dirty flag* hashea la **identidad** del icono, nunca sus píxeles: un metaball está animado y capturarlo
    daría un hash distinto cada vez (re-push infinito). Para un logo importado la identidad lleva la fecha de
    modificación del fichero, o cambiarlo nunca llegaría al teléfono.
  - Los glifos se renderizan **después** de comprobar el dirty flag: si no hay nada que mandar, no se dibuja nada.
- **Cristal, no paneles grises.** Superficies translúcidas con `backdrop-filter` y borde iluminado sobre el
  gradiente ambiente de `GlassStyle.swift` (mismos stops warm→cool + bloom azul), botones redondos tipo
  `IconButton`, y los círculos de proyecto con el borde tenue y el brillo superior de `SphereView`.
- **Acento azul Nidus** (`#3A5BFF`) en vez del naranja: la app nunca fue naranja.
- **Claro/oscuro** con el toggle luna/sol en la cabecera, oscuro de serie (se captura a una mano, y a menudo
  de noche). Vive en el elemento raíz, así que el fondo de la página cambia con él.
- **Landing** — dos tarjetas *New Inbox* / *New Task* con icono, `+` y descripción, en vez del CTA único.
- **Picker** — anclados como fila de esferas de cristal (igual que el Greeting Panel), recientes como filas
  con *"Last used…"* (se guarda la marca de tiempo por proyecto), y el resto plegado por disciplina.
- **Compose** — campos más altos y con aire, etiquetas en versalitas, `input[type=date]` sin tocar su
  apariencia a propósito: así iOS da la rueda de fecha nativa.
- Verificado en navegador a 402×874 en los dos temas antes de publicar. Build de la PWA sin avisos, 7/7 tests
  del códec de emparejamiento, build macOS verde.

---

## Fase 12 · Captura desde el móvil (pairing + relay + PWA) · Lunes, 13 de julio de 2026

Capturar ideas/tareas en cualquier proyecto desde el teléfono cuando no estás en el ordenador, como con
Raycast pero fuera de casa. Patrón "phone bridge": app de escritorio + PWA instalable + un buzón tonto en
medio. **Sin cuentas, sin backend que mantener, sin datos del vault en la nube.** Builds verdes macOS+iPad;
relay y round-trip completo verificados con simulación (18/18), códec de emparejamiento con tests (7/7) e
interop Swift↔JS comprobada byte a byte.

- **`relay/`** — Cloudflare Worker + KV (`worker.js` pegable en el dashboard + `wrangler.toml` + README con
  el contrato y el setup). Rutas `/channel/:token/down|up`, TTL 7 días, `MAX_PENDING` 50 por pairing,
  `MAX_BODY_BYTES` 512 KB, CORS, validación de token, **dedupe por `id`** (editar en el móvil y re-sincronizar
  REEMPLAZA, no duplica). El relay no sabe qué significa nada de lo que guarda.
- **Swift (`PhoneBridge.swift` + `PhoneBridgePanel.swift`)** — token con `SecRandomCopyBytes`, QR con
  CoreImage (sin dependencias), push `down` (proyectos activos + tags) con dirty-flag SHA256, pull `up` que
  archiva cada captura con `CardStore.append` en el Inbox o el Task Manager del proyecto y **solo entonces**
  borra del relay (round trip de confirmación). Panel con QR, **código de emparejamiento** (imprescindible:
  iOS da a las webapps instaladas su propio almacén, invisible al de Safari) y Advanced con verificación
  write-then-read del relay (una URL que solo devuelve 200 NO es un relay).
- **UI** — botón discreto en el **sidebar** junto al `?`; onboarding de una sola vez en el workspace al
  crear el primer proyecto ("Show me" / "Not now"). Sync automático no bloqueante al activar la app.
- **`mobile/`** — PWA Vite + Svelte 5 + vite-plugin-pwa: lista de proyectos buscable, captura a Inbox o
  Task (título + nota + tags del vault + deadline con scope day/week/month, todo opcional), cola offline,
  bloqueo de navegadores desktop. Deploy por Actions a Pages con `PAGES_BASE=/Nidus/`.
- **Bugs cazados en revisión** (habrían pasado desapercibidos): (1) importar `state` del store hacía que
  Svelte leyera `$state(...)` como *suscripción a store* y **toda la UI habría sido no reactiva** →
  renombrado a `app`; (2) `data.hashValue` como dirty-flag no es estable entre lanzamientos (Swift siembra
  el hasher por proceso) → SHA256; (3) `pushedAt` dentro del payload hasheado hacía que el dirty-flag no
  disparara nunca → se hashea solo la parte estable.
- Con dos dispositivos Nidus (Mac + iPad) **no hay doble importación**: el primero que abre consume y borra;
  el segundo encuentra el buzón vacío.

## Fase 11 · Glaze Library: rename, tablas legibles, botón edit honesto · Lunes, 13 de julio de 2026

Peticiones acumuladas del tool de esmaltes. Builds verdes; JS verificado con node.
- **Renombrado a "Glaze Library"** + `allowsMultiple:false` en el manifest del `.js` (id sigue
  "glaze-recipes" para no romper datos). Actualizada también la copia instalada en el vault del usuario
  (`_tools/glaze-recipe-book.js`), así que no hace falta re-importar; sale "Glaze Library" al recompilar.
- **Tablas mucho más legibles**: `NodeTable` (host, el primitivo `table`) reescrito de "markdown
  espaciado" a **tabla con rejilla real** — borde exterior, separadores de FILA y de COLUMNA, cabecera
  destacada, 1ª col a la izquierda / resto a la derecha. Beneficia a cualquier tool que use `table`.
- **`card()` del glaze reestructurado**: en vez de un bloque markdown, ahora **secciones bordeadas** —
  "Recipe" (tabla base→100), "Additives (% of base)" en su propia zona, y **"Notes" en su propia card**.
  Cada zona con su borde, todo legible. `recipeSections()` sustituye a `recipeMarkdown()` (eliminada).
- **Botón "OK" del editor de card, honesto**: el check de arriba salía del modo edición SIN guardar
  (Save está abajo) y se sentía engañoso. Ahora, en edición, es un botón explícito **"Leave editing"** con
  subtexto **"doesn't save"** (`InstalledToolCardPanel`). La X sigue cerrando todo; Save (abajo) guarda.

## Fase 11 · Anclado en greeting + pill sobre el calendario · Lunes, 13 de julio de 2026

Micro-ajustes. Builds verdes.
- **Greeting**: los proyectos anclados se marcan con un **pin pequeño de acento al final del nombre**
  (`SphereView.pinned` → pin.fill inline en el `Text` del label). (Antes se probó un punto encima del icono
  → descartado por el usuario, "queda mal ubicado".)
- **Pill "Project Blueprint" reubicado**: de flotar sobre el identity card pasa a flotar sobre la **esquina
  superior derecha del calendario** (`overviewCard.overlay(topTrailing)`, `offset y:-34`), a la derecha del
  header. Extraído a `blueprintPillOverlay`. Ubicación **confirmada OK por el usuario**.
- **Fix contraste del pill en modo claro**: naranja-sobre-tinte-0.15 se lavaba en claro (invisible). Ahora
  theme-aware (`ThemeController`, fiable sobre el blur del escritorio): oscuro igual (tinte sutil + texto
  acento); claro = relleno de acento sólido + texto blanco. El dot de contenido sigue el foreground.

## Fase 11 · Blueprint pill fuera del card + rename a "Project Blueprint" · Domingo, 12 de julio de 2026

El pill de blueprint apretaba la descripción del proyecto. Builds verdes.
- **Pill flotando FUERA del card**: el pill (antes dentro, arriba-dcha) ahora flota **por encima** del card,
  justo sobre "Open Project Folder" (`.overlay(topTrailing).offset(y:-34)`), fuera del contenido → la
  descripción recupera todo el ancho. Se subió el `padding(.top)` del workspace 30→44 para darle sitio.
  Estilo con más presencia (peso semibold, borde de acento). Oculto en Customize Mode.
- **Renombrado a "Project Blueprint"** (elegido por el usuario entre Project Blueprint / North Star /
  The Objective / Blueprint). El título del panel también pasa a "Project Blueprint" para coherencia.
  `BlueprintPill` gana `label` configurable.

## Fase 11 · Teclas del sidebar + carpeta sigue al nombre · Domingo, 12 de julio de 2026

Dos correcciones rápidas. Builds verdes; renombrado verificado con script.
- **Teclas de la búsqueda del sidebar se filtraban al workspace**: la barra de búsqueda que añadí no marca
  `model.isEditingText`, así que teclear disparaba hotkeys de tools / quick-add (las quick actions "saltaban").
  Fix: `handleKey` ahora ignora teclas cuando `sidebarOpen` (guard `!sidebarOpen`).
- **Renombrar un proyecto no renombraba su carpeta real**: `updateProject` solo movía la carpeta al cambiar
  de disciplina, no al cambiar el nombre. Ahora, si el nombre cambia (misma disciplina), renombra la carpeta
  del vault al slug del nuevo nombre (único contra hermanos Y disco). Así un fork renombrado deja de leer
  "…-forked-3". Migra el `_owner` de las entradas de la librería interproyectos a la nueva ruta
  (`migrateLibraryOwner`) para no romper la propiedad del banco. Editar sin cambiar el nombre no toca la carpeta.

## Fase 11 · Delete deja huérfanas (fix raíz) + Current Forks + layout card · Domingo, 12 de julio de 2026

Tres cosas tras la 2ª ronda de pruebas. Builds verdes macOS+iPad.
- **[BUG serio] Borrar un proyecto dejaba la carpeta en el vault.** Diagnosticado inspeccionando el vault
  real: `removeItem` SÍ borraba la carpeta, pero las tools **Reference Board y Notebook la recreaban** —
  llamaban a `ensure()` (crea carpeta + marker) en cada `reload()`/`load()`, y al borrar el proyecto el
  `notifyFileChange` disparaba un reload de las tools aún montadas → recreaban `Nidus References/` y
  `Notebook/` en la ruta ya borrada (huérfana con solo los markers, sin datos). **Fix de raíz: una tool ya
  no crea su carpeta solo por leerla** — `ReferenceBoardTool.reload()` deja de llamar `ensure()`
  (`reconcile` tolera carpeta ausente); `NotebookStore.load()` comprueba existencia sin crear. La carpeta
  se crea perezosamente al primer guardado (paste/import/nueva nota, que ya llaman `ensure`). Efecto extra:
  un proyecto nuevo no tiene esas carpetas hasta que las usas (vault más limpio).
- **Current Forks (nuevo)**: un proyecto con forks muestra una pill reservada **"Forks · N"** (menú
  desplegable) en la zona de quick actions, para saltar a cualquiera de sus forks (estilo GitHub).
  `NidusModel.forks(of:)`; `ProjectQuickActions` gana `forks`/`onOpenFork`. Forked-Original y Forks pueden
  coexistir (cada una ocupa un slot; deja 1–2 de usuario).
- **Layout del identity card**: el "Current Direction" (Blueprint pill) se solapaba con nombres largos.
  Ahora la pill va **debajo** del botón de carpeta (renombrado **"Open Project Folder"**), el nombre solo
  tiene que despejar el botón de carpeta (o nada si no hay carpeta vinculada), **límite de 25 caracteres**
  al nombre del proyecto, y la card crece 180→190pt.

## Fase 11 · Fixes de fork + greeting anclados-primero · Domingo, 12 de julio de 2026

Reportados por el usuario tras probar la Fase 11. Builds verdes; lógica de fork verificada con script Swift.
- **Bug 1 (fork bloqueado tras borrar un fork, persistente entre reinicios)**: `forkProject` elegía el
  slug de carpeta comprobando solo `nidus.json`, no el disco. Una carpeta HUÉRFANA (de un delete cuyo
  `removeItem` falló en silencio con `try?`) hacía que `copyItem` lanzara y el fork devolviera nil para
  siempre. Fix: la unicidad de carpeta ahora comprueba config **y disco** (salta huérfanas → "-2"). Además
  `deleteProjectPermanently` ya no traga el error del borrado de carpeta (lo pone en `lastError`).
- **Bug 2 (dos forks con nombre idéntico)**: el nombre del fork era siempre "<X> (Forked)". Ahora es único
  dentro de la disciplina: "<X> (Forked)", luego "<X> (Forked) 2", "3"… (las carpetas ya eran únicas).
- **Greeting anclados-primero**: los 3 huecos de "Recent projects" muestran los **anclados** primero (si
  los hay) y rellenan con los más recientes (`NidusModel.openingProjects`). Antes solo recientes.
- Confirmado: borrar un proyecto (deprecated → Delete permanently) elimina su carpeta de `NidusVault` de
  forma definitiva; es la única acción realmente destructiva.

## Fase 11 · Gestión de proyectos: status, anclados, fork, buscador · Domingo, 12 de julio de 2026

La tirada de gestión de proyectos que faltaba, ahora que el core está maduro. Todo son **tags internos en
`nidus.json`** (no subcarpetas — evita multiplicar carpetas de disciplina por status). Decisiones cerradas
con el usuario vía AskUserQuestion. Builds verdes macOS+iPad.

**Modelo (`NidusConfig.swift` + nuevo `ProjectStatus.swift`)**: `Project.status`
(`active`(nil)/`completed`/`archived`/`deprecated`), `Project.forkedFrom` (`{discipline_id, project_id}`),
`NidusConfig.pinnedProjects` (`[String]` ordenado, máx 3, global). Decodificación tolerante (vaults viejos
sin las claves → defaults). `ProjectStatus` enum con label/hint/icon/color (dot como Event Log).

**Métodos (`NidusModel.swift`)**: `setStatus` (unpinnea si pasa a no-activo), `isPinned`/`setPinned`/
`togglePin` (rechaza el 4º pin), `pinnedHits`, `forkProject` (copia la carpeta ENTERA del proyecto +
entrada de config → "<nombre> (Forked)", `forkedFrom` al original; NO copia el banco `_library`),
`deleteProjectPermanently` (guardado a `deprecated`; borra carpeta + entrada; **el banco `_library` NO se
toca** → una entrada aportada sobrevive al proyecto, queda sin dueño pero importable).

**1. Anclados** — sección "PINNED" arriba del sidebar (global, máx 3); pin/unpin con un icono al hacer
hover en la fila (o en la fila ya anclada). Los anclados se sacan de su lista de disciplina para no duplicar.

**2. Status** — cluster flotante a la derecha del identity card SOLO en Customize Mode
(`ProjectStatusControls`): pill de status (popover con los 4 estados + hint + dot) → `setStatus`. Debajo,
**Fork**. Y solo si `deprecated`, debajo **Delete permanently** con doble confirmación.

**3. Fork** — botón en el cluster → duplica el proyecto y cambia la ventana al fork (sale de Customize).
Una de las 3 quick actions queda reservada como pill **"Forked Original"** (icono rama) que abre el original
(`ProjectQuickActions` gana `forkedOriginal`/`onOpenOriginal`; deja 2 slots de usuario).

**4. Sidebar reescrito (`SidebarView.swift`)**: buscador arriba (bajo NIDUS) que busca por nombre de
proyecto Y de disciplina en TODOS los estados (reusa `searchProjects`), resultados con dot de color de
status. La lista de trabajo muestra solo **activos** (+ anclados arriba). Un colapsable abajo abre la vista
**ARCHIVE** (completed/archived/deprecated, agrupados por disciplina, con dots) que sustituye la lista y es
persistente hasta pulsar "Back to active".

## Fase 10 · Botón Tools → marketplace real · Domingo, 12 de julio de 2026

El marketplace de tools ya existe y está en desarrollo activo: **https://paramostudio.github.io/nidus-tools/**.
`WorkspaceView.swift`: `toolsURL` pasa del placeholder (repo de GitHub) a la URL real del marketplace;
help del botón actualizado ("Browse the Nidus tools marketplace", antes "Search tools (GitHub)"). El
botón de abajo (`aboutURL`, rama/GitHub) sigue apuntando al repo, sin cambios. Build verde macOS+iPad.

## Fase 10 · Carpeta `Skills/` en el repo + skill de micro-tools nueva · Domingo, 12 de julio de 2026

Documentación, sin cambios de app. El usuario no encontraba la skill de Blueprint porque solo existía en
`~/.claude/skills/` (fuera del repo). Resuelto:
- **`~/.claude/skills/nidus-microtool-maker/SKILL.md` (NUEVA)**: nunca había existido como skill
  invocable — solo como doc de referencia (`NIDUS-microtool-authoring.md`). Ahora tiene su propio
  SKILL.md con frontmatter, condensado (contrato del objeto `tool`, tipos de input, `render`, subset de
  Markdown, iconos, self-check, un ejemplo) que remite al doc completo para el resto de ejemplos.
- **`Skills/` en la raíz del repo** (`NIDUS-SKILL-tool.md`, `NIDUS-SKILL-microtool.md`,
  `NIDUS-SKILL-blueprint.md` + `README.md`): copias de las tres skills, para que vivan en el repo y sean
  fáciles de encontrar/entregar a cualquier IA directamente. Son copias de las de `~/.claude/skills/`
  (esas son las que Claude Code invoca de verdad); si se pulen, mantener ambas en sync.

## Fase 10 · Fix botón glass "pegado" + brief marketplace · Miércoles, 8 de julio de 2026

- **Fix definitivo del botón que se quedaba con el highlight pegado** (`IconButton`, la columna
  rightControls). Diagnóstico real (no parche): los botones que funcionan (tema, customize) MUTAN estado
  observado al pulsar → re-render → el glass se limpia. Los dos botones que abren URL (wrench + branch,
  ambos al repo) NO mutan nada → sin re-render tras el clic, y abrir el navegador quita el foco a la app,
  dejando el highlight interactivo de Liquid Glass pegado hasta el siguiente hover. No era específico del
  de abajo. Fix: `.rebuildOnFocusChange()` — en macOS reconstruye el botón cuando cambia
  `controlActiveState` (foco de ventana), limpiando el highlight igual que los stateful lo limpian gratis;
  no-op en iOS. Builds verdes macOS+iPad.
- **`NIDUS-marketplace-brief.md` ampliado** (doc, no código): (1) **exactamente 2 screenshots** por tool
  (tile colapsado + expandido, regla dura), (2) campo **`why`** de intencionalidad ("para qué / por qué lo
  hice") mostrado como zona "What it's for", (3) sección de **estética de Nidus** (calma, liquid glass,
  navy oscuro tintado, tipografía sobria caps-tracked, un solo acento azul, metaball orgánico) para
  trasladarla a la web.

## Fase 10 · 2ª pasada: flash de ventana, cadencia 1.5s, Blueprint flyer, skill+marketplace · Miércoles, 8 de julio de 2026

Segunda tanda de pulido tras probar la anterior. Builds verdes macOS+iPad.
- **Fix flash de ventana nueva** ("resolver antes de mostrar"): al crear una ventana (⌘N o al abrir la
  app), macOS la pintaba un frame a tamaño grande antes de que `WindowConfigurator` la encogiera — flash
  feo del Greeting expandido. Ahora la ventana nace con `alphaValue = 0` (oculta en cuanto se puede
  tocar), se dimensiona+centra, y se **revela con un fade de 0.22s** en el siguiente runloop, ya resuelta.
  `Coordinator.didReveal` (one-time). Cubre también el arranque de la app.
- **Cadencia entre proyectos a ~1.5s** (era 0.7): fade más largo y deliberado, "entrar a otro espacio".
- **Blueprint — vista de lectura estilo "flyer"**: rediseñada a algo centrado y estético en vez de un
  formulario. Cabecera "YOUR CURRENT DIRECTION" + una línea recordando qué es ("what this project is
  working toward, right now"). Cada campo = **LABEL centrado · separador corto · card con el valor
  centrado**. Todo centrado, el card crece a lo que necesite. La edición no se toca.
- **Skill `nidus-blueprint-maker`** (nueva, en `~/.claude/skills/`): cómo hacer un template de Blueprint
  (`# Título`, `## Campo` por línea, `<!-- icon: SFSymbol -->`), lista curada de SF Symbols por
  disciplina, guía de diseño (6–9 campos, ordenar de objetivo→incógnitas), ejemplo completo.
- **Marketplace**: `NIDUS-marketplace-brief.md` en la raíz del repo — prompt maestro autocontenido para
  construir el marketplace (GitHub Pages estático, estilo Übersicht simplificado, submission por PR con
  `tool.js`+`tool.json`, index generado por Action, sin backend) en otro chat.

## Fase 10 · Pulido de madurez: ventanas, cadencia, cards limpias, Blueprint · Miércoles, 8 de julio de 2026

Ronda de correcciones pequeñas con la app ya madura. Builds verdes macOS+iPad; stripper y parseos verificados con scripts standalone.
- **⌘N abre VENTANA, no pestaña**: `NSWindow.allowsAutomaticWindowTabbing = false` en `NidusApp.init`.
  Antes, con la ventana maximizada, macOS fusionaba la nueva como pestaña y encogía la existente. Ahora
  cada proyecto es una ventana independiente y redimensionable — varios proyectos abiertos a la vez sin
  arrastrarse. (Es el comportamiento que ya pretendía el comentario del código.)
- **Cadencia más calmada entre proyectos**: el cross-fade de `RootWindowView` pasa de 0.4s a **0.7s** —
  saltar de proyecto se siente como "entrar a otro espacio", un beat deliberado (intencional, parte del
  tono de toda la app).
- **Cards nativas sin ruido Markdown**: nuevo `MarkdownParser.plainPreview()` aplana el body a prosa sin
  símbolos (quita `#`, pipes de tabla, `**`/`_`/`` ` ``, viñetas, `>`, sintaxis de links/imágenes, tags
  HTML) para el preview de `CardFace`. El modo view/edit de la nota completa no cambia; solo el snippet
  compacto se lee limpio. Verificado con los ejemplos reales de las capturas.
- **Blueprint — vista de lectura en columna única**: los campos dejan de ir en rejilla 2-col
  (izq/dcha, se sentían "pequeños") y pasan a **una columna full-width de arriba abajo**, cada campo con
  más presencia (valor en `callout`, más padding). La EDICIÓN no se toca (funciona perfecta).
- **Blueprint — panel con altura adaptativa** (misma regla "size to content"): el card crece para caber
  el blueprint en vez de scrollear en una caja fija.
- **Blueprint — icono de templates importados**: un `.md` de template puede declarar su SF Symbol con
  `<!-- icon: flask -->` (cualquier línea) → su tile del picker combina con las built-in; si no lo
  declara, un default neutro (`square.grid.2x2`) en vez del genérico `doc.text`.
- **PENDIENTE (futuro, no ahora)**: el botón "Tools" (arriba-dcha del workspace) apunta al repo de
  GitHub; debería llevar a un MARKETPLACE de tools (página servida en GitHub Pages, estilo Übersicht
  simplificado) que el usuario aún no ha creado. Cuando exista, cambiar `WorkspaceView.toolsURL`.
- **Nota**: la extensión de Raycast YA ESTÁ HECHA por el usuario y funcionando (quick-capture +
  manage-aliases). El sidecar `vault-path.txt` cumplió su función. Ver `Raycast/nidus/`.

## Fase 9 · Tools instaladas: paneles con altura adaptativa (sin scroll) · Miércoles, 8 de julio de 2026

Regla general nueva (a petición del usuario, viendo el glaze tool cortado con scroll): **un panel debe
ocupar el espacio que necesita para no forzar scroll, hasta el límite de la ventana.** Builds verdes.
- `InstalledToolExpandedView` y `InstalledToolCardPanel` dejan de tener altura FIJA (900×640 / 640×620)
  y pasan a **altura adaptativa**: miden el alto natural del árbol renderizado con un measurer oculto
  (`NodeView(...).fixedSize(vertical).onGeometryChange`), y fijan la altura del panel a
  `min(contenido + chrome, ventana − margen)`. Ancho también capado a la ventana. Si el contenido supera
  la ventana, `TidyScroll` sigue haciendo scroll (único caso en que aparece). Centrado en `GeometryReader`.
- Skill `nidus-toolmaker` + spec documentan la regla "size to content, don't design for a scroll" para
  que cualquier IA/persona que haga tools no maquete pensando en una altura corta fija.

## Fase 9 · Reference Board: Quick Look + instancias múltiples · Miércoles, 8 de julio de 2026

Dos peticiones del usuario tras usar la tool en serio. Builds verdes macOS+iPad.
- **Quick Look (ver en grande dentro de la app)**: en el visor grande, con el cursor sobre una imagen,
  **Espacio** la amplía a tamaño completo sobre un scrim oscuro; Espacio de nuevo (o clic, o Escape) la
  cierra. Carga el fichero completo (no el thumbnail) para ver detalle. `QuickLookOverlay` +
  `MasonryScroll.onHoverItem` reporta la imagen bajo el cursor + `.onKeyPress(.space)` en el visor.
  Escape cierra primero el Quick Look y solo después el visor.
- **Instancias múltiples de Reference Board** (antes `allowsMultiple:false`): ahora duplicable. La
  carpeta de almacenamiento se declara como el "file" de instancia (`files:[ReferenceStore.folderName]`,
  un token SIN extensión) → `resolveInstance` la sufija por instancia ("Nidus References",
  "Nidus References-2", …); la primera instancia mantiene la carpeta original (files nil) → **boards
  existentes intactos**. `folder` se resuelve vía `context.fileURL(...)`; density/sort ya iban por
  `slotID`. Para que la maquinaria genérica de `.md` no cree un fichero de texto con el nombre de la
  carpeta, `MarkdownStore.ensureToolFile`/`renameHeader`/`markDeprecated` ahora **ignoran tokens sin
  extensión** (invariante: MarkdownStore solo gestiona ficheros con extensión). Borrar un board deja sus
  imágenes en disco (no destructivo, coherente con detach).

## Fase 9 · Sidecar de ruta del vault (para herramientas externas) · Miércoles, 8 de julio de 2026

Preparación para la extensión de Raycast (que se construye en otro codebase/IA, ver
`Raycast/nidus/HANDOFF.md`). El vault se localiza en la app vía un security-scoped bookmark opaco en
`UserDefaults` — indecodificable desde un proceso externo (Node/Raycast). `VaultStore.swift` ahora
escribe también una copia en **texto plano** de la ruta absoluta del vault cada vez que se resuelve
(crear/abrir/restaurar), en `~/Library/Application Support/Nidus/vault-path.txt` — no es un secreto,
solo una ruta, así que cualquier herramienta externa que corra como el mismo usuario puede leerla con un
simple `fs.readFileSync`, sin tocar el bookmark. Build verde macOS+iPad.

## Fase 9 · Fix: nota de Reference Board ilegible en modo oscuro · Miércoles, 8 de julio de 2026

`ReferenceBoardTool.swift` (`BoardThumb`): el scrim + texto de la nota "why is it here?" era blanco con
texto negro siempre — legible en modo claro, invisible en oscuro (blanco sobre blanco). Ahora
`colorScheme`-aware: `noteScrimColor`/`noteTextColor` invierten a scrim oscuro + texto blanco en dark
mode. Build verde macOS+iPad.

## Fase 9 · Blueprint: direccionalidad clara en Revert/Return · Miércoles, 8 de julio de 2026

El usuario notó que "Revert to previous" era el MISMO botón yendo en ambas direcciones: v2→v1 se sentía
bien ("volver atrás"), pero pulsarlo otra vez volvía a v2 sin avisar — confuso, le quitaba peso al estado
actual. El número en sí YA era correcto (cada snapshot conserva su propio número fijo); el problema era
solo de UI/etiqueta. Builds verdes; lógica de swap verificada con script Swift standalone (3 swaps
consecutivos alternan correctamente v2→v1→v2→v1, `swapGoesForward` cambia de signo cada vez).
- **`Blueprint.swift`**: `revertToPrevious()` → **`swapWithPrevious()`** + nuevo **`swapGoesForward: Bool`**
  (`previous.version > version`). El swap en sí no cambia (sigue intercambiando `current`↔`previous` sin
  renumerar nada — cada snapshot ya tenía su número fijo, correcto desde el principio).
- **`BlueprintViews.swift`**: el botón único se separa en dos según dirección: **"Revert to v‹N›"** (hacia
  un número menor) sin confirmación — sigue siendo instantáneo y no destructivo, tal como al usuario le
  gustaba. **"Return to v‹N› (current)"** (hacia un número mayor) ahora exige **`.confirmationDialog`**
  ("¿Volver a v‹N›? Se convierte otra vez en la versión activa") — le da el peso de seriedad que pidió a
  la acción de abandonar deliberadamente la versión a la que habías vuelto.
- Log de actividad diferencia "Reverted to v‹N›" vs "Returned to v‹N›" según la dirección real del swap.

## Fase 9 · Blueprint: pulido tras primera prueba · Miércoles, 8 de julio de 2026

5 correcciones sobre el primer build de Blueprint. Builds verdes macOS+iPad; parser de plantillas `.md`
verificado con un script Swift standalone (nombre/id/labels correctos; sin `#` usa el nombre de fichero;
sin `##` devuelve nil).
- **#1 Pill fijo**: ya no muestra el nombre de la plantilla — siempre dice **"Current Direction"** (icono
  `scope` + un punto relleno si hay contenido), para que se identifique como control, no como dato.
- **#2 Plantillas importables**: formato **`.md` con `# Nombre` + un `## Campo` por línea**
  (`BlueprintTemplate.parse`). Se copian a `_templates/blueprint/` en la raíz del vault (reusable entre
  proyectos, mismo patrón que `_library/`). Botón "Import a template…" en el picker (**solo macOS**:
  `.fileImporter` no dispara de forma fiable dentro de `WorkspaceOverlay`'s `AnyView` — mismo problema ya
  documentado para micro-tools en `CardViews.swift`; se usa `NSOpenPanel` en su lugar).
- **#3 Compacto, sin scroll**: layout a **grid de 2 columnas** (lectura Y edición) en vez de una columna
  larga; paddings/spacing reducidos a la mitad; panel 620×460 (antes 560×600). Tope de **140 caracteres
  por campo** (`BlueprintField.maxLength`, truncado en vivo) — es un ancla mental, no un documento.
- **#4 Anular campos**: `BlueprintField` gana `included: Bool` (default true, decodificación tolerante
  para blueprints ya guardados). En edición, un checkbox por campo lo anula sin borrar lo escrito; la
  lectura filtra por `included && !empty`, así un campo que no interesa desaparece de la vista sin perder
  el texto si se reactiva luego.
- **#5 Empezar de cero**: botón destructivo "Start over…" en el formulario de edición con **doble
  confirmación** (arma el estado → "Yes, delete it" / Cancel) → `BlueprintStore.delete()` borra
  `blueprint.json` y vuelve al picker de plantillas dentro del mismo panel.

## Fase 9 · "Current Blueprint" — punto focal anclado al proyecto · Miércoles, 8 de julio de 2026

Feature nativa nueva (no un tool del grid): un pill anclado en la esquina de `identityCard` que responde
"dado todo lo que sabemos, ¿qué estamos haciendo realmente?". Builds verdes macOS+iPad.
- **`Blueprint.swift`**: modelo `Blueprint` (template/campos ordenados/versión/`approvedAt`/`previous`
  snapshot/`activity` trail) + `BlueprintTemplate.builtIns` (4 plantillas: Ceramic Product, Software,
  Research, Exhibition, cada una con sus campos propios) + `BlueprintStore` (lee/escribe
  `<project>/blueprint.json`, fuera de `ProjectLayout` — no es un tool del grid).
- **Versionado self-contained** (decisión del usuario): NO es un historial completo navegable — cada
  `logUpdate` guarda solo UN paso atrás (`previous`) y añade una línea a `activity` ("Blueprint updated").
  `revertToPrevious()` intercambia actual↔previous simétricamente (deshacer Y rehacer). El primer
  relleno tras elegir plantilla NO cuenta como "update" (no salta a v2 de la nada).
- **`BlueprintViews.swift`**: `BlueprintPill` (icono+nombre de plantilla, o "+Blueprint" si no hay una) +
  `BlueprintPanel` (picker de plantilla → lectura bonita compartimentada por campo → lápiz→edición →
  "Save & Log Update"; "Revert to previous version" cuando hay `previous`; mini trail de actividad).
  Reutiliza `NotebookCircleButton`/`glassCard()`/`TidyScroll`/`overlay.present` (mismos patrones que
  las tools instaladas).
- **`WorkspaceView.swift`**: el pill vive en el MISMO sitio que el lápiz de "editar proyecto" — Customize
  Mode y el Blueprint son mutuamente excluyentes en esa esquina (uno u otro, nunca ambos). `identityCard`
  reserva algo más de espacio a la derecha del título (150→180pt) porque el pill es más ancho que los
  iconos que reemplaza.
- Plantillas de v1 son fijas (hardcoded); autoría de plantillas propias/reusables queda como paso natural
  futuro (mismo patrón que el banco `_library/` si hiciera falta cross-proyecto).

## Fase 9 · Biblioteca cross-proyecto (banco opcional por tool) · Miércoles, 8 de julio de 2026

El "gran build" que resultó pequeño: una carpeta + una API + un toggle. Builds verdes macOS+iPad; jerarquía completa verificada headless. NO es resource-intensive: son ficheros `.md` copiados a una carpeta.
- **Almacén**: `_library/<toolid>/` en la raíz del vault (hermano de `_tools/`): `library.md` (formato CardStore)
  + `_assets/` para fotos. Nuevo `InstalledToolLibrary.swift` (`ToolLibraryStore`) hace todo el IO.
- **API host `nidus.library`** (opcional; el tool hace feature-detect `if (ctx.nidus.library)`):
  `save(cardId)` / `remove(cardId)` / `contains(cardId)` / `all()` → `[{…, ownedHere}]` / `importHere(entryId)`.
  `Run` gana `vaultURL`; el dueño = clave del proyecto (carpeta relativa al vault) guardada en `extra._owner`.
- **Jerarquía = una sola fuente de verdad**: el proyecto que guardó algo es el dueño y puede quitarlo; los
  demás solo `importHere` → copia independiente (id nuevo, sus propios assets), nunca tocan el original.
- **Fotos cross-proyecto**: al guardar, los assets se copian al banco con ruta ABSOLUTA; nuevo helper
  `resolveImage()` en el renderer carga rutas absolutas (banco) o relativas (`_assets/`). Al importar, se
  copian al `_assets/` del proyecto destino con id nuevo. `button` gana `with` (payload, p.ej. el card id).
- **Ejemplo glaze v1.7**: toggle "Save to library / ✓ In library — remove" en la lectura del esmalte + sección
  "My glaze library (all projects)" en el expandido con Import (y Remove solo en `ownedHere`). Skill + spec
  documentan la API como capacidad OPCIONAL y el patrón de jerarquía.
- Nativas (ideas/inbox/tasks/event log/reference board): NO aplican (contextuales de campo). Notebook podría
  beneficiarse en el futuro (toggle "crossover" dentro de la nota) — se evaluará si el concepto cuaja en glaze.

## Fase 9 · Drag por zonas + no-destrucción real (write) · Miércoles, 8 de julio de 2026

Dos problemas de la 2ª ronda de pruebas glaze. Builds verdes macOS+iPad; no-destrucción verificada headless con el repro exacto del usuario.
- **Drag recategorizar reescrito (host)**: `.dropDestination` era poco fiable dentro del overlay scrolleable
  (soltar no transportaba). `NodeCardGrid` pasa a **drag manual**: `DragGesture` en un coordinate-space local
  (`cardGrid`) + hit-test contra los frames de cada zona (reportados por `CardGridFrameKey`). TODA la zona con
  borde (cabecera + grid) es destino; realce al pasar por encima; preview que sigue al cursor; el tile de origen
  se atenúa; nunca filtra a tools de fondo. Es el mismo enfoque manual que ya funcionaba en el `cardList`.
- **No-destrucción REAL (bug del usuario)**: importar una card no era destructivo, pero **usarla sí** —
  `save`/`add`/`recategorize` regeneraban el `body` con la plantilla del glaze y BORRABAN lo que no era suyo
  (p.ej. un triaxial añadido en Ideas). Principio corregido y ahora documentado como regla general en la skill:
  **una tool guarda TODO en `card.extra` + título + fotos y NUNCA escribe `body`.** `nidus.cards.update` solo
  pisa las claves que le pasas → omitir `body` preserva el contenido ajeno. La vista se renderiza desde `extra`
  (helper `recipeMarkdown`), no desde el body. Ejemplo glaze **v1.6**. Verificado: editar+guardar y recategorizar
  conservan el triaxial intacto.
- **Skill**: regla de no-destrucción (write + display) como sección load-bearing; nota de que todo lo hecho es
  autorable en un solo `.js` autocontenido, on-par con las built-in.

## Fase 9 · Pulido tools instalables: 4 fixes de la ronda de pruebas glaze · Miércoles, 8 de julio de 2026

Cuatro correcciones tras probar el ejemplo glaze v1.4. Builds verdes macOS+iPad; edit/foreign verificados headless.
- **#1 Tile más compacto**: `NodeCardList` reescrito a filas limpias (miniatura + nombre + subtítulo de un
  campo `extra` (`subtitle`) + fecha relativa), SIN volcar el `.md` crudo. El ejemplo usa `subtitle:"surface"`.
- **#2 Tabla legible**: `MarkdownTable` pasa a `Grid` con separación (spacing 20/9) y divisores tenues
  entre filas. Estado/superficie/cono ya NO van en el body: se muestran como **pills** (badges) en `card()`.
- **#2.2 Fix drag recategorizar**: el drop del `cardGrid` no transportaba. Área de drop mayor (minHeight 76,
  `contentShape`) + realce al pasar por encima (`isTargeted`) + `dropDestination` devuelve false si no procede.
- **#3 (crítico) Editar ya no sale en blanco**: `render()` pasaba la card SOLO a `card`, no a `edit` → el
  form se abría vacío y desvinculado. Ahora pasa la card a cualquier render con scope de card; el `edit()`
  se pre-rellena (nombre, cono, estado, superficie, tablas base/aditivos, notas, fotos) y guarda con `with:{id}`.
- **#4 Cards importadas no-destructivas**: una card ajena (de Inbox/Ideas/Tasks) que cae en la tool ya no
  vuelca su contenido incompatible. La tool detecta si es suya (`isGlaze`: tiene sus propios campos) y, si no,
  muestra solo título + fotos + una pista para convertirla. Patrón recomendado para cualquier tool en el skill.
- **Ejemplo glaze v1.5**: incorpora todo lo anterior.

## Fase 9 · Tools instalables Notebook-quality: grid, read/edit, fotos, fix drag · Martes, 7 de julio de 2026

Gran ronda para que las tools instaladas lleguen a nivel Notebook. Builds verdes macOS+iPad.
- **Fix bug drag-leak**: arrastrar dentro de un overlay (card/expandido) ya NO apunta a tools de fondo
  (`CardDragController.overlayActive`, seteado por `WorkspaceView` según `overlay.content`).
- **Tile abre como Notebook**: footer "Open …" ANCLADO (no scrollea) + clic en el header del tile
  también abre el expandido. `manifest.openLabel`; `ToolTileView.onTitleTap` generalizado a instaladas.
- **Read-then-edit**: `InstalledToolCardPanel` muestra `card()` (lectura) con lápiz que conmuta a
  `edit()` (form pre-rellenado); guardar vuelve a lectura. Nueva render fn `edit()`.
- **Fotos**: input `photos` (pegar/importar → `_assets/`), nodo `gallery`, `nidus.cards.update` acepta
  `images`. `NodePhotoInput` (paste + NSOpenPanel + thumbnails).
- **Primitivo `cardGrid`**: tiles con foto agrupados por categoría (`groupBy`) + badge (`badge`);
  **arrastrar un tile a otro grupo → handler `onMove{id,group}`** (recategoriza), scoped al grid (no
  filtra). `.draggable`/`.dropDestination`.
- **Ejemplo glaze v1.4**: expandido con `cardGrid` (Tested/To try/Rejected/Unsorted, drag entre ellos),
  `card()` lectura (galería+receta) / `edit()` form (con fotos), footer host, recategorize regenera la
  cabecera. Verificado headless.
- **PENDIENTE (último gran build)**: LIBRERÍA GENERAL cross-proyecto — `nidus.library` API + `_libraries/
  <toolid>.md` en raíz del vault + toggle "Save to library" en tested + buscar/importar a otro proyecto.

## Fase 9 · Tools instalables: drops bidireccionales + editar con su form · Martes, 7 de julio de 2026

- **Card sharing bidireccional**: una tool `shareable:true` ahora es DROP TARGET — soltar una card
  encima la mueve a su almacén (mismo mecanismo `ToolFramePreferenceKey`/`CardDropHighlight` que las
  nativas), y sus cards se pueden arrastrar fuera (ya iba). Los silos (`shareable:false`) no aceptan.
- **Editar con el formulario propio** (no el editor de notas): `NodeForm` gana `initial` (pre-rellenar
  escalares + tablas) y `with` (payload estático, p.ej. el id de la card). Así una tool define `card()`
  = el MISMO form pre-rellenado desde `card.extra`, con `submit:"save"` + `with:{id}`, y el handler hace
  `nidus.cards.update(id, …)`.
- **Ejemplo v1.3**: `shareable:true`; datos estructurados en `extra` (JSON) para round-trip; `card()` =
  form de edición pre-rellenado (pickers + tablas de materiales); botón del tile → **"Open Glaze
  Library"** (abre el navegador); "New glaze" vive en el expandido. Verificado headless (crear→abrir
  pre-rellenado→guardar por id; base 30/45/30→28.57/42.86/28.57).
- **PENDIENTE**: botón "Add to library" en los tested + la LIBRERÍA GENERAL cross-proyecto (guardar/
  buscar/importar) — subsistema propio, siguiente gran build. Fotos dentro del form de creación.

## Fase 9 · Tools instalables: cards nativas + card editable con fotos + normalización · Martes, 7 de julio de 2026

Tras feedback: las cards del tile no se veían como las tradicionales, no se podían editar ni pegar
fotos, y la receta no se normalizaba. Arreglado:
- **`cardList` ahora renderiza el `CardRow` NATIVO real** (mismo look/arrastre/menú "…" que Inbox/
  Ideas) — se acabó la fila custom fea con "## Recipe" de subtítulo.
- **Abrir una card de tool instalada → `CardDetailView` nativo por defecto** (editable, **pegar fotos**,
  notas Markdown, links) — salvo que la tool defina `card()` (que queda como vista de solo-lectura
  opcional). Así se puede editar y añadir fotos a un esmalte ya creado.
- **Ejemplo `glaze-recipe-book.js` v1.2**: SIN `card()` (usa detalle nativo); form con tabla de **base**
  (normaliza a 100) + tabla de **aditivos** (% sin normalizar) → receta pulida como el Recipe
  Normalizer; línea de cabecera en negrita `**Tested · Matte · Cone 8/9**` en el body + status en extra
  para agrupar. Verificado headless (30/45/30→28.57/42.86/28.57, aditivo 8%, total 108).
- Skill actualizada: cardList=filas nativas, preferir OMITIR `card()` para detalle editable con fotos,
  poner contenido estructurado (tabla receta, cabecera) en el BODY Markdown, y computar (normalizar) en
  el handler.
- **PENDIENTE (dimensión futura reiterada por el usuario)**: librería GENERAL cross-proyecto — al pulsar
  cualquier zona de la tool (no card/no new) abrir un banco global de esmaltes ordenado por categoría +
  buscador para IMPORTAR al proyecto; "guardar en banco" desde el detalle. Es la nueva categoría de tool
  (biblioteca global). No implementada.

## Fase 9 · Tools instalables Glazy-quality: section, tabla, card estructurada · Martes, 7 de julio de 2026

Subida de nivel del renderer para que las tools se integren de verdad (nivel Glazy), tras feedback del
usuario de que Glaze Recipes se veía primitiva. Builds verdes macOS+iPad.
- **Primitiva `section`** (panel con título + fondo/borde) → una zona tiene su propia división, no
  "tirada encima". Y `field` (label/value de solo lectura).
- **Input `table`** en `NodeForm` (columnas del schema, add/remove filas, celdas editables) → el handler
  recibe un array de `{columnKey: value}` (como las tablas de micro-tools). Es la "tabla que construyes
  directamente" (materiales + cantidades).
- **Primitiva `table`** de solo lectura (render vía tabla Markdown nativa) para mostrar recetas.
- **Card detail estructurada por la tool**: si la tool define `card(card, ctx)`, abrir una card muestra
  SU vista (badges + tabla receta + notas), en `InstalledToolCardPanel`; si no la define, cae al
  `CardDetailView` nativo editable. `InstalledToolEngine.defines()`.
- **Ejemplo `glaze-recipe-book.js` reescrito** a nivel Glazy: form con name/cono/**status picker**/
  **surface picker**/**tabla de materiales**/notas, secciones, y card estructurada (badges + receta como
  tabla Markdown en el body + notas). Fix del doble "+" en el botón. Verificado headless.
- **Anotado (dimensión futura, NO implementada)**: tools que perviven al proyecto = librerías generales
  cross-proyecto (banco de esmaltes accesible desde cualquier proyecto, "guardar en banco", importar).

## Fase 9 · Tools instalables más capaces + pegar imágenes en Notebook · Martes, 7 de julio de 2026

- **Cards de tools instaladas ahora abren el `CardDetailView` REAL** (editable: notas Markdown, pegar
  imágenes, links) → se comportan como las del resto de la app. Los campos custom (`extra`) se
  conservan lossless; el `card()` custom de la tool queda ignorado (se usa el detalle nativo).
- **Input `picker` (selector) en el form** de tools instaladas (`NodeForm`): fila de chips que elige un
  valor. El ejemplo `glaze-recipe-book.js` usa selector de estado (Tested/To try/Rejected).
- **Honestidad de capacidades** (skill+spec): inputs live = text/textarea/number/row/**picker**; NO
  cableados aún = table/grid/batch/showWhen (próximo paso: reusar el motor de form de micro-tools) +
  drag-sharing de cards cross-tool.
- **Pegar imágenes en notas de Notebook**: ⌘V de una imagen la guarda en `_assets/` de la carpeta de la
  nota e inserta `![](ruta)` en el cursor; el render la muestra (vía baseURL). Seleccionar esa línea +
  Align la centra (el renderer ya honra `<div align>`). `pasteImage()` + modificador `pasteImageIntoNote`
  (macOS `onPasteCommand`), reusa `ReferenceStore.clipboardImagePNG`/`model.saveCardImage`.

## Fase 9 · Tools instalables — openExpanded + hotkey + skill final · Martes, 7 de julio de 2026

- **`nidus.openExpanded()`**: una tool puede abrir su propia vista expandida desde un botón/handler
  (patrón "＋ abajo abre el log"). `Run.onOpenExpanded` + bloque inyectado.
- **`hotkey` en el manifest**: letra única → quick action que abre el expandido (cableado en
  `WorkspaceView.handleKey`, junto a Notebook). `descriptor` genera el `ToolQuickAction`.
- La **vista expandida** ahora abre el detalle de card internamente (`openCardID` overlay) al tocar una
  card de su navegador.
- **Skill finalizada** (`~/.claude/skills/nidus-toolmaker/SKILL.md`): añadido openExpanded/hotkey, el
  patrón de tools tradicionales (grupos = cardLists filtrados por `extra`, "＋"→openExpanded, expandido
  a dos paneles) y nota honesta: el drag de cards cross-tool aún NO está cableado (declaración leída,
  wiring pendiente). Spec actualizado igual.
- **2º ejemplo** `tool-examples/glaze-recipe-book.js`: recetario de vidriados NATIVO (sin html) con
  grupos por estado (Tested/To try/Rejected), "＋ New glaze" que abre el expandido, y expandido de dos
  paneles (navegador + form). Verificado headless. Prueba que las tools tradicionales se expresan con
  las primitivas, sin necesitar el webview.

## Fase 9 · Host de TOOLS INSTALABLES (v1) · Martes, 7 de julio de 2026

Infraestructura para importar tools instalables (`.js` declarativas) — la base para juzgar/pulir el
formato antes de crear más tools. Builds verdes macOS+iPad. Archivos nuevos:
- **`InstalledTool.swift`**: parseo del `manifest`, motor JSContext que corre `tile`/`expanded`/`card`/
  `handlers` con un objeto **`nidus`** inyectado (cards.all/get/add/update/remove, openCard, clipboard)
  respaldado por `CardStore` sobre el `.md` de la instancia; construye un `ToolDescriptor` en runtime.
- **`InstalledToolStore.swift`**: carga/instala/desinstala desde **`_tools/`** del vault (como micro-tools).
- **`InstalledToolViews.swift`**: renderer declarativo `NodeView` (primitivas stack/text/markdown/badge/
  divider/spacer/image/cardList/button/form/grid/html) + tile en el board + vista expandida + detalle de
  card. Los handlers corren el JS y re-renderizan.
- **`InstalledToolWebView.swift`**: nodo `html` en `WKWebView` sandbox con puente `window.nidus`
  (reply-based message handler: `cards.all()`/`cards.add()` + `on('cardsChanged')`); sin red salvo
  `network:true`.
- **Registro dinámico**: `ToolRegistry` ahora = `builtIn` + `installedDescriptors`; `NidusModel` carga
  `_tools/` al abrir vault (+ `installTool`/`uninstallTool`). Las instaladas aparecen en la biblioteca de
  Customize Mode en su propia sección "Installed tools" con importar (`NSOpenPanel`/fileImporter) y
  desinstalar.
- **PENDIENTE probar en vivo** (JSContext+WKWebView+render solo corren en la app; el usuario valida).
  Cubierto para el ejemplo `glaze-log.js`. Limitaciones v1: form soporta text/textarea/number/row (grid/
  batch/picker por ampliar); puente webview = leer + add; tap tile→expanded puede necesitar pulido.

## Fase 8 · Event Log instancia única + card Project Tools sin "+" · Martes, 7 de julio de 2026

- **Event Log pasa a instancia única** (`allowsMultiple: false`) — un proyecto tiene una sola historia.
- **Quitado el "+" de las cards de "Project tools"** (instancias detachadas): chocaba con el botón de
  abandonar (papelera). La card entera re-adjunta al tocarla, así que el "+" era redundante ahí. Nuevo
  parámetro `showAdd` en `card()` (true en Template tools, false en Project tools).

## Fase 8 · Abandonar instancia de tool (con deprecación) · Martes, 7 de julio de 2026

- **Nueva acción "Abandon" para instancias de tool**: distinta de quitar del board (que solo la
  detacha, re-adjuntable). Abandonar quita el link de la app para siempre (de grid y de detached) y
  **marca el/los .md como deprecated** (prefija el título `# [deprecated] …` + línea `Deprecated: true`)
  PERO conserva el archivo en disco (los .md son baratos, valor de archivo). Inbox exento.
  `NidusModel.abandonTool` + `MarkdownStore.markDeprecated` (idempotente, no-op si no hay archivo).
- UI: botón papelera en cada card de "Project tools" (instancias detachadas) del panel de Customize +
  `confirmationDialog` explicando que las notas se conservan.

## Fase 8 · Micro-fixes: hover clip, gestor con card, fade proyecto, handle iPad · Martes, 7 de julio de 2026

- **Tile de documento ya no se recorta al hover** — padding extra dentro del scroll horizontal de cada
  estante (`.padding(.horizontal,6).padding(.vertical,8)`).
- **El gestor de micro-tools ya tiene su card** (glassCard + sombra) como el resto de la app; antes
  flotaba sin contenedor sobre el fondo difuminado.
- **Fade al cambiar de proyecto** — `WorkspaceView` con `.id(ref)` + `.transition(.opacity)` y animación
  raíz a 0.4s: cruzar de un proyecto a otro hace un fundido ("entrar en otro espacio") en vez de
  intercambiar el contenido al instante.
- **iPad: la barra-handle izquierda abre el cambiador de proyecto al tocarla** — en Mac era solo hover
  (que no dispara en táctil); añadido `.onTapGesture { sidebarOpen.toggle() }` al handle.

## Fase 8 · Notebook pulido 5: revert dark + tools con presencia · Martes, 7 de julio de 2026

- **Revertido el aclarado de la zona de notas en dark** (al usuario no le convenció). Quitado el
  `@Environment(ThemeController)` que ya no se usa.
- **Sección TOOLS con más presencia**: el "+" pasa a botón redondo más grande (30pt con fondo circular);
  cada micro-tool es ahora una **pastilla de esquinas redondeadas** (`NotebookToolPill`) reactiva al
  hover (fondo + borde + icono en acento), texto más grande (`.callout`) y más padding.

## Fase 8 · Notebook pulido 4: toolbar+, tools en sidebar, caché, dark, fix task · Martes, 7 de julio de 2026

- **Fix (regresión del click único): completar una tarea ya no la abre.** El click de abrir era
  `.simultaneousGesture` → disparaba a la vez que el botón del círculo. Cambiado a `.onTapGesture` (los
  botones hijos —círculo, menú "…"— consumen su propio tap). Además el **círculo de completar tiene un
  área de toque más ancha que el glifo** (30×26, reservada para completar, nunca abre).
- **Toolbar del editor gana: Link, Image, y alineación (izq/centro/dcha).** Link → `[sel](url)` con el
  cursor en la url; Image → `![alt](url)`; alineación envuelve el bloque en `<div align="…">…</div>` **y
  el renderer ahora HONRA esa alineación** (nuevo `MDBlock.aligned` + `MDAlign`, parseo con conteo de
  profundidad de divs anidados, verificado headless).
- **Micro-tools movidos a la columna de info** (decisión del usuario) — sección "TOOLS" en el sidebar
  derecho (icono+nombre por tool, "+" gestiona/importa); ya no hay barra flotante. El runner sigue
  flotando sobre toda la ventana.
- **Sidebar de info más fino** (210→172) para dar espacio a las notas.
- **Modo oscuro: la zona de notas se aclara sutilmente** (`Color.white.opacity(0.05)` solo en dark) para
  trabajar más cómodo.
- **Imágenes remotas se cachean en disco** (`RemoteImageCache` en Caches/, clave = SHA256 de la URL):
  se descargan una vez, quedan disponibles offline y no se recargan cada render. `CachedRemoteImage`
  sustituye a `AsyncImage`.

## Fase 8 · HTML/imágenes en Markdown + click único total + header Notebook · Martes, 7 de julio de 2026

- **El renderer Markdown ahora entiende HTML básico e imágenes** (antes mostraba `<div>`/`<img>` como
  texto crudo — nuestro renderer es propio y mínimo, no un motor GFM completo). Añadido: `MDBlock.image`;
  parseo de `![alt](src)` y `<img src="…">` → imagen renderizada (remota http/https vía `AsyncImage`,
  local relativa a la carpeta de la nota vía `baseURL`); las etiquetas HTML estructurales de una línea
  (`<div>`, `</div>`, `<p>`, `<br>`, comentarios…) se descartan (no se muestran como código); las
  etiquetas inline (`<b>`, `<a>`…) se limpian dejando el texto (sin tocar comparaciones `a < b`).
  `MarkdownView` gana `baseURL` opcional (nil por defecto → las relativas se omiten). Verificado headless
  con el README del usuario. **Nota:** las imágenes remotas se descargan al renderizar (red).
- **Click único abre TODAS las cards** — faltaba Task Manager (`TaskCardRow` seguía en `count:2`), ahora
  click único como el resto.
- **Cabecera del tile Notebook abre la biblioteca general** — `ToolTileView` gana `onTitleTap` opcional,
  cableado en `WorkspaceGridView` solo para el Notebook (abre `NotebookLibraryView`). Antes solo el pie
  "Open Notebook" lo hacía. (Los items del tile siguen abriendo su nota directamente con un clic.)

## Fase 8 · Notebook pulido 2 + click único global · Martes, 7 de julio de 2026

- **Toolbar MD: botón de Título (H1 `#`) además del de Heading (H2 `##`)** — antes solo había subheader.
  Botones "H1"/"H2" con etiqueta de texto.
- **Micro-tools FUERA del panel** (no negociable): la barra flotante ya no vive dentro del editor sino
  a nivel de `NotebookLibraryView`, desplazada JUSTO FUERA del borde derecho del panel (`.offset(x:62)`),
  como en el resto de la app (CardDetailView). Se muestra solo cuando hay una NOTA abierta.
- **Fila "Main Folder"**: la fila raíz (sin grupo) ahora tiene cabecera "Main Folder" + contador de
  items + indicador discreto de anclados **n/2** (pin) — también en los grupos. Da significado visible
  al pin (máx 2 por fila).
- **Botón Select redondo** (icono `checklist` → `checkmark` activo con tinte de acento) en vez de texto.
- **General: cualquier card abre con UN clic** (antes Ideas/Inbox/Task pedían doble). `CardRow` pasa de
  `TapGesture(count:2)` a click único (el drag necesita ≥8pt, así que un tap nunca inicia arrastre) —
  igual que Event Log/Notebook/Reference.
- **Closed view del Notebook: los items recientes abren directamente** (hover reactivo + flecha; clic →
  su editor/visor vía `initialItem`). El pie "Open Notebook" abre la biblioteca general.
- **Esc retrocede un nivel**: dentro de una nota o del visor de documento, Esc vuelve a la biblioteca
  (no al menú principal); en la rejilla de la biblioteca, Esc cierra. Antes cerraba todo desde cualquier
  sitio. `escape()` según `route`.

## Fase 8 · Notebook — editor render-por-defecto + edición · Martes, 7 de julio de 2026

- **Spike previo (clave):** `AttributedString(markdown:)` **elimina los saltos de línea** entre bloques
  — la estructura vive en atributos, no en caracteres (`# T\n\ntexto` → `Ttexto`). Está pensado para
  MOSTRAR con `Text`, no para editar en `TextEditor`. → El WYSIWYG inline verdadero exigiría un motor
  de rich-text propio sobre APIs `TextEditor(AttributedString)` que no puedo probar yo (el usuario
  ejecuta la app), con riesgo de corromper los .md. Consultado con el usuario: eligió la vía segura.
- **Nota abre RENDERIZADA por defecto** (la vista bonita del `MarkdownView` que ya usa la app —
  headers grandes, negritas, listas, tablas, code — el look del screenshot de git). El `.md` crudo
  sigue siendo SIEMPRE la verdad: cero riesgo de corrupción.
- **Botón lápiz → modo edición** (Markdown crudo + toolbar); checkmark vuelve a render. **Doble clic**
  en la vista renderizada también entra a editar. Nota nueva ("n") abre directamente en edición.
- **Outline navega en ambos modos**: en edición lleva el cursor al heading (scroll al caret); en
  render hace scroll al bloque del heading (`ScrollViewReader`, mapeo k-ésimo heading → k-ésimo bloque).
- Título: `Text` grande en render, `TextField` en edición.

## Fase 8 · Notebook — pulido: micro-tools, atajo n, toolbar MD, outline · Martes, 7 de julio de 2026

- **Fix importante: los micro-tools se renderizaban mal dentro del Notebook** (aparecían encajonados
  con layout raro dentro del panel, no como popup propio). Causa: el runner se presentaba como overlay
  DENTRO del editor, que está dentro del panel 1040×700 con `.glassCard()` → recortado. Fix: el runner
  y el gestor de micro-tools ahora los aloja `NotebookLibraryView` y se aplican DESPUÉS de `.glassCard()`
  → flotan sobre toda la ventana (igual que en las cards). La barra flotante sigue en la zona de
  escritura del editor, pero solo dispara `onRunTool`/`onManageTools` hacia arriba.
- **Al pulsar fuera del micro-tool (zona difuminada) vuelves al Notebook**, no a la pantalla principal
  — el dim del runner cubre toda la ventana y va por encima del backdrop de la biblioteca, así que el
  clic cierra solo el micro-tool.
- **Atajo rápido "n"**: la tecla `n` (quick action del Notebook) abre la biblioteca directamente en una
  **nota nueva** lista para escribir. Caso especial en `WorkspaceView.handleKey` (Notebook no usa el
  quick-add de línea; abre el editor). `NotebookLibraryView` gana `startNewNote`.
- **Toolbar de Markdown en el editor** (arriba de la zona de escritura, persistente, como en Ideas/
  Inbox): Bold/Italic/Heading/Bullet/Numbered/Table operando sobre la **selección** (`TextEditor(text:
  selection:)`). Mejora sobre las cards: **una selección multilínea prefija CADA línea** (seleccionas 3
  líneas y "lista" las convierte en 3 items).
- **Outline navegable + elegante**: estilo índice de libro (más espaciado, jerarquía por nivel, hover,
  barra de acento en el seleccionado). **Clic en una entrada lleva el cursor a ese heading** (vía la
  selección), lo que hace que el editor haga scroll hasta él. (El resaltado visual del heading en el
  texto llega con el editor live-render.)
- **QuickLook**: `shouldCloseWithWindow` para limpieza. Nota: copiar texto (⌘C) desde el preview de un
  PDF no está soportado por QuickLook (es un preview, no un lector) — para copiar texto de PDFs haría
  falta PDFKit (`PDFView`) solo para .pdf; de momento "Open in default app" permite copiar desde
  Preview.app. **PENDIENTE grande: el editor live-render** (render en vivo del Markdown, headers
  grandes sin ver `#`) — sigue siendo texto plano en el shell.

## Fase 8 · Notebook (tool nueva, shell) + Reference Board al vault · Martes, 7 de julio de 2026

- **Nueva tool built-in: Notebook** — biblioteca ligera de notas y documentos por proyecto (una sola
  instancia, no duplicable a propósito). Notas = `.md` propios con frontmatter YAML oculto
  (title/id/created — el usuario nunca ve el id ni metadatos); documentos importados (pdf/txt/docx/odt/
  pages/rtf) se copian tal cual y se previsualizan con **QuickLook** + "Open in default app" (sin
  reimplementar lectores). Todo vive en una carpeta real `Notebook/` dentro de la carpeta del proyecto
  en el vault. Archivos nuevos: `NotebookStore.swift` (almacén), `NotebookTool.swift` (tile),
  `NotebookLibraryView.swift` (biblioteca), `NotebookTiles.swift` (tiles + botón "+"),
  `NotebookNoteEditor.swift` (editor), `NotebookDocumentView.swift` (visor QuickLook).
- **Grupos = subcarpetas reales**, mostradas como estantes tipo Apple Books (una fila por grupo + fila
  raíz sin nombre). Se crean/gestionan desde un **modo Select** (selecciona items → "New group" / "Move
  to" / Delete), no con un explorador de carpetas. Cada fila **ancla hasta 2 items** al frente (pin);
  anclar un 3º expulsa el más antiguo. Solo estado inventado: un manifest JSON de anclas por fila.
- **Add flow (botón "+" cuadrado clásico por fila)**: un clic → menú Importar/Crear nota; doble clic →
  crea nota directa; hover + ⌘V → pega (archivo importable, o texto plano → nota nueva). Nunca pega con
  un clic solo. También acepta drag&drop de archivos. Import por `NSOpenPanel` en macOS (mismo motivo
  que micro-tools: `.fileImporter` no dispara dentro del overlay), `.fileImporter` en iOS.
- **Editor de nota (shell)**: título grande, outline desde los headings de la nota, cuerpo Markdown,
  columna de info (Type/Created/Edited) + Delete, barra de micro-tools reutilizada. Autosave con
  antirrebote; el `.md` en disco sigue siendo Markdown portable (frontmatter oculto en la UI). **El
  editor live-render (WYSIWYG-en-Markdown con `AttributedString` + `TextEditor` nativo de macOS/iOS 26)
  es el siguiente paso** — este shell usa una superficie de texto plano de momento, detrás de la misma
  UI. Export/Move/Duplicate diferidos a v2.
- **Reference Board movido al vault**: su carpeta `Nidus References` ya no vive en la carpeta externa
  vinculada del proyecto sino dentro de la carpeta del proyecto en el vault (junto a `Notebook/` y
  `_assets/`) — ahora funciona para CUALQUIER proyecto (antes fallaba en silencio si el proyecto no
  tenía carpeta externa vinculada) y sincroniza como todo lo demás. Quitado el hint "Link a project
  folder". `ReferenceStore.folderURL(forLinkedPath:)` eliminado.

## Fase 7 · Quitado el botón ⊖/⊕ de desactivar campo (redundante) · Lunes, 6 de julio de 2026

- Revertido el toggle ⊖/⊕ por campo (y `locked`) añadido en la ronda anterior — el usuario señaló que
  es redundante: como un campo vacío ya se excluye de `render(data)` (y con el fix de `isSkip` ya
  esconde la sección entera), simplemente no rellenar el campo logra lo mismo sin necesitar un control
  extra. Solución más simple. `MicroToolRunnerView` vuelve a su forma anterior (sin `disabledInputs`),
  `MicroInput` pierde `locked`, Template Library pierde `locked: true` de sus títulos.

## Fase 7 · Template Library pasa a built-in + pulido · Lunes, 6 de julio de 2026

- **Template Library ahora es un micro-tool hardcoded** (5º built-in, junto a Recipe Normalizer/Table
  Builder/Triaxial/Batch Renamer): protegido de borrado, se re-siembra si falta, canónico (las mejoras
  futuras llegan solas a vaults existentes). `MicroToolStore.builtInIDs` += `template-library`.
- **El título de cada template ya no se puede desactivar** — nuevo flag de schema `locked: true` (oculta
  el botón ⊖ para ese campo). Los 11 templates lo usan en su campo de título.
- **El botón ⊖/⊕ de desactivar un campo pasa a la IZQUIERDA de la etiqueta** (antes a la derecha), para
  cualquier micro-tool.
- **Fix: desactivar un campo no lo quitaba del live preview/copy, solo atenuaba la celda** — la causa
  era del propio `render()` de Template Library: un valor vacío seguía imprimiendo la cabecera de
  sección (`## Label`) sin cuerpo. Cambiado su `isSkip` para tratar vacío igual que `"--"` (salta la
  sección entera). Documentado como patrón general en la guía de autoría para cualquier tool que quiera
  este comportamiento.
- **Acordeón de templates con descripción breve por opción**: nuevo campo `description` en las opciones
  de un `picker`, mostrado bajo el nombre en el estilo `list` (no en `chips`/`menu`, no hay sitio) —
  ayuda a usuarios menos técnicos a elegir sin tener que probar cada template.

## Fase 7 · Confirmado: import de micro-tools funciona (NSOpenPanel) · Lunes, 6 de julio de 2026

- El usuario confirmó que el import desde la app ya funciona tras el cambio a `NSOpenPanel` en macOS.
  Dejado apuntado por si vuelve a romperse en el futuro: la causa fue que `.fileImporter` no llamaba a
  su `onCompletion` en esta vista concreta (presentada vía `AnyView` de `WorkspaceOverlay`); no era un
  problema de timing con popovers como se pensó en los dos intentos anteriores. Ver detalle en la
  entrada anterior y en la memoria del proyecto.

## Fase 7 · Micro-tools — input `picker` + campos condicionales · Lunes, 6 de julio de 2026

- **Nuevo tipo `picker`**: elige un preset/template (fila de chips). Su valor es un string
  (`data[key]` en render). Arranca en la primera opción.
- **Campos condicionales `showWhen`**: cualquier input se muestra solo cuando otro campo (típicamente
  el picker) tiene cierto valor (`{ key, equals: "x" }` o `equals: ["x","y"]`). Permite un picker de
  templates que revela únicamente los campos de ese template. Los ocultos no estorban ni se exportan.
- Documentado en `NIDUS-microtool-authoring.md` (con ejemplo cocktail/glaze). Capacidades generales,
  cualquier micro-tool futura las usa.

## Fase 7 · Import micro-tools por fin funciona (NSOpenPanel) + input desactivable · Lunes, 6 de julio de 2026

- **El importador seguía sin funcionar tras quitar el `.popover`.** Diagnóstico con logs: el `.fileImporter`
  dejaba abrir el panel de Finder, pero su `onCompletion` **nunca se llamaba** al elegir el archivo — cero
  logs, sin importar el archivo. Verificado aparte que ni el `.js` ni la lógica de copiar+parsear tenían
  ningún problema (probado en frío contra el vault real: copia y parseo OK). El fallo estaba en cómo
  `.fileImporter` interactúa con esta vista concreta (se presenta dentro de un `AnyView` de
  `WorkspaceOverlay`, no en un `.sheet`/ventana normal — sospecha, sin confirmar del todo).
- **Fix: en macOS, importar una micro-tool ya NO pasa por `.fileImporter`** — usa `NSOpenPanel`
  directamente (AppKit puro), que se salta toda esa maquinaria de SwiftUI. Las imágenes de la card
  siguen con `.fileImporter` (nunca tuvieron el problema). En iOS/iPadOS (sin `NSOpenPanel`) se mantiene
  el `.fileImporter` de siempre para el import de `.js`.
- El panel de gestión (`MicroToolManager`) ahora también muestra un **error inline en rojo** si el
  archivo elegido no parsea como micro-tool válida — antes fallaba en silencio total.
- **Cualquier input de una micro-tool ahora se puede desactivar**: un botón ⊖ junto a cada etiqueta
  (también por campo dentro de un `row`) lo atenúa, lo bloquea y lo excluye del live preview y del
  copy — sin borrar lo que hayas rellenado. ⊕ para reactivarlo. Documentado en
  `NIDUS-microtool-authoring.md`.

## Fase 7 · Fixes menores — import micro-tools, color botón, picker · Lunes, 6 de julio de 2026

- **Fix: importar micro-tool desde la app no metía el archivo**. Causa: el `.fileImporter` se
  presentaba en el mismo instante en que el popover del gestor se cerraba → AppKit se lo tragaba y el
  panel de selección no aparecía. Fix: cerrar el popover primero y presentar el importer 0.2s después.
- **Fix: iconos del top-bar (incl. GitHub) no cambiaban de color al alternar claro/oscuro**. Los
  botones glass se apoyan sobre un fondo de desenfoque del escritorio, y `.secondary` acababa
  muestreando el esquema equivocado. Fix: el color del glifo se deriva ahora directamente de
  `ThemeController.isDark` (glifo claro en oscuro, oscuro en claro) — flip garantizado.
- **Picker mejorado (selector de templates)**: nuevo `style` para el input `picker` →
  **`list`** (default): arranca EXPANDIDO como lista para elegir; al elegir se colapsa al nombre, y
  tocar el nombre lo re-expande. **`chips`** (tabs): la fila de chips de antes. **`menu`** (dropdown):
  menú compacto. Cubre dropdown/select/tabs/accordion/collapsible. Además el picker ya **no
  autoselecciona** — los campos `showWhen` aparecen al elegir. Documentado en la guía.
- **Template Library (.js del usuario)**: el título del export pasa a componer `Nombre del template:
  tu título` (p.ej. "Decision Record: Adopt SQLite") en vez de sustituir el nombre. Verificado con node.

## Backlog / Futuro (apuntado, no implementado)

- **Reference Board — sync con iPad**: las imágenes viven en la carpeta VINCULADA real del
  proyecto (típicamente en el Mac), inalcanzable desde iPad. Falta un espejo continuo dentro del
  propio `NidusVault` (accesible en iCloud desde ambos dispositivos) + reconciliación cuando se
  añade material desde el lado sin acceso directo a la carpeta vinculada. Relacionado con la
  robustez de carpeta pendiente (detectar ausente + re-vincular por marker) — mismo área de
  código (`ReferenceStore.swift`).
- **Submenú de color en el toggle (personalización de tema)** — *cómo lo haría*: el toggle
  (`AppearanceToggle`/`IconButton`) revela **on hover** un pequeño flyout/popover con swatches de
  presets de **paleta**: cada preset = (stops del gradiente de fondo + accent color) — p.ej. azul
  (actual), cálido, verde, magenta. `ThemeController` se amplía para guardar la paleta activa
  (stops + accent) además de `isDark`; `AmbientBackground` lee esos stops en vez del azul
  hardcodeado, y el accent se inyecta app-wide (vía `.tint()` / Color en el entorno). El cambio
  usa la misma transición calmada de `darkness` (commit del esquema al click, fondo en easing).
  Persistencia **local de dispositivo** (`@AppStorage`, coherente con doctrina §9: apariencia no
  se sincroniza). Aparece on hover (flyout lateral), se cierra al salir; en iPad (sin hover):
  long-press o tap-expande. Opción avanzada: color picker para accent 100% custom. Implementar
  cuando toque.

- **Greeting Panel — pulido estético** (→ T3): alineación exacta del toggle con los semáforos
  (idealmente titlebar accessory nativo), crossfade claro/oscuro perfecto de toda la ventana,
  fidelidad liquid-glass y animación de abanico/orbit.
- **Fuzzy search con "New/Create" innato**: el campo de búsqueda debe ofrecer siempre una
  opción "New"/"Create" que, con Enter, dispare directamente la creación de un proyecto nuevo
  (con el texto escrito como nombre candidato).
- **Heredar descripción desde `Project.md`**: al crear un proyecto, buscar primero un
  `Project.md` en la carpeta de trabajo vinculada y heredar su descripción. Si no hay, expandir
  el diálogo para añadir descripción. Si se deja en blanco, siempre editable luego en edit mode
  (Customize Mode, al mover/redimensionar widgets).
- **Reset de layout a por defecto** para proyectos creados con un default antiguo (opcional).
- **Reconciliación con el disco**: al arrancar / escanear, detectar carpetas de proyecto
  ausentes (borradas a mano fuera de Nidus) y actualizar `nidus.json` — marcar "missing" en UI
  y ofrecer relink/quitar de la lista (su contenido ya no existe). Hoy las entradas fantasma
  siguen saliendo en el selector.
- **Archive de proyecto (NO borrar — doctrina §10.2)**: botón Archive en el selector de
  proyectos y en el top-bar de info del proyecto, con confirmación en dos pasos:
  `Archive → ¿Seguro? Sí/No → ¿Abandonado o completado?`. Al confirmar: mover la carpeta del
  proyecto (con toda su data) a una carpeta de archivados del vault (p.ej. `_archived/`),
  desaparece del selector principal, y se registra en `nidus.json` el estado
  (`abandoned` | `completed`) + fecha — se conserva para tracking y la wiki de la LLM local.
- **Restore de proyecto archivado**: acción manual en Settings (futuro).

---

## Fase 7 · Event Log — fix lag de selección (doble-clic manual) · Lunes, 6 de julio de 2026

- **Bug**: apilar `.onTapGesture(count: 2)` + `.onTapGesture(count: 1)` en la misma fila (para el
  doble-clic → branch) obligaba a SwiftUI a **retrasar cada clic simple** mientras esperaba a ver si
  llegaba un segundo — la selección se sentía lenta/con lag.
- **Fix**: un único `.onTapGesture` (dispara al instante, sin espera) que **selecciona siempre en el
  acto**; el doble-clic se detecta a mano cronometrando el tiempo entre dos clics en la MISMA fila
  (<0.4s) y, si se cumple, dispara el atajo de branch por encima de la selección ya aplicada. Cero
  delay perceptible en la selección normal; el doble-clic sigue funcionando igual de bien.

---

## Fase 7 · Event Log — doble-clic branch + buscador de timeline · Lunes, 6 de julio de 2026

- **Doble-clic en cualquier evento de la lista izquierda** = mismo atajo que el botón de rama: abre un
  evento nuevo ya vinculado ("Branches from") a ese evento. El clic simple sigue seleccionando/revelando
  como siempre.
- **Buscador junto al "+"**: campo compacto que filtra la lista izquierda por **título o tipo** (escribir
  "decision" saca todas las decisiones, cronológicas) — pensado para cuando el log crece a cientos de
  eventos. Se combina con "Collapse related" (ambos son formas de acotar la lista).

---

## Fase 7 · Event Log — botón "Branch from this event" · Lunes, 6 de julio de 2026

- **Nuevo botón** justo debajo del lápiz de editar (mismo tamaño, misma esquina): abre directamente
  un evento **nuevo y vacío ya vinculado** ("Branches from") al evento que estás viendo — atajo a
  Add Event → buscar y elegir el padre a mano. El resto del evento (tipo, título, notas…) se rellena
  como siempre; el "Branches from" ya sale puesto.

---

## Fase 7 · Event Log — lápiz fuera, card de tamaño fijo, fade · Lunes, 6 de julio de 2026

- **Botón editar fuera de la card**, esquina arriba-izquierda del panel (simétrico a la "X" de cerrar
  arriba-derecha) — un control de esquina estable, más grande (44pt), en vez de ir dentro del contenido.
- **Todas las cards del mismo tamaño fijo** (420×460): ya no saltan de tamaño entre eventos. Se
  dimensionó para el caso más cargado (título, un branch, 3 líneas de notas, 3 fotos); si un evento
  tiene menos, el espacio sobrante queda dentro de la card; si tiene más, la card **scrollea por
  dentro** (contenido interno en `ScrollView`, tamaño exterior fijo) — nunca cambia de tamaño.
- **Transición suave** entre ver/editar y al cambiar de evento seleccionado: cross-fade (0.18s) en vez
  de corte brusco.

---

## Fase 7 · Event Log — visor en card centrada + editor más compacto · Lunes, 6 de julio de 2026

- **Editor 5% más compacto** tras quitar Related items: spacing 16→14, paddings de campo 12/9→11/8,
  caja de notas 62→52, thumbnails de imagen 64→58, padding exterior 24→22 — todo entra sin scroll.
- **Visor rediseñado como card centrada** (en vez de contenido pegado arriba-izquierda con hueco
  muerto alrededor): una card de ancho fijo (420pt) con fondo/borde sutil y sombra, **centrada vertical
  y horizontalmente** en el panel — y si el contenido es más alto que el panel, sigue scrolleando con
  normalidad (`GeometryReader` + `frame(minHeight:)` + Spacers). Dentro de la card: **tipo en pill con
  su color** (icono+etiqueta) + fecha arriba, lápiz de editar junto al título, "Branches from" si
  aplica, notas y referencias separadas por dividers finos — todo compacto y sin sub-etiquetas de
  sección (MAYÚSCULAS) que ya no hacían falta al ir todo junto en la card.

---

## Fase 7 · Event Log — quitado "Related items" · Lunes, 6 de julio de 2026

- **"Related items" eliminado**: no conectaba a nada de verdad (texto suelto, ni el "estado" era en
  vivo) — la promesa del mockup original (enlace vivo a otra tool) nunca se cumplió. Con **Branches
  from** ya cubriendo la conexión que sí importa (linaje dentro del log), y las Notes ya renderizando
  Markdown para cualquier referencia suelta que quieras anotar, la sección quedaba redundante.
  Simplifica el editor y el panel de lectura. Si algún día hay un sistema real de enlaces vivos entre
  tools, ese es el momento de traer un "Related items" de verdad.

---

## Fase 7 · Event Log — fecha al final, "Today", día sin hora · Lunes, 6 de julio de 2026

- **Fecha por defecto = "Today"**: si no tocas la fecha, el botón pone "Today" (en vez de la fecha
  completa).
- **Día distinto de hoy → sin hora**: elegir un día que no sea hoy guarda la fecha a las 00:00 y el
  timeline muestra **solo el día** (no tiene sentido "12 jun · tu hora actual"). Hoy sí conserva la
  hora real del momento.
- **Reorden del editor**: Type → Branches from → Title → Notes → References → Related → **When al
  final** (pesa menos: sirve sobre todo para mapear un decision-log antiguo o planear milestones/
  iteraciones futuras). Etiqueta cambiada a "When did / will this become relevant?".
- **"+" de referencias**: reacciona al hover en **todo su recuadro** (contentShape), no solo cerca
  del "+".

---

## Fase 7 · Event Log — editar arriba, calendario propio, sin hora · Lunes, 6 de julio de 2026

- **Botón editar movido arriba**, junto al título del evento (a su izquierda, circular con lápiz) —
  ya no está pegado al borrar en la barra inferior (que queda solo con el "Delete" pill a la derecha).
- **Calendario propio** en el editor: el `DatePicker` de serie (feo) se cambia por un botón que abre
  el **calendario del programa** (mismo lenguaje visual que el de deadlines) para elegir el día. Popover
  limpio, selección de día simple.
- **Hora eliminada del editor**: ya no editas la hora — se mantiene la del momento en que se registró
  (elegir un día conserva esa hora). El timeline sigue mostrando fecha·hora (la real).

---

## Fase 7 · Event Log — pulido 3 (colores de rama, reglas, botones, paste) · Lunes, 6 de julio de 2026

- **Buscador de padre por tipo**: escribir "decision"/"iteration"/"milestone"/"abandoned" (o parte)
  saca todos los de esa categoría, cronológicos, además de la coincidencia por nombre — siempre hay
  resultados útiles aunque no aciertes el título.
- **Dimming menos agresivo**: lo no seleccionado baja a opacity 0.6 (antes 0.4) — se atenúa pero se
  sigue leyendo.
- **Spine del color de la rama**: la barra vertical que conecta el hilo usa el **color del tipo raíz**
  de la rama (la decisión de la que nace), no el acento naranja.
- **Botones**: "Edit event" pasa a **botón circular con lápiz** (abajo-dcha, hover), junto a un
  **"Delete" en pill muteado** (sin rojo alarmante, como las otras cards). El "+" de añadir evento
  también es circular/hover.
- **Regla ampliada**: milestone y abandoned son **endpoints** → solo nacen de Decision/Iteration (no
  milestone-de-milestone, no abandonar un logro/abandonado). Decisiones/iteraciones libres.
- **"+" de imagen en el editor**: reacciona al hover, acepta **drag & drop** y **⌘V para pegar** una
  imagen directamente (datos del portapapeles → `_assets/`, o archivos) — como en la card.

---

## Fase 7 · Event Log — pulido: colapsar rama, buscador, reglas, compacto · Lunes, 6 de julio de 2026

- **Colapsar rama**: al seleccionar un evento con hilo, botón "Collapse related" abajo del timeline
  que **filtra la lista a solo esa rama** (y "Show all events" para volver) — cómodo cuando el log
  crece y una rama queda dispersa entre muchas entradas.
- **Botón "+" redondo** siempre visible abajo-izquierda del timeline (hover-reactivo) para añadir
  evento directo; el "Edit event" también reacciona al hover.
- **Selector de padre con buscador**: el "Branches from" pasa de menú a popover con **campo de
  búsqueda** (match por texto) + lista cronológica con tipo/fecha. Cómodo cuando hay muchos eventos.
- **Reglas de vinculación (mínimas, a propósito)**: única regla dura — **un Abandoned solo puede
  nacer de una Decision o Iteration** (no se abandona un milestone/logro ni un abandonado). El resto
  libre (el buscador resuelve la findability; una taxonomía rígida daría más fricción que orden). Si
  cambias el tipo y el padre deja de ser válido, se limpia solo.
- **Tipo Note eliminado** (el programa ya tiene muchas formas de nota; cada evento ya lleva notas).
  Tipos: Decision / Iteration / Milestone / Abandoned.
- **Caja de notas más compacta** (mitad de alto) para que el editor entre sin scroll.
- **Extra resultón**: hacer hover sobre una fila del **tile pequeño** también ilumina su hilo.

---

## Fase 7 · Event Log — ramas/linaje + tipo a la vista · Lunes, 6 de julio de 2026

- **Tipo a la vista**: cada card del timeline (tile y expandido) muestra ahora **icono + etiqueta**
  del tipo en su color (⚑ Milestone · fecha), no solo el punto — reconocible sin memorizar colores.
- **Estructura de ramas ("git" del proyecto)**: cada evento puede **nacer de otro evento** del log
  (una iteración nace de una decisión, un hito de una iteración…). Selector "Branches from" en el
  editor (excluye self + descendientes para evitar ciclos). Guardado en `card.extra["parent"]`.
- **Linaje al seleccionar** (dirección elegida por el usuario): la lista sigue **plana y cronológica**
  (lo nuevo arriba); al seleccionar un evento, **todo su hilo se ilumina** — los puntos del hilo
  brillan, el resto se atenúa, y la **línea del timeline (spine) que los conecta se resalta en
  acento**. Cada evento ramificado lleva un "↳ Branches from: [decisión]" (clicable, salta al padre).
- Orden newest-first intacto.

---

## Fase 7 · Tool nueva — Event Log (v1) · Domingo, 5 de julio de 2026

- **Event Log** (built-in, tamaños 1x1 y 1x2): diario visual tipo "git simplificado" — decisiones,
  iteraciones, hitos y branches abandonados, para que el PORQUÉ de las cosas quede legible.
- Cada evento **reutiliza la Card** (título + notas Markdown + imágenes=References) + 3 extras: una
  **fecha/hora que tú pones** (clave del timeline, orden newest-first), un **tipo de evento fijo con
  color** (Decision azul · Iteration ámbar · Milestone verde · Abandoned rojo muteado · Note gris) y
  **related items** (referencias escritas a mano con estado opcional — v1, sin enlace vivo).
- **Closed view**: timeline compacto y visual (punto de color + línea conectora, fecha·hora, título,
  thumbnail) que invita a abrir; "View all events →".
- **Expanded view** (dos paneles, como el render): lista timeline izq (seleccionable, con subtítulo)
  + panel de detalle dcha (tipo, fecha, notas renderizadas, References, related items) con Edit/Delete;
  "Add event" abre el editor (selector de tipo, date/time picker, título, notas, imágenes, related).
- Almacén: `event-log.md` en el vault (cards con extras `eventDate`/`eventType`/`related`).

---

## Fase 6 · Fix — importer de imágenes de la card + drag/paste en "+" · Domingo, 5 de julio de 2026

- **Bug: el botón "+" de añadir imagen no abría el buscador** — había **dos `.fileImporter` en la
  misma vista** (imágenes + import de micro-tools `.js`), y SwiftUI solo honra uno. Consolidado en un
  único importer enrutado por un enum `importKind` (.image / .tool).
- **References (imágenes) vuelven a verse en modo normal** (se revirtió el ocultado; "Assets and
  tools" sí sigue solo en Edit / si ya hay alguno). Las imágenes son la identidad visual de la card.
- **Drag & drop y paste sobre el "+"** (como en Reference Board): arrastrar una imagen al botón la
  añade (`dropDestination`, con ring de acento al pasar por encima), y hacer **⌘V con el cursor sobre
  el "+"** pega la imagen (datos del portapapeles → `_assets/`, o archivos copiados). Nuevo
  `model.saveCardImage(data:ext:)` para pegar datos crudos.

---

## Fase 6 · Micro-tools v1.7 — widget `batch` + Batch Renamer · Domingo, 5 de julio de 2026

- **Nuevo widget `batch`** (tipo de input general, como `grid`): un prefijo de código + un contador →
  N filas, cada una con su **código autogenerado** (hint en vivo) y celdas editables para las columnas
  del esquema. Las filas conservan sus valores al crecer/encoger el contador. Reutilizable ("una serie
  numerada de ítems con atributos editables").
- **Nueva built-in: Batch Renamer** (`batch-renamer.js`): metes nombre del lote + código (p.ej. "Nm")
  + cuántas pruebas, y rellenas por fila el **cambio/aditivo**, el **nº de tesela física** (asociable
  ahora o después) y **notas**. Exporta una tabla `**Nm-1** | cambio | tesela | notas`. Los pipes en
  celdas se escapan para no romper la tabla. Verificado con node.
- La guía de autoría documenta el widget `batch`.

---

## Fase 6 · Micro-tools v1.6 — form en filas + triaxial pulido · Domingo, 5 de julio de 2026

- **Schema del form: `row` + `maxLength`** (capacidades generales, cualquier tool las usa): un input
  `{type:"row", fields:[…]}` renderiza varios campos escalares en UNA línea (con su label cada uno;
  los `number` van estrechos, los `text` flexibles), y `maxLength` limita el largo de un texto. Sirve
  para declutter de forms sin scroll.
- **Triaxial — form más limpio**: nombre de material + su Max % en la misma línea por vértice
  (▲ Top / ◣ Bottom-left / ◢ Bottom-right), nombres clave limitados a 14 caracteres, y **máx 5 pasos**
  (antes 8). Entra sin scroll.
- **Triaxial — triángulo del output**: los nombres de los vértices inferiores (B y C) ahora van
  **inline a la izquierda y a la derecha** de la fila base (no debajo), con A centrado arriba; y el
  **code-block se renderiza centrado** en la nota/preview (los diagramas ASCII ya no quedan pegados a
  la izquierda). La guía de autoría documenta `row` y `maxLength`.

---

## Fase 6 · Micro-tools v1.5 — code-blocks + Triaxial + unit a la derecha · Domingo, 5 de julio de 2026

- **Unit a la derecha también en el editor**: el chip de unidad de columna pasa de la izquierda a la
  derecha de la celda, coincidiendo con cómo se lee en el export ("10 g").
- **Code-blocks en el renderer de Markdown**: texto entre ` ``` ` se renderiza **monoespaciado y con
  los espacios preservados** (scroll horizontal si hace falta) — habilita ASCII art / diagramas
  alineados en cualquier nota, no solo en micro-tools. Añadido a la guía de autoría.
- **Nueva built-in: Triaxial** (`triaxial-calculator.js`): 3 materiales en las esquinas (A arriba, B
  abajo-izq, C abajo-dcha) + nº de pasos → exporta un **triángulo de puntos** (en code-block, bien
  alineado) más una **tabla de mezcla** con el % de cada material en cada punto. Verificado con node
  (esquinas 100%, blends intermedios suman 100%). Primer tool cuyo output es un diagrama y no una
  tabla clásica — posible gracias a los code-blocks.
- **Triaxial — pulido tras prueba**: (1) los **nombres de los materiales van en sus vértices** del
  triángulo (A arriba centrado, B abajo-izq, C abajo-dcha) en vez de solo en el título; (2) **cada
  vértice tiene su límite %** configurable por el usuario (default 100) — permite testar fuera del
  100%, p.ej. bases A/B al 100% y C "hasta 15%" (una adición); el valor de cada esquina = su max ×
  su peso baricéntrico; (3) triángulo **bien centrado** (se corrigió el sangrado que lo escoraba a
  la derecha); (4) campo **"Test name"** arriba del editor, reflejado como título; (5) en la tabla
  cada **vértice se marca con su nombre** junto al número, y (6) los **~3 puntos centrales** se
  marcan `(center)` (1 exacto si N múltiplo de 3). Built-ins ahora **canónicos**: el seed reescribe
  la versión enviada cuando cambia, así las mejoras llegan a vaults existentes.

---

## Fase 6 · Micro-tools v1.4 — preview que crece + unit por columna · Domingo, 5 de julio de 2026

- **Preview con altura adaptativa**: la card de live preview arranca pequeña (arriba-derecha del
  editor) y **crece hacia abajo con su contenido** hasta un tope (~640), y solo ahí scrollea. Se
  acabó la card grande medio vacía. **Crece también en ancho** (decisión del usuario: el jitter solo
  ocurre los primeros segundos armando la tabla; luego rellenar sin scroll es más cómodo). Todo con
  clamp min→max y animación suave.
- **Unit por columna** (rediseñado al modelo correcto): la unidad es ahora **estado por columna**, no
  texto de celda. Pulsas el **botón de regla** de una columna, escribes la unidad (g, %, ml, °C…) y
  Apply/Enter → aparece como un **chip fijo anclado a la izquierda de cada celda de datos de esa
  columna** (aunque estén vacías), y escribes el valor en el espacio a su derecha. Al exportar se
  pliega en el valor ("10 g"); el texto crudo que escribes en la celda sigue siendo solo el valor.
  Volver a pulsar la regla precarga la unidad actual para editarla o borrarla (vacío + Apply la quita).
  Antes "no pasaba nada" porque el enfoque viejo solo añadía a celdas ya rellenas; ahora el chip
  aparece de inmediato en toda la columna. El header (fila 1 estilada) se mantiene limpio.
- **Selector de nº de columnas** junto a "+ Column" (menú, máx 8): eliges N directamente en vez de
  clicar "+ Column" varias veces — la tabla se asienta en un paso y el jitter del preview sale una
  sola vez. "+ Column" también tope 8.

---

## Fase 6 · Micro-tools v1.3 — preview flotante + grid con −/swap · Domingo, 5 de julio de 2026

- **Preview flotante anexo**: el editor y el live preview vuelven a ser dos cards SEPARADAS —
  editor a la izquierda, preview flotante contigua anclada a su derecha (más ligero que fusionado).
  El preview scrollea en ambos ejes, así una tabla ancha (muchas columnas) ya no colapsa en "…".
- **Grid — controles − y swap en vez de ⋯+duplicar**: cada columna tiene ‹ − › centrados arriba
  (mover izquierda / borrar / mover derecha) y cada fila tiene ∧ − ∨ en el margen izquierdo (subir /
  borrar / bajar). Se quitó el menú ⋯ y el "duplicar" (poco útil). El reorden por swap-con-adyacente
  sustituye al drag & drop (elegante y sin la fragilidad del drag).
- La guía de autoría aclara que el host provee TODA la UI de edición (add/borrar/reordenar filas y
  columnas + live preview) automáticamente — el autor solo declara el esquema y `render`; el
  documento es por tanto la superficie completa que controla un autor de micro-tools.

---

## Fase 6 · Micro-tools v1.2 — live preview + grid más completo · Domingo, 5 de julio de 2026

- **Live preview (todas las micro-tools)**: el runner pasa a dos paneles — editor a la izquierda
  (mismo tamaño) y un panel de **preview a la derecha que renderiza el Markdown en vivo**, tal como
  se verá en una nota (usa el mismo `MarkdownView`). El botón **Copy** vive ahora en ese panel. Ves
  la tabla/normalización formándose mientras escribes. El popup dejó de estar recortado dentro de la
  card: ahora es un modal propio que atenúa toda la ventana y flota centrado.
- **Return añade fila**: pulsar Enter en la última fila de una tabla/rejilla añade otra (feel de hoja
  de cálculo). (Tab sigue moviendo el foco de celda de forma nativa.)
- **Grid (Table Builder) más completo**:
  - **Scroll horizontal** con ancho de columna cómodo — muchas columnas ya no se aplastan (arreglado
    el problema de +6 columnas).
  - **Duplicar / eliminar fila** (menú ⋯ por fila) y **duplicar / eliminar columna** (menú ⋯ por
    columna) — antes solo se podía borrar la última columna.
  - Auto-formateo al exportar (ya presente): descarta filas vacías, recorta espacios.
- **Diferido a propósito** (dicho al usuario): drag & drop para reordenar filas/columnas (grande y
  delicado — el reorder por drag ya nos costó 3 intentos en Reference Board; mejor hacerlo en un pase
  propio) y los **roles de celda** (Heading/Separator/Unit) — requieren extender el contrato del
  widget (celdas con metadato de rol) + menú por celda; se hará como iteración dedicada. El
  "separator" ya se cubre por convención (fila con solo la 1ª celda rellena = divisor en negrita).

---

## Fase 6 · Micro-tools v1.1 — input `grid` editable + Table Builder · Domingo, 5 de julio de 2026

- **Nuevo tipo de input `grid`**: una tabla editable que empieza en NxM (2×2 por defecto) y **crece en
  ambas direcciones** (+ Row / + Column), con borrar fila y borrar última columna. La primera fila es
  la cabecera (estilada). El host dibuja toda la UI; el `.js` sigue siendo puro y recibe `data[key]`
  como **array 2D de strings**. Motivación: el runtime declarativo (text/textarea/number/table) no
  podía expresar un editor de tabla cómodo con columnas variables — este widget lo desbloquea sin
  romper el sandbox. Decisión deliberada: añadir UN widget con demanda real, no un framework
  especulativo de widgets.
- **Nueva built-in: Table Builder** (`table-builder.js`, sembrada y protegida como Recipe Normalizer).
  Rejilla visual → tabla Markdown limpia: primera fila = cabecera, alineación numérica automática por
  nombre de columna, y una fila con solo la primera celda rellena = **divisor de sección en negrita**.
  Verificada con node.
- Guía de autoría `NIDUS-microtool-authoring.md` ampliada con el tipo `grid` (esquema, forma de
  `data[key]`, cuándo usar `table` vs `grid`, y un ejemplo completo).

---

## Fase 6 · Fix — heading en la nota partía la card en dos · Domingo, 5 de julio de 2026

- **Bug (introducido con el render Markdown de las notas)**: `CardStore` usa `## ` al inicio de línea
  como separador de cards en el `.md`. Al permitir ahora escribir headings Markdown en la nota, un
  `##`/`###` en el cuerpo se reinterpretaba como una card NUEVA al releer el archivo → al darle a
  Done la nota se "exportaba" partida en dos (la mitad interior aparecía como card fantasma sin foto).
- **Fix**: el parser desambigua por el comentario de metadatos. Toda card escrita por la app lleva
  `<!-- nidus:{…} -->` justo bajo su `## título`; un heading del cuerpo no. Ahora un `## ` solo abre
  card nueva si la línea siguiente es ese comentario. Los archivos legacy/escritos a mano sin ningún
  metadato mantienen el comportamiento antiguo (cada `## ` es una card). Verificado con simulación:
  el heading del cuerpo se queda dentro, las cards reales se separan bien, y el caso legacy no cambia.
- **Recuperación**: como el arreglo es en el LECTOR y el archivo en disco seguía teniendo la card en
  un solo bloque, al reabrir la card fantasma desaparece sola (su texto vuelve a su sitio) — salvo que
  la fantasma se hubiera editado/guardado por separado, en cuyo caso quedaron dos bloques reales y hay
  que borrar la fantasma a mano (la real conserva todo).

---

## Fase 6 · Micro-tools — infraestructura + Glaze Normalizer · Domingo, 5 de julio de 2026

- **Capa de micro-tools**: herramientas pequeñas, modulares y aditivas que viven DENTRO del modo
  edición de una card (Inbox/Ideas). "Markdown templates + un pequeño apoyo lógico". Cada una es un
  **`.js` autocontenido** — formato elegido sobre `.py`/ejecutables porque un `JSContext` de
  JavaScriptCore (framework nativo, cero dependencias) **no tiene acceso a disco/red/sistema**, así
  que correr una micro-tool de la comunidad es seguro y no requiere runtime empaquetado ni procesos.
- **Contrato del `.js`**: define un global `tool` con `{ id, name, icon, summary, inputs[],
  render(data) }`. `inputs` es el ESQUEMA del formulario que la app renderiza de forma genérica
  (tipos `text`/`textarea`/`number`/`table`), así que una tool nueva no necesita código Swift.
  `render(data)` es una función PURA (escalares como strings, tablas como arrays de `{col: string}`;
  hace su propio `parseFloat`) que devuelve Markdown. El resultado se **copia al portapapeles** y lo
  pegas (⌘V) en la nota — desacoplado, sin depender de qué campo tiene el foco.
- **Almacén**: `_microtools/` en la raíz del vault (como `_icons`), así una micro-tool instalada
  está disponible en **todos los proyectos** y sincroniza por iCloud.
- **UI**: columna flotante abajo-derecha de la card — colapsada a una pieza de puzzle sutil (indica
  que existen) cuando no editas, **se expande hacia arriba en modo Edit** mostrando las instaladas
  con un **`+` de importar arriba del todo**. Hover muestra nombre. Clic → popup del runner (form
  del esquema + botón "Copy Markdown"). El importador acepta `.js`, valida que parsee como tool y si
  no, descarta el archivo.
- **Primera micro-tool: Recipe Normalizer** (sembrada como `.js` en el primer arranque, pasa por el
  MISMO pipeline importable que cualquier tool de la comunidad). Genérica: materias primas + cantidad
  → normaliza a base 100; aditivos en % (no normalizados); exporta una tabla Markdown limpia (base +
  "Total base recipe 100.00" + aditivos con "+ nombre" + "Total"). Verificado: la receta de prueba
  da el total 105.50 correcto. Icono `percent`, subheader completo sin truncar.
- **Pulido tras prueba**: (a) la columna de micro-tools vive ahora JUSTO FUERA del borde derecho de
  la card (antes solapaba dentro); (b) en hover cada botón muestra el nombre de la tool en una pastilla
  a su derecha; (c) el `+` ahora abre un **gestor** (popover): lista de micro-tools instaladas con
  **borrar** las del usuario — las **built-in** (Recipe Normalizer y las que hagamos nosotros) están
  bloqueadas con candado y se re-siembran si faltan — más **Importar (.js)**.
- **Guía de autoría** `NIDUS-microtool-authoring.md` (raíz del repo, junto a `NIDUS-tools-guideline.md`):
  spec técnico, preciso y orientado a IA para que otra IA genere un `.js` de micro-tool sin conflictos
  (contrato del objeto `tool`, tipos de input del esquema, contrato de `render(data)`, subset de
  Markdown soportado, iconos SF Symbol, checklist y dos ejemplos completos).

---

## Fase 5 · Pulido notas + Quick-add hereda nombre + hotkeys sin colisión · Domingo, 5 de julio de 2026

- **Título + Edit fijados** (pinned) arriba del popup de card: antes se iban con el scroll de la
  columna de info; ahora se quedan visibles mientras bajas por una nota larga, así siempre sabes
  qué card es y cómo editarla.
- **Borde sutil en la zona de notas** (modo vista): un contorno un par de tonos más claro que el
  panel delimita el bloque de Markdown renderizado, para identificarlo de una pasada sin recurrir a
  una caja pesada ni scroll interno.
- **Quick-add más elegante**: el prompt hereda el nombre de la instancia — pulsar la R de "Recipes"
  ahora abre **"Quick Recipes"** (antes salía el nombre genérico del tipo de tool). El campo usa un
  placeholder versátil ("Add a new entry to the active project…") válido para cualquier tool, y se
  quitó el tercer subheader redundante ("Adds to the active project.").
- **Hotkeys sin colisión**: al editar el hotkey de un tool, ya **no se permite** elegir una letra
  que otra instancia del tablero ya usa (su override o su default). El campo rechaza la tecla y
  muestra momentáneamente **"Hotkey already in use"** en rojo, en vez de dejar dos tools con la misma
  letra (donde antes siempre saltaba la primera y la segunda quedaba muerta). El editor de tool
  (renombrar + hotkey) pasó de un `alert` nativo a un panel de cristal propio para poder validar en
  vivo, coherente con el resto de la app.

---

## Fase 5 · Notas con render Markdown (Inbox + Ideas) · Domingo, 5 de julio de 2026

- **Modo vista renderizado / modo edición texto plano** para las notas de Inbox e Ideas (los
  únicos dos tools con notas libres multilínea — Task Manager y References usan notas de una
  línea, no aplica). Reutiliza el toggle Edit/Done ya existente en `CardDetailView`: en Edit ves
  y escribes Markdown crudo; en Done/View se renderiza de verdad.
- **Parser de bloques propio** (`MarkdownRender.swift`, sin dependencias externas — coherente con
  el resto del proyecto): encabezados `#`/`##`/`###`, listas con viñetas y numeradas, y **tablas
  estilo GFM** (`| a | b |` + fila separadora). El énfasis inline (negrita/cursiva) se delega a
  `AttributedString(markdown:)` por línea/celda — ya lo resuelve bien, no hacía falta reinventarlo.
  Render minimalista: sin caracteres ASCII de tabla, sin bordes pesados, solo un divider fino bajo
  la cabecera — línea visual del resto de la app.
- **Toolbar de Markdown básico**, visible solo en modo Edit, arriba de la caja de notas: Bold,
  Italic, Heading, Bullet list, Numbered list, Table. Actúa sobre la selección/cursor real
  (`TextEditor(text:selection:)`, API de macOS 15+/iOS 18+ — sobra margen con el deployment target
  26.5): Bold/Italic envuelven la selección (o insertan el par vacío con el cursor en medio si no
  hay selección); Heading/listas anteponen el marcador a la línea actual; Table inserta una
  plantilla 2×2 lista para sobreescribir.
- Misma caja que antes (crece 1→8 líneas, luego scroll interno sin scrollbar vía `TidyScroll`) para
  que cambiar de modo no salte de tamaño. El editor en modo Edit también perdió su scrollbar nativa
  (`.scrollIndicators(.never)`), quedando consistente con el resto de la app.
- **Alcance explícito de este tramo**: solo el render + el toggle + el toolbar básico. El
  mecanismo de **micro-tools** (botón redondo flotante, independiente del card, que se expande al
  entrar en Edit — primer caso de uso: un normalizador de recetas/esmaltes que copia una tabla
  Markdown ya normalizada al portapapeles para pegarla aquí) queda **fuera de este tramo**;
  se documentó su forma pero no se construyó nada de su plomería para no dejar un hueco a medias.
- **Fix tras prueba**: el modo vista ya no mete el render dentro de una caja con su propio
  scroll interno — eso obligaba a un scroll-dentro-de-scroll incómodo. Ahora el Markdown
  renderizado va embebido directo en el flujo de la columna de info (que ya scrollea entera,
  sin scrollbar), así que se puede bajar todo lo que haga falta con un solo scroll. El modo
  Edit conserva su caja delimitada (tiene sentido ahí: es un campo de texto editable con
  tamaño acotado 1→8 líneas).

---

## Fase 4 · References — pulido final del tile/nota · Domingo, 6 de julio de 2026

- **Hint de pegar** como texto plano integrado (fuera el emboss que se veía mal).
- **Editor de nota que envuelve**: pasa a `TextField(axis: .vertical) + lineLimit(1...3)` — el texto
  hace salto de línea dentro del espacio en vez de estirarse/scrollear horizontalmente; Enter guarda
  (newline→commit), tope 60.
- **Abrir el visor clicando en cualquier lado del tile**: antes solo respondía la barra superior (el
  ScrollView del collage se comía el tap); ahora `simultaneousGesture(TapGesture)` sobre todo el tile
  (coexiste con el scroll). Un clic en cualquier imagen/zona abre el visor.
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 4 · References — tile scrolleable + nota sólida + cierre de la herramienta · Domingo, 6 de julio de 2026

- **Nota más legible**: el fondo pasa a una **zona blanca sólida** (0.9) hasta el 58% de la altura y
  solo a partir de ahí se difumina a transparente; texto un pelín más oscuro.
- **Tile scrolleable con TODAS las imágenes**: fuera el auto-fill; ahora el masonry se puebla con
  todas, las que no caben se recortan y se **hace scroll SIN barra** (`.scrollIndicators(.never)`),
  **anclado arriba** (`.defaultScrollAnchor(.top)`) para respetar el orden (lo primero = prioridad).
  El visor también ancla arriba.
- **Reference Board cerrada** (V1+V2+pulidos). Pendiente cuando se quiera: V3 (robustez de carpeta:
  detectar ausente + re-vincular por marker).
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 4 · References — nota legible, zoom on-top, + directo + hint de pegar · Sábado, 5 de julio de 2026

- **Nota legible**: vuelta a menos transparencia (0.85 abajo) + degradado **multi-stop** que se funde a
  transparente sin corte visible arriba; texto centrado.
- **Hover-zoom siempre por encima**: el zIndex era por columna; ahora se sube el **zIndex de la
  columna** que contiene la imagen en hover (track `hoveredID` en `MasonryScroll`), así la foto
  ampliada queda on-top de las vecinas de otras columnas también.
- **"+" flotante = importar directo** (fuera el popover que solo enseñaba importar).
- **Hint de pegar**: texto embossed discreto bajo el "+": *"Did you know you can paste any image?
  Just press ⌘V"*.
- Confirmado: pegar/soltar **texto o documentos no-imagen** no añade nada (se filtra por tipo/extensión).
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 4 · Notas de referencia — pulido + hover-zoom +15% · Sábado, 5 de julio de 2026

- Nota: el fondo pasa de un rectángulo sólido a un **gradiente blanco que se difumina hacia arriba a
  transparente** (sin corte abrupto) y un pelín más translúcido; **texto centrado** y menos oscuro
  (menos contraste). Icono 💬 movido a **abajo-derecha** y ~10% más pequeño.
- **Hover-zoom +15%** (de 1.05 a 1.15) para ver mejor el detalle. (Dentro del margen; si en algún
  tamaño se sale, se avisa.)
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 4 · Scrollbar fuera de los tools + notas de referencia · Sábado, 5 de julio de 2026

- **Sin scrollbar en los tools**: `TidyScroll` (Inbox/Ideas/Task Manager/Archive) y los scrolls del
  Reference Board pasan de `.scrollIndicators(.hidden)` a `.never` — no se ve barra aunque haya que
  bajar.
- **Nota por imagen (References)**: cada imagen puede llevar una nota corta de trazabilidad ("¿por
  qué está aquí?"). En el visor, **hover** sobre la imagen muestra la nota como un overlay
  **blanquecino translúcido** (hasta 3 líneas); **doble-clic** la edita (máx 60 caracteres, Enter o
  clic fuera guarda). Se guarda en el manifiesto oculto (`Manifest.notes`, decode tolerante, se poda
  al borrar la imagen). Un icono 💬 sutil al hover indica que se puede anotar cuando está vacía.
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 4 · Pulido — "+" flat, no cerrar al clicar chrome, hover en Reorder · Viernes, 4 de julio de 2026

- **"+" flotante flat**: fuera el gradiente/relieve; ahora solo círculo (material) + borde blanco +
  un poco de **fulgor fuera** (glow), reactivo al hover. Coherente con lo flat de la app.
- **Clicar el panel (fuera de un botón) ya no lo cierra**: los taps en el chrome (cabecera/toolbar)
  se tragaban y caían al backdrop de dismiss. Añadido `.contentShape(Rectangle())` +
  `.simultaneousGesture(TapGesture)` en el visor de referencias **y también** en `CardDetailView` y
  `TaskDetailView` (pasaba en las cards también). `simultaneousGesture` para no robar foco a los
  campos de texto.
- **Botón Reorder con hover**: fill + borde que reaccionan al pasar el ratón.
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 4 · Reference Board — reorder que por fin funciona (patrón de las cards) · Viernes, 4 de julio de 2026

El `List.onMove` en macOS resultó poco fiable (la fila volvía a su sitio). Reescrito `ReorderView`
con **el mismo patrón que sí funcionó en las cards**: sobre una rejilla **estática** (frames
reportados una sola vez → sin churn ni warning) una **copia flotante** sigue al cursor, la celda
destino se **ilumina**, y al soltar se hace **una sola** reordenación con animación (nada de
reindexar en vivo = nada de lag/escalonado). Borrar sigue con la "x". Persiste y fija Manual.

- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 4 · Reference Board — reorder nativo (fin del drag janky) · Viernes, 4 de julio de 2026

- **Reorder rehecho**: el drag propio (frames + offset) iba fatal (fotos que desaparecían al cogerlas,
  movimiento escalonado) y emitía el warning rojo `RefCellFrameKey tried to update multiple times per
  frame`. Sustituido por un **`List` nativo con `.onMove`** (arrastrar filas para reordenar): fiable,
  cómodo y sin geometría custom. Cada fila = thumbnail + asa + borrar; al mover, persiste y fija
  Manual. Fuera `RefCellFrameKey`/`ReorderCell`/estado de drag → adiós al error rojo.
- Nota: los warnings **amarillos** (intents/`com.apple.linkd.autoShortcut`, `ViewBridge`, task port)
  son ruido del sistema de Apple, no de Nidus; no se pueden silenciar desde la app.
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 4 · Reference Board — tile auto-relleno + Sort limpio + Add borde blanco · Viernes, 4 de julio de 2026

- **Tile que se auto-rellena**: en vez de "parar cuando la siguiente no cabe", ahora `MasonryTile`
  elige el número de columnas que **empaqueta el máximo de imágenes** llenando el recuadro (el
  tamaño más grande con el que caben todas; si no caben, el que quepa más). La densidad marca el
  ancho mínimo de columna (small = pueden encoger más → caben más).
- **Sort limpio**: arreglado el "Sort" que se cortaba (`.fixedSize()`), y **fuera la flecha de
  dirección** — Manual = tu orden; Added/Created salen **cronológicos (más nuevo primero)** y ya.
- **Add con borde blanco, sin naranja**: `AddPill` y el "+" flotante pierden el acento; ahora borde
  blanco + glare/sombra al hover (el FAB es un círculo glass con borde blanco).
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 4 · Reference Board — reorder real + hover contenido + Add con presencia · Viernes, 4 de julio de 2026

- **Imágenes nunca tocan el borde**: el masonry calcula las columnas sobre el ancho **menos** el
  margen (26/20), así ni con hover-zoom llegan al borde; fuera el `.clipped()` (que recortaba feo).
- **Contador en el tile**: pill discreto "N images" abajo-derecha, para saber cuántas hay aunque solo
  se vean las primeras.
- **Reorder que SÍ funciona (estilo iPhone)**: el DnD nativo de SwiftUI no movía nada; sustituido por
  un **drag propio** (frames de cada celda vía PreferenceKey + hit-test del cursor); arrastras una
  imagen y las demás se reacomodan en vivo; al soltar, persiste y fija el orden Manual.
- **Add con presencia**: el `Menu` se comía el estilo custom → ahora `AddPill` y el **"+" flotante**
  (`AddFab`) son botones con **popover** (Import / Paste), con su cápsula/círculo de acento, glare y
  sombra reactivos al hover. El flotante es un círculo grande de verdad, no un "+" plano.
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 4 · Reference Board — pulido del visor + calendario +10% · Jueves, 3 de julio de 2026

- **Deadline Calendar ~10% más grande** (440×200, banda 200, mini-mes 164) — aprovecha el hueco.
- **Visor: hover ya no se sale**: la zona de imágenes recorta al panel (`.clipped()`) y el masonry
  tiene margen interno (16/12), así el zoom al hover tiene aire y no choca con bordes/vecinos.
- **Densidad pictográfica**: iconos (`square.grid.3x3` / `square.grid.2x2`) en vez de "Small/Medium".
- **Sort agrupado y discreto**: los modos (Added/Created/Manual) + dirección van dentro de una
  cápsula con la etiqueta "Sort", en `controlSize(.small)`.
- **Reorder que SÍ funciona**: el drag&drop nativo por item no movía nada; sustituido por el patrón
  fiable `DropDelegate` (array vivo `reorderItems` que se mueve al pasar por encima + persiste al
  soltar). Fija el orden Manual.
- **Add con personalidad** (`AddPill`: tinte de acento + glare al hover) y un **"+" flotante**
  (`AddFab`) centrado abajo con presencia (glass, sombra, glare) que hace lo mismo.
- **Contador con label**: "5 images" en vez de solo "5".
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 4 · Reference Board — V2 (visor + orden) + fixes · Miércoles, 2 de julio de 2026

Fixes sobre V1:
- **Parpadeo arreglado**: los thumbnails recargaban al re-maquetar (resize) → caché de proceso
  (`ThumbnailCache`, CGImage) + fallback síncrono desde caché en `BoardThumb` (sin frame en blanco).
  Carga fuera del hilo principal (`Task.detached`).
- **Tamaño 2x1** añadido a las capacidades del board (`.wide`), además de 1x1/1x2/2x2.
- **Densidad** (Small / Medium): columnas más anchas = imágenes más grandes y menos. Persistida por
  board (`@AppStorage` por slotID); se controla desde el visor y el tile la respeta.
- El tile ya no lleva barra de "Add reference"; **doble-clic abre el visor**. Vacío = "Paste or drop".

V2 — **visor grande** (`ReferenceViewer`, se abre con doble-clic):
- **Masonry scrollable** con todas las imágenes + **hover-zoom** (se agrandan al pasar el ratón).
- **Orden**: Added (llegada) / Created (creación de archivo) / Manual, con **dirección** (↑/↓). Un
  **manifiesto oculto** (`.nidus-references` JSON: id + arrival + order) registra la llegada y el
  orden manual; se reconcilia con la carpeta (nuevos entran, borrados se podan).
- **Añadir** desde el visor: importar, pegar (⌘V) y arrastrar.
- **Reordenar** (botón Reorder): rejilla tipo Finder, arrastrar para mover (drag&drop de nombre),
  fija el orden Manual; borrar imagen (x) = quita el archivo de la carpeta.
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 4 · Reference Board (mood board) — V1 · Martes, 1 de julio de 2026

Nueva tool image-first. Decisiones: masonry (sin recortar), la fuente de la verdad es una carpeta
real **`Nidus References` dentro de la carpeta VINCULADA del proyecto** (no el vault), solo imágenes
en v1.

- **`ReferenceStore`**: crea/valida la carpeta + un **marker oculto** (`.nidus-references` con UUID),
  lista las imágenes con su tamaño en píxeles (barato vía ImageIO, sin decodificar), y carga
  thumbnails downsampleados. Importar/pegar/guardar data en la carpeta.
- **`ReferenceBoardToolView`** (tool `reference-board`, clase widget, tamaños 1x1/1x2/2x2, sin `.md`):
  - **Entrada**: **pegar** (⌘V en macOS + botón; lee imagen o file-URLs del portapapeles),
    **importar** (fileImporter) y **arrastrar** archivos (`dropDestination`). Todo copia a la carpeta.
  - **Collage masonry** en el tile: columnas de ancho fijo, alto por ratio, muestra las primeras que
    caben **sin recortar**; para de añadir cuando la siguiente no cabría entera.
  - Estado vacío con "Add reference"; si el proyecto no tiene carpeta vinculada, hint para vincular.
- Pendiente V2 (visor grande + hover-zoom + modo editar/reordenar + modos de orden) y V3 (robustez:
  detectar carpeta ausente + re-vincular por marker).
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 3 · Fix — tile congelado al salir de edición a media animación · Lunes, 30 de junio de 2026

- **Drag no se congela al pulsar ⌘E a media animación**: el gesto del grid estaba gateado solo por
  `isEditing`; al salir de Customize mientras un tile se movía/asentaba, SwiftUI cancelaba el gesto
  sin `onEnded` → `dragTranslation` fijo → tile congelado. Ahora el gesto sigue vivo para el tile en
  arrastre (`isEditing || isDragging`) y vuelve a `.subviews` cuando el drag se asienta. Termina de
  colocarse aunque salgas de edición.

---

## Fase 3 · Búsqueda card-aware (ilumina el card exacto) + color neutro real · Lunes, 30 de junio de 2026

Calendar:
- **Color neutro (varios / sin tags) real**: ya no es `.primary` (que se veía gris), sino
  **near-white en oscuro / near-black en claro** (`colorScheme`), visible pero no radiactivo. Aplica
  a puntos de mes/día/lista y a la banda de semana.

Búsqueda — rework (el que estaba apuntado):
- **Card-aware**: `searchContent` recorre las **instancias** del grid (no nombres fijos), lee sus
  cards vía `CardStore` y matchea **título + cuerpo**. Cada `ContentHit` lleva ahora `toolID`,
  `slotID` y `cardID` (antes solo el nombre de archivo canónico).
- **Ilumina el card exacto, no el tool**: al elegir un resultado, `model.reveal(ref/slotID/cardID)`
  → el tool correcto hace **scroll hasta el card y lo ilumina** con un anillo de acento (`RevealingList`
  envuelve la lista con `ScrollViewReader`; `CardRow`/`TaskCardRow` tienen `flashing`). Se acabó
  encender las dos task managers. Cubre instancias duplicadas y funciona entre proyectos (onAppear).
- **Palette**: icono/label del resultado por `toolID` (vía descriptor). Fuera `flashHighlight`/
  `toolID(for:)`/`highlightedTool` (highlight por tipo de tool).
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 3 · Calendar pulido + arranque de auditoría de búsqueda · Domingo, 29 de junio de 2026

Calendar:
- **Múltiples tags → color de más contraste**: el neutro pasa de gris (`.secondary`) a `.primary`
  (blanco en oscuro / negro en claro). Aplica a puntos del mini-mes y de la lista.
- **Mes**: ya no se pinta cada día del mes; ahora un **puntito junto al nombre del mes** (color del
  tag, o blanco/negro si varios).
- **Semana**: una **única banda continua** detrás de la fila entera (antes día a día), con el color
  del tag muy suave (0.16) en vez de gris, sin pisar los otros elementos. (Mini-mes reconstruido con
  filas explícitas en vez de `LazyVGrid` para poder dibujar la banda.)

Búsqueda (auditoría — la arquitectura cambió mucho y quedó desfasada):
- **Arreglo ahora**: `searchLines` ya no filtra los títulos de card (`## …`) — antes se excluían TODOS
  los `#`, así que no se podía buscar una card por su título; ahora sí (por el texto del título). Y
  se excluyen las líneas de metadatos `<!-- nidus:… -->` (era el "ruido JSON" que salía).
- **Pendiente (tramo de búsqueda dedicado, apuntado)**: los resultados apuntan al **tipo** de tool,
  no a la instancia/card concreta → al pulsar Enter se iluminan TODAS las task managers en vez del
  card exacto. Además `searchContent` usa los nombres canónicos fijos (`toolFiles`), así que no cubre
  instancias duplicadas (`tasks-todo-2.md`, etc.). Rework: search card-aware (indexar título/cuerpo,
  devolver card id + instancia, y revelar/iluminar ese card concreto).

---

## Fase 3 · T5 — Deadline Calendar agregador · Sábado, 28 de junio de 2026

El overview card (slot anclado arriba) pasa de scaffold pasivo a **activo**, agregando los deadlines
de **todos los task managers activos** del proyecto.

- **Agregador** (`NidusModel.deadlineEntries(folderURL:grid:)` + `DeadlineEntry`): recorre cada slot
  `task-manager` del grid, lee su `tasks-todo.md` y recoge las tareas con deadline (título, scope,
  lista de origen, y color = el del tag si hay exactamente uno, neutro si 0 o varios). Se refresca con
  `fileChangeTick`.
- **Mini-mes** (mes actual): **punto de color** en los días con deadline de día (neutro si varios);
  **tinte suave** en los días cubiertos por un deadline de semana/mes; hoy marcado.
- **Lista de próximos**: ordenada por cercanía (`sortDate`), filtrando lo aún relevante (`isRelevant`
  — una semana/mes cuenta hasta que termina), 4 primeros: punto de color + título + "cuándo · lista".
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 3 · Task Manager — pulido 3 (selector de color, saturación, Enter en notas) · Sábado, 28 de junio de 2026

- **Selector de color de tag propio** (`TagColorDot`): un popover con las **8 muestras de color
  reales** (el `Menu` nativo pintaba los swatches en monocromo → no se veía el color). El disparador
  es un círculo de color visible; fuera el espacio muerto. Reutilizado en el chip del editor y en el
  gestor de tags.
- **Saturación de tags +~5%**: subida un poco desde el muteado excesivo (sigue calmada, no
  radiactiva).
- **Enter en las notas del task = guardar y cerrar**: la nota es una sola línea corta (Enter =
  hecho, sin párrafos). `TextField` de una línea con `onSubmit` → `close()`; se sanea cualquier
  salto de línea y sigue el límite de 80.
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 3 · Task Manager — pulido 2 (fit-to-content, origen, fecha de completado) · Viernes, 27 de junio de 2026

- **Editor de tarea sin scroll**: el popup crece justo para caber (fixedSize vertical), así el
  calendario y todo entra siempre. El **viewer del Archive** hereda esto → se autoadapta y queda
  justo (fuera el mar de espacio muerto).
- **Notas de tarea máx 80 caracteres** (una tarea es algo directo).
- **Re-clic en el día seleccionado = limpiar** el deadline (sin tener que pulsar "Clear").
- **Archive → de qué lista viene**: al completar se guarda el nombre del task manager de origen
  (`card.originName`); en la celda del Archive aparece un pill discreto (🗂 nombre) y en el viewer una
  línea "From … · Completed dd/mm/yyyy".
- **Archive → fecha de completado**, no de creación: la celda del Archive muestra `card.modified`
  (día en que se completó) en vez de la fecha de creación.
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 3 · Task Manager — pulido (compacto, viewer, tags settings, calendario) · Viernes, 27 de junio de 2026

Cinco ajustes tras la primera prueba (el modelo funcionó de maravilla):

1. **Celda de tarea más compacta**: fuentes/espaciado/padding reducidos (título 13.5, subnota
   caption, redondo 15, footer 13, padding 10/8) — cabe lo mismo en menos alto.
2. **Archive = solo viewer**: abrir una tarea del Archive es un visor **read-only** (título, notas,
   tags y deadline como texto/chips estáticos), sin edición ni botones salvo **Delete task**. La
   edición vive solo en el Task Manager. (`TaskDetailView(editable:)`.)
3. **Gestor de tags** (`TagManagerView`, sheet desde un engranaje discreto en la sección Tags del
   editor): renombrar, **recolorear** y **borrar** tags del banco. `NidusModel.renameTag/deleteTag`.
   Borrar un tag no rompe nada: las tareas que lo tuvieran simplemente dejan de mostrarlo.
4. **Fuera la nota de deadline**: los tags ya cubren eso; eliminado el campo.
5. **Calendario de deadline propio** (`DeadlineCalendar`, estilo de la app, dentro del card):
   **1 clic = ese día**, **doble clic = esa semana entera**, **doble clic en el mes = ese mes**;
   flechas para cambiar de mes; "Clear" para quitar. Fuera el `DatePicker`/segmentado anticuado.

- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 3 · Task Manager como cards (T1–T4) · Jueves, 26 de junio de 2026

Reescrito el Task Manager (y el Archive) sobre el modelo de card universal. Calendario agregador
queda para su propio tramo (T5).

- **Modelo (T1)**: campos de tarea sobre la card, en su `extra` (lossless): `tagIDs`, `deadline`
  (fecha + scope Día/Semana/Mes) y `deadlineNote`. Nuevo **banco de tags** compartido a nivel de
  vault (`nidus.json` → `tags`), como las disciplinas: se crean escribiendo, autocompletan, y cada
  uno tiene un color de 8 presets (`TagPalette`). Métodos en `NidusModel`: `createOrFindTag`,
  `setTagColor`, `tagSuggestions`, `tags(ids:)`.
- **Celda de tarea (T2)** `TaskCardFace`/`TaskCardRow`: tags de color arriba, **botón redondo** de
  completar + título (tachado si hecho), subnota si la hay, y footer con **fecha (izq)** + **pill de
  deadline sutil (der)** ("Jun 16" / "Wk Jun 16" / "June"). Drag, doble-clic para abrir y menú "…".
- **Editor (T3)** `TaskDetailView`: mismo lenguaje que Ideas, adaptado — título + redondo de
  completar, **Notes** (auto-crece a 8 líneas), **Tags** (chips con color editable + añadir con
  autocomplete del banco), **Deadline** (segmentado None/Day/Week/Month + fecha + nota). Guarda al
  cerrar; borrar. (`FlowRow` para que los chips fluyan a varias líneas.)
- **Completar → Archive (T4)**: el redondo mueve la card a `tasks-done.md` del proyecto (recordando
  su archivo de origen en `originFile`); en el **Archive**, el redondo la **devuelve a su origen**.
- **Cutover**: el todo viejo (`- [ ]`, sin `##`) se lee como 0 cards → limpio. El done viejo
  (`## Completed:`) sí aparecería como cards basura → conviene vaciar `tasks-done.md` de prueba.
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 2 · paso 3j — card compacta en altura + notas que SÍ crecen + panel fijo · Jueves, 26 de junio de 2026

Aclarada la terminología (CARD = celda en el tool; POPUP = visor de detalle):

- **CARD más compacta en altura** (se adapta al ancho del tool, eso no cambia): fuentes más
  pequeñas (título 15pt, notas footnote), menos espaciado e interlínea, thumbnail 46px, padding
  reducido → caben más apiladas. Footer ultracompacto: **🔗N · 🖼N** agrupados a la izquierda y
  **fecha numérica DD/MM/YYYY** a la derecha (antes "1 image" / "25 Jun…" repartidos con huecos).
- **POPUP de altura FIJA otra vez** (deshecho el "altura según contenido"): el panel no cambia de
  tamaño; el **contenido de la columna de info hace scroll** si se desborda.
- **Notas que de verdad crecen (bug arreglado)**: antes se quedaban en 2 líneas con scrollbar y
  nunca se expandían — el texto-espejo que medía la altura estaba **atrapado dentro del mismo frame**
  que intentaba calcular, así que siempre devolvía el mínimo. Ahora la altura se calcula con
  **métricas de fuente** (`boundingRect`) sobre el ancho real medido, creciendo de 1 a **8 líneas** y
  con scroll interno a partir de ahí.
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 2 · paso 3i — popup más compacto + notas 8 líneas + fix "…" · Miércoles, 25 de junio de 2026

- **Sin espacio muerto / más compacto**: el popup ya no tiene altura fija (560) con un ScrollView
  codicioso que dejaba un hueco enorme antes del Delete. Ahora la **altura sigue al contenido**
  (`fixedSize` vertical, cap ~600), el Delete va justo bajo el contenido, y se bajó un poco el tamaño
  de cabecera/título (22pt), paddings y miniaturas (64px). Algo más estrecho (920/540).
- **Notas hasta 8 líneas**: la caja crece hasta 8 líneas antes de hacer scroll interno (antes 5), así
  se aprovecha el espacio en vez de dejarlo vacío.
- **"…" sin solaparse**: en la celda, el thumbnail baja 18px para dejar libre la esquina superior
  derecha del menú "…" (y de paso queda alineado con las notas, como el mockup).
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 2 · paso 3h — celda de card según mockup + foco de teclado · Miércoles, 25 de junio de 2026

- **Flechas siempre que no se edite texto**: el popup mantiene el foco de teclado por defecto
  (`.focusable` + `rootFocused`), así que ←/→ navegan las fotos cuando **no hay campo de texto
  activo**. Al escribir en un campo, las flechas mueven el cursor (el campo las consume); clicar la
  imagen o una miniatura devuelve el foco a la card. Ya no depende del hover sobre el visor.
- **Escape cierra**: vía un comando `.cancelAction`, dispara aunque haya un campo enfocado, y guarda
  igual que la X / tocar fuera.
- **Celda de card rediseñada (fuente de verdad: mockup)** — válida para tools "note-based":
  - **Título** + **preview de notas (2 líneas) SIEMPRE**, también cuando hay imágenes (antes se
    sustituía por "N images"); **thumbnail** de portada a la derecha.
  - **Divisor** y **footer** repartido: icono de **enlace** (solo si hay alguna referencia) ·
    **contador de imágenes** (solo si hay) · **fecha** (`MMM d, yyyy`).
  - Menú **"…"** arriba-derecha (aparece al hover): Open / Delete card (borra la card y sus assets).
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 2 · paso 3g — popup: persistencia al cerrar + navegación del visor · Miércoles, 25 de junio de 2026

Dos fallos del uso real:

- **No guardaba al tocar fuera (crítico)**: cerrar tocando el backdrop hacía `overlay.dismiss()` sin
  pasar por el guardado. Ahora `CardDetailView` guarda en `.onDisappear`, así que **tocar fuera = la
  X = Escape**: todo (título, notas, links, imágenes) persiste igual. Borrar imagen y borrar card
  guardan/limpian al instante (`removeImage`/`deleteCard` con un flag `deleted` para que el cierre no
  resucite la card borrada). Añadir imagen también persiste el vínculo al momento.
- **Navegar fotos sin estar en Edit**: el visor tenía atado "portada" y "lo que se ve". Ahora se
  separan: `previewIndex` (lo que muestra el visor, **navegable**) vs. `selected` (la portada, que se
  elige con el selector de Edit). Se navega **clicando una miniatura**, con **chevrons** laterales en
  el visor (aparecen al hover) o con las **flechas ←/→** (clic en la imagen para enfocar). Anillo de
  acento = portada; anillo tenue = imagen que se está viendo.
- **Cosmético**: el "+" de añadir imagen ya no se recorta al hover — la caja queda fija a 76px y solo
  reacciona el glifo (escala) + el glare.
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 2 · paso 3f — popup: menos fricción, Edit = borrar, renombres · Miércoles, 25 de junio de 2026

Ajustes a partir del uso real (el "Edit" como modo completo daba demasiada fricción):

- **Título y notas siempre editables**: se escribe directamente clicando, sin entrar en modo. El
  botón **Edit** ahora solo revela controles de **borrado/selección**: la "x" de cada imagen y
  referencia, los dos campos de cada referencia, el selector de portada, y un borrar del **bloque de
  nota entero**.
- **Notas auto-crecientes**: la caja crece con el contenido y a partir de **5 líneas** hace scroll
  interno (un mirror invisible mide la altura vía `NotesHeightKey`), sin deformar el resto del popup.
- **Delete card** ya no es rojo: mismo lenguaje de pill suave que Edit, integrado.
- **Imágenes sin recortar de serie**: el visor muestra la imagen **entera** por defecto
  (`imageFill = false`); el botón del visor la pasa a rellenar el marco si se quiere.
- **Selector de portada**: en modo Edit, cada miniatura tiene un botón redondo (junto al de borrar)
  que se ilumina con el **acento** al elegirla como portada (solo una).
- **Botón "+" de imagen reactivo**: glare diagonal + lift (escala) al hover (`GlareAddButton`).
- **Renombres**: la sección de imágenes pasa a llamarse **References** (referencias visuales); los
  enlaces pasan a **Assets and tools**. Estos piden **Nombre + Link**; tras Enter se muestra solo el
  nombre, y en Edit se pueden reeditar ambos o borrar.
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 2 · paso 3e — popup de card según mockup canónico (vista/edición, References) · Miércoles, 25 de junio de 2026

Reescritura de la disposición de `CardDetailView` tomando el mockup del usuario como **fuente de
verdad** (la disposición previa quedaba "fea"):

- **Sin divisor vertical**: dos columnas separadas solo por aire. El visor de imagen ocupa toda la
  altura a la izquierda; la columna de info a la derecha.
- **Modo vista/edición**: por defecto es un **lector limpio** (título y notas como texto). El botón
  **Edit** (lápiz → "Done") hace editables el título y las notas. References e imágenes se gestionan
  siempre inline.
- **Notas** en panel redondeado con borde; en vista se renderiza el texto, en edición un `TextEditor`.
- **References** (antes "Links"): filas agrupadas con icono de documento + nombre + abrir, separadas
  por divisores, y una fila final **"Add reference"** (pegar URL, autocompleta nombre desde el host).
  En edición aparecen el nombre editable y la "x" para quitar. Abrir normaliza la URL (`asOpenableURL`).
- **Imágenes** abajo: miniaturas 76pt (clic = portada) + recuadro punteado "+", todo pulsable.
- **"Delete card"** como pill con borde abajo-derecha; **Edit** también es pill. Ambos reactivos al
  hover (`HoverPill`). Cerrar = círculo gris reactivo (`HoverCircleButton`).
- **Visor**: botón circular **blanco** abajo-izquierda (flechas hacia afuera) que alterna fit/fill;
  la imagen sigue contenida (no se desborda).
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 2 · paso 3d — pulido del popup de card (contención, links, asset cleanup, Space) · Miércoles, 25 de junio de 2026

Pasada de pulido sobre el panel reutilizable, a partir del uso real:

- **Imágenes contenidas**: el visor ya no se desborda. La imagen vive dentro de un recuadro
  redondeado (`RoundedRectangle` relleno + `overlay` + `clipShape`), así que nunca escapa.
- **Botón fit/fill**: pequeño botón abajo-izquierda del visor que alterna **rellenar el cuadro**
  (zoom, sin distorsión) vs. **ajustar la imagen entera** (`aspectRatio .fill`/`.fit`).
- **Borrar limpia los assets**: al borrar una card (o quitar una imagen) se eliminan también sus
  archivos de `_assets/` (`model.deleteCardImage`), para no acumular ruido en disco.
- **Links inteligentes**: la URL se normaliza al abrir (`String.asOpenableURL` añade `https://` si
  falta) → adiós al error −50. Cada link tiene **nombre editable**, autocompletado desde el host
  (`www.google.com` → "google.com"). `Card.links: [CardLink]` (título + url); decode tolerante lee
  el formato viejo `[String]` sin perder nada.
- **Space para abrir**: con el cursor sobre una card, pulsar **Space** abre su popup (solo puede
  haber una en hover → sin ambigüedad). `CardDragController.hovered` + `handleKey`.
- **Rediseño compartimentalizado**: cabecera con **icono + nombre del tool** (la instancia, p.ej.
  "Recipes" vía `ToolContext.name`) y cerrar; divisor visor↔info; **Notas con más espacio**, Links
  debajo de Notas, **Imágenes abajo del todo**, y **Borrar abajo-derecha** discreto y reactivo al
  hover. Botón "+" de añadir imagen: ahora todo el recuadro es pulsable (`.contentShape`).
- Builds verdes macOS + iPad (simulador). Pendiente prueba manual.

---

## Fase 2 · paso 3c — panel reutilizable viewer+editor (notas/imágenes/links) · Miércoles, 24 de junio de 2026

- **Drag menos "snappy"**: la card levantada sigue al cursor con un `interactiveSpring` suave +
  transición de aparición/desaparición.
- **`CardDetailView` reescrito a viewer + editor reutilizable** (para tools aditivas): a la izquierda
  un **visor grande** (la imagen abierta = portada, se guarda al cerrar); a la derecha **título
  editable**, **Notas** (Markdown), **Imágenes** (tira de miniaturas, clic = elegir portada, botón +
  para añadir) y **Links** (lista + añadir/abrir/quitar). Guarda al cerrar; borrar incluido.
- **Modelo**: `Card.links: [String]` (en metadatos, optional en `CardMeta` → backward-safe).
  `model.importCardImage` copia la imagen elegida a `_assets/` del proyecto y devuelve su ruta
  relativa (sobrevive al mover la card entre tools).
- Cada tool aditiva reusa el panel; Tasks tendrá su variante (fecha/tag/orden) más adelante.
- Builds verdes macOS + iPad. Pendiente prueba manual.

---

## Fase 2 · paso 3b.5 — drag PROPIO (sin DnD de SwiftUI, sin fantasma) · Miércoles, 24 de junio de 2026

El `.dropDestination` de SwiftUI no entregaba el drop en el grid anidado (y arrastra un "ghost"
translúcido = ruido visual). Insight del usuario: completar una tarea ya mueve datos entre 2 `.md`;
lo difícil era solo detectar el drop. Reimplementado a mano:
- **`CardDragController`** (@Observable, en el entorno): guarda la card en arrastre + su posición +
  los marcos de los tools (`ToolFramePreferenceKey`) + el `targetFile` bajo el cursor.
- **`CardRow`**: `DragGesture` en el espacio `"workspace"` → la card original se atenúa y la **card
  real se levanta** (`CardFloatingView`, nítida, con sombra — sin ghost) siguiendo al cursor. Al
  soltar, el controlador detecta el tool bajo el cursor por su marco y llama a `model.moveCard`.
  **Doble-clic** abre el popup (no colisiona con el arrastre).
- **Tools** reportan su marco (GeometryReader→preference) y se **resaltan** cuando son el destino.
- Quitado todo el DnD de SwiftUI (`.draggable`/`.dropDestination`/`CardTransfer`/`CardDrop`).
- Builds verdes macOS + iPad. Pendiente prueba manual del usuario.

---

## Fase 2 · paso 3b.4 — drop (causa real) + doble-clic + LazyVGrid · Miércoles, 24 de junio de 2026

- **Causa real del drop fallido (del log del usuario)**: el UTType propio `studio.paramo.nidus.card`
  no estaba declarado en Info.plist → el pasteboard recibía **Data vacía** → el drop no traía nada.
  Fix sin tocar Info.plist: `CardTransfer` usa `CodableRepresentation(contentType: .json)` (tipo ya
  registrado). El move/lossless ya estaba.
- **Interacción**: pulsar-y-arrastrar mueve; **doble-clic abre** el popup (`TapGesture(count: 2)`),
  para que nunca colisionen. Preview de arrastre con pinta de card (menos "fantasma").
- **Warning LazyVGrid corregido**: el mini-mes metía cabeceras/blancos/días con ids `Int` que
  colisionaban en un mismo `LazyVGrid` ("ID used by multiple child views" → layout indefinido). Ahora
  cada sección lleva `.id` único (`wd*`/`blank*`/`day*`).
- (Los warnings de `com.apple.linkd`/task-port son ruido benigno del sistema, no del código.)
- Builds verdes macOS + iPad. Pendiente prueba manual del drop.

---

## Fase 2 · paso 3b.3 — fix drop + pulido de card · Miércoles, 24 de junio de 2026

- **Drop arreglado (presumiblemente)**: el drag ya funcionaba pero el drop no soltaba. `CardTransfer`
  pasa de payload `String` a **`Transferable` con UTType propio** (`studio.paramo.nidus.card`), para
  que `.draggable`/`.dropDestination` casen exacto. `CardDrop.handle` y los `dropDestination` usan
  `CardTransfer.self`. (Pendiente prueba manual.)
- **Card pulida**: borde y sombra **adaptativos** (`Color.primary.opacity` + `shadow`) → visibles en
  light y dark; **altura uniforme** (`minHeight 54`) para que cards con/sin subtítulo midan igual;
  **título prioritario** (hasta 2 líneas, legible entero) y subtítulo como hint (1 línea); timestamp
  + thumbnail (42px) a la derecha.
- Builds verdes macOS + iPad.

---

## Fase 2 · paso 3b.2 — cards autocontenidas + fix tap/drag · Miércoles, 24 de junio de 2026

- **`CardRow` rediseñado a card autocontenida** (estilo notificación Apple): superficie propia
  (rounded rect con fill sutil + borde + hover), thumbnail 40px a la izquierda, título (semibold),
  subtítulo (preview del cuerpo / nº de imágenes) y **timestamp relativo a la derecha** (hora hoy /
  "Yesterday" / fecha corta). Listas de Inbox/Ideas pasan de divisores a **cards espaciadas**.
- **Fix tap+drag**: el tap-para-abrir bloqueaba el `.draggable` (no arrancaba el arrastre). Cambiado
  a `.simultaneousGesture(TapGesture())`, que coexiste con el drag. Pendiente de **prueba manual**
  del usuario (no se puede accionar DnD nativo vía automatización).
- Builds verdes macOS + iPad.

---

## Fase 2 · paso 3b — Ideas como cards + drag entre tools · Miércoles, 24 de junio de 2026

- **Ideas reescrito a cards** (cutover limpio), reusando `CardRow`/`CardDetailView`/`CardStore`.
  Verificado en disco: añadir idea → card con metadatos; el instance renombrado ("Recipes") escribe
  en su propio `ideas.md`. `IdeaEntry`/`IdeaDetailPanel` quedan muertos (sin usar).
- **Quick-add de ideas crea Card**: el hotkey de Ideas (`CardStore.append`) en vez del formato viejo;
  `QuickAddTarget`/`QuickAddView` llevan el `tool` para el `origin` de la card.
- **Drag entre tools (move lossless)**: `CardTransfer` (payload JSON), `model.moveCard` (lee origen,
  fija `origin`=source + `modified`, quita de origen, añade a destino), `CardDrop.handle` +
  `CardDropHighlight`, y `.draggable`/`.dropDestination` en Inbox e Ideas. `CardRow` pasó de Button a
  vista plana (tap + draggable conviven; un Button se comía el drag).
- **Bug**: el detail overlay no estaba gateado en `handleKey` → teclas del cuerpo se filtraban; añadido
  `overlay.content == nil`.
- **Verificación**: cards + serialización + expand + edit/save confirmados en vivo y en disco. El
  **gesto de drag NO se pudo accionar vía automatización** (eventos sintéticos no inician DnD nativo de
  macOS) — el cableado es estándar; pendiente prueba manual del usuario. Builds verdes macOS + iPad.

---

## Fase 2 · paso 3a — arquitectura de Card + Inbox como cards · Miércoles, 24 de junio de 2026

La base del modelo de cards (substrate común + exposición por tool), aplicada primero a Inbox.

- **Icono full-bleed que se salía del círculo**: `logoGlyphSize` (0.58 con círculo) para imagen/built-in;
  los procedurales (metaball/bauhaus) se quedan a 0.72. Verificado en greeting + workspace.
- **`Card` (modelo)**: `id, title, body (markdown), images, created, modified, origin, extra`. `make()`
  crea con id estable + timestamps.
- **`CardStore` (serializador)**: lee/escribe un `.md` como lista de cards conservando el header
  autodescriptivo del tool. Formato: `## título` + `<!-- nidus:{json} -->` (id, fechas, origin,
  images, extra) + cuerpo Markdown. `append/update/remove`; `update` refresca `modified`.
- **`CardRow` (compact)** + **`CardDetailView` (popup expandido)** sobre blur (vía `WorkspaceOverlay`):
  thumbnail+título+subtítulo en el tile; título/cuerpo editables, galería de imágenes, fecha, borrar.
- **Inbox reescrito a cards** (cutover limpio): capturar crea una Card (`origin: "inbox"`); lista de
  `CardRow`; click → popup. Verificado end-to-end en disco (round-trip del formato).
- **Bug**: el detail overlay no estaba gateado en `handleKey` → las teclas del cuerpo se filtraban a
  los atajos T/I. Añadido `overlay.content == nil` al guard.

Pendiente paso 3b: Ideas como cards (reusa componentes) + **drag Inbox↔Ideas** (el move lossless).
Nota: la búsqueda (paleta ⌘F) aún no indexa títulos de card (`## ` se salta); pendiente hacerla
card-aware.

---

## Fase 2 · paso 2 — hotkeys data-driven + descripción full-width · Miércoles, 24 de junio de 2026

- **Descripción del proyecto a todo el ancho**: se enmaquetaba en una columna estrecha (junto al
  icono) desperdiciando el ancho. Ahora los controles (Open Folder + lápiz) flotan en overlay
  arriba-derecha (misma posición visual) y la descripción usa el **ancho completo del card** +
  líneas dinámicas (3 con quick actions, 5 sin) — cabe mucho más sin recortar ni mover lo demás.
- **Hotkeys de tools data-driven** (paso 2): `handleKey` ya no hardcodea I/T; recorre los slots del
  grid y dispara el quick-add de la tool cuyo hotkey efectivo coincide (override de instancia, si no
  el `defaultHotkey` del descriptor). El quick-add apunta al `.md` de **esa instancia** (no a un
  archivo fijo), así una copia escribe en su propio fichero.
- **Hotkey personalizable por instancia**: nuevo `ToolSlot.hotkey` (persistido en `nidus.json`);
  `model.setToolHotkey`; el alert de Customize pasa a "Edit tool" (Name + Hotkey, el campo de hotkey
  solo si la tool declara quick action). Verificado: `t`→primer Task Manager, y poniendo `r` a
  "Task Manager 2", `r`→quick task que aterriza en Task Manager 2. Builds verdes macOS + iPad.

---

## Fase 2 · paso 1 — `ToolDescriptor` ampliado · Miércoles, 24 de junio de 2026

Base declarativa del contrato (sin comportamiento nuevo todavía; lo leen los pasos 2–4).
- Nuevos tipos: `ToolClass` (collector/worker/lens/widget/archive), `CardKind` (generic/task),
  `ToolAction` (id/title/icon), `ToolQuickAction` (defaultHotkey/label).
- `ToolDescriptor` gana `toolClass` (requerido) + `accepts`/`produces`/`actions`/`quickAction`
  (con defaults, así no rompe los descriptores existentes).
- Las 4 base declaran lo suyo: Inbox/Ideas = collector (aceptan generic+task); Ideas y Task Manager
  exponen quick action (i→"Quick Idea", t→"Quick Task"); Task Manager = worker (produces task,
  acción "complete"); **Task Archive = archive + singleton** (`allowsMultiple: false`, `accepts: []`
  — solo se llega completando). Builds verdes macOS + iPad.

---

## Fase 2 — arquitectura de tools: contrato documentado · Miércoles, 24 de junio de 2026

Diseño consolidado (sin código todavía) en `NIDUS-tools-guideline.md` (raíz del repo), la semilla del
skill "crear una tool". Decisiones fijadas:
- **Card lossless**: contenido Markdown + metadatos abiertos; cada tool lee su subconjunto y **preserva**
  el resto → mover entre tools nunca destruye datos. **Mover (reubicar)**, no enlazar, por defecto.
- **Clases de tool**: Collector (Inbox/Ideas), Worker (Task Manager), Lens (Calendar), Widget (sin `.md`,
  p. ej. Pomodoro). **Archive** = singleton de sistema (sink con memoria de origen).
- **Matriz de drag**: sacas de Collector/Worker/Archive; metes en Collector/Worker (enriquece); no en
  Lens/Widget.
- **Subsistema de tareas**: clases con color (registro **por proyecto**, 8 colores); fecha día/semana/mes;
  Calendar = Lens de solo lectura, ventana **rodante de 4 semanas** por cercanía (día→punto de color;
  semana/mes→se iluminan al clicar/hover); Archive singleton alimentado al **completar**, con trazabilidad
  de origen (descheck → vuelve si el doc existe, si no popup; arrastrar = reubicar).
- **Descriptor**: añadirá `class`, `accepts/produces`, `actions`, `quickAction (hotkey+label)`; hotkeys
  **personalizables por instancia**; `handleKey` leerá el registro.

Pendiente: implementar lo anterior y evolucionar las 4 tools base de "vistas de lista" a **cards**.

---

## Pulido — sugerencias de disciplina, editor no se cierra, flash de ⌘N · Miércoles, 24 de junio de 2026

- **Pills de disciplina (overview)** en el creador y el editor: con el campo vacío o ya con una
  disciplina válida, salen las **3 disciplinas con más proyectos** (para no teclear de memoria y
  duplicar "cerámica"/"cerámicas"); al escribir, mutan a las coincidencias. (`disciplineSuggestions`.)
- **Editor: clic dentro del panel ya no cierra**: una capa que absorbe los toques dentro del panel
  flotante evita que un clic al lado de un campo se cuele al backdrop con blur y descarte la edición.
  Solo el área borrosa de fuera cierra.
- **Flash de tamaño al hacer ⌘N corregido**: `WindowGroup.defaultSize = 360×600`, así la ventana
  nueva (un Greeting) nace ya al tamaño del panel en vez de heredar el tamaño grande del workspace
  y encogerse un instante después.

---

## Workspace — rediseño del card del proyecto + quick actions · Miércoles, 24 de junio de 2026

Fase 1 (cosmético) del pase del Workspace.

- **Sidebar**: botón de ayuda ~20% más pequeño (46→37); fuentes reducidas (disciplina 18→14 con
  `minimumScaleFactor`, así "PROGRAMMING" cabe en una línea; proyectos 14→13).
- **Card del proyecto**:
  - **Open Folder** movido a la esquina superior derecha (junto al lápiz de editar en Customize).
  - **Icono** rediseñado: fuera la esfera con glare (deprecated); ahora panel de cristal redondo
    (`ultraThinMaterial`) **sin glare**, con borde fino y **fulgor perimetral suave**, icono
    contenido (cristal de reloj antiguo).
  - **Quick actions**: hasta 3 atajos por proyecto en la fila inferior. En Customize salen 3 slots
    "Configure quick action"; el popup permite 4 tipos + título: **App**, **Web**, **Route** (un
    archivo *o* una carpeta — `.folder` en los tipos del importer, así la carpeta se *selecciona* en
    vez de solo navegarse) y **Script** (ejecuta el archivo: directo si es ejecutable —respetando su
    shebang— o vía `/bin/zsh`). Fuera de Customize solo se ven las configuradas, centradas (0/1/2/3).
    App/Route abren nativo en macOS (`NSWorkspace`), Script se ejecuta (macOS), Web en cualquier
    plataforma; se guardan en `nidus.json` (`quick_actions`). Nuevos: `QuickAction` (modelo),
    `model.setQuickActions`, `ProjectQuickActions` (UI).
- **Bug corregido**: en Customize las teclas sueltas se filtraban a los atajos T/I/F (el popup de
  quick-action no marcaba `isEditingText`). `handleKey` ahora se inhibe también con `isCustomizing`
  (las tools están inertes ahí y hospeda campos de texto: rename, config de quick-action).

---

## Workspace — editar proyecto + sidebar a ayuda · Miércoles, 24 de junio de 2026

Primer tramo dentro del Workspace.

- **Editar el proyecto desde el Workspace**: en Customize Mode (⌘E) aparece un **lápiz** sobre la
  identityCard que abre el editor — reusa `AddProjectView` en modo `editing:` (precarga nombre,
  disciplina, descripción, icono y ruta; cabecera "Edit project / Refine your project"; botón "Save
  changes"). Se presenta como overlay glass centrado sobre el workspace atenuado.
- **Modelo `updateProject(...)`**: actualiza nombre/descr./icono/ruta in-place; si cambia la
  disciplina, **mueve la carpeta del proyecto dentro del vault** a la nueva disciplina (slug único
  si colisiona) y devuelve el nuevo `ProjectRef` (la ventana se re-apunta vía `onOpen`). Las
  disciplinas son solo agrupación interna; el `linkedLocation` real nunca se toca. Guard
  source==dest en `setProjectIconImage` para no recopiar el icono al editar sin cambiarlo.
  *Verificado en disco*: `route-test` migró de `testing/` a `programming/` con sus 4 `.md` intactos
  y el JSON correcto.
- **Sidebar: "+" → "?"**: el botón inferior (que además estaba muerto, no se le pasaba acción) pasa
  a ser **ayuda** → abre `WorkspaceHelpCard`, un popup glass in-app que explica el workspace, ⌘E,
  los atajos y cómo añadir tools. (Nuevo proyecto se hace con ⌘N → ventana nueva en el Greeting,
  nativo de `WindowGroup`.)
- **"?" arriba-derecha → icono Git** (`arrow.triangle.branch`): se identifica como "ir al repo".
- **Bug corregido**: con el editor/ayuda abiertos, las teclas sueltas se filtraban a los atajos
  T/I/F del workspace (los campos del editor no marcan `model.isEditingText`). `handleKey` ahora
  también se inhibe con `editingProject`/`showHelp`.

---

## New Project Panel — ruta del proyecto (faltaba) · Miércoles, 24 de junio de 2026

Lo más importante que se nos había colado: en el creador de proyectos **no había forma de fijar la
carpeta real** del proyecto, así que el Workspace nunca mostraba "Open Folder".

- **Botón "Project route"** encima de `Create Workspace`: abre un selector de carpeta y, una vez
  elegida, el botón muestra su nombre (con icono de carpeta llena). Opcional —un proyecto puede ser
  puro de ideas/tareas— y se puede recolocar tocándolo de nuevo. Conecta `linkedURL` →
  `model.linkedLocation(for:)` → `createProject(... linkedLocation:)` (antes iba `nil` hardcoded).
- **Un único `.fileImporter` con modo** (`importMode = .icon | .folder`): dos importers en la misma
  vista entran en conflicto (solo dispara uno), así que el de imagen y el de carpeta comparten el
  mismo presentador y cambian `allowedContentTypes` y la rama del resultado.
- **Quitado "Press Enter to create"**: redundante (se puede clicar o Enter igualmente) y así gana
  aire el botón de ruta.
- Verificado end-to-end: crear proyecto con ruta → el Workspace muestra **Open Folder** en la
  cabecera (abre por path con `NSWorkspace` en macOS; en iPad la ruta queda como info).

---

## New Project Panel — tipografía Nidus + disclaimer de iconos · Miércoles, 24 de junio de 2026

- **Fuentes a estilo Nidus**: `Project name` y la descripción (`What lives here?`) usaban
  `.system` (San Francisco), que se veía redondeado/playful. Cambiados a **Helvetica Neue** (la
  identidad tipográfica del sidebar): nombre en `HelveticaNeue-Medium` 20, descripción en
  `HelveticaNeue` 13. (Discipline se dejó como estaba; se puede igualar si se quiere.)
- **Disclaimer en el popup de iconos**: bajo `Import image…`, una línea breve y discreta —
  *"Background-free SVG or PNG — it's tinted to one colour."*— para que el usuario sepa de forma
  intuitiva (sin ir al repo) que debe importar un logo sin fondo; cualquier imagen con fondo/colores
  acaba como silueta sólida porque se tiñe a un solo color.
- **Sin barra de scroll en el popup de iconos**: el grid limitaba a 3 filas visibles y, con ~25
  formas, desbordaba → al ser scrollable macOS pintaba la barra (según el ajuste del sistema).
  Ahora `pickerHeight` muestra **todas las filas sin scroll** (tope sano de 8 filas por si se
  meten muchísimos iconos propios) → cero desbordamiento → sin barra.
- **Orden y centrado en el popup**: el **metaball** (el icono por defecto/firma) pasa a ser el
  **primero del todo** de la rejilla (antes iban los built-ins primero). El botón `Import image…`
  se centra (quitado el `Spacer()`), y el **disclaimer** también se centra con
  `.multilineTextAlignment(.center)` explícito — el contenido del `.popover` es una jerarquía
  aparte y **no hereda** el centrado del body de AddProjectView.
- **Jerarquía del campo de intención**: en macOS `.subheadline` ≈ 11pt, así que al poner el texto
  fantasma en Helvetica Neue 13 quedaba más grande que el título. Subido `What lives here?` a
  `system 15 semibold` para que el título vuelva a dominar sobre la línea fantasma.

---

## Greeting Panel — metaball hero que cede sitio a la búsqueda · Miércoles, 24 de junio de 2026

Última depuración estética del Greeting Panel.

- **Metaball "avatar" siempre arriba**: el mismo metaball vivo del Vault Picker (`MetaballView(seed:
  42, avatar: true)`) ahora vive permanentemente sobre el saludo ("Good morning, {nombre}"). Le da
  el toque agradable del inicio en todo momento. El nombre sale de config/usuario (`savedName` →
  `NSFullUserName`), no hardcoded.
- **Cede el espacio al buscar**: al escribir (`isSearching`), el hero **se encoge hasta
  desaparecer** — no fade, sino colapso real de tamaño animando el frame del `Canvas` de 104→0, así
  que además **libera el espacio vertical** y todo sube para que quepan los resultados. Al limpiar
  la búsqueda **vuelve a crecer desde el centro** (spring `response 0.5 / damping 0.82`), mismo
  estilo elegante centro-afuera que el bloom de bienvenida. (`metaballHero` / `heroSize`.)
- **Nombres de proyecto a 2 líneas en recientes**: el label bajo las esferas (`SphereView`) tenía
  `lineLimit(1)` y truncaba títulos cortos ("Brulee Iterations" → "Brulee Itera…"). Ahora
  `lineLimit(2, reservesSpace: true)` + centrado: envuelve hasta 2 líneas (máx) y reserva el alto
  de 2 líneas para que todos los círculos queden alineados. 1–3 palabras razonables ya caben.

---

## Vault Picker — bienvenida primera-vez + metaball vivo · Martes, 23 de junio de 2026

Pulido del panel de primer arranque (`VaultPickerView`) y del motor del metaball.

- **Espaciado reequilibrado**: más aire entre bloques (NIDUS / hero / "Set up your vault" /
  botones / "?"), aprovechando mejor el alto del panel 360×600.
- **Metaball "avatar" más vivo** (`MetaballView(avatar:)`): modo nuevo solo para el héroe del
  picker — más blobs (3–4), más rápidos y **más segregados**, con un *breath* global sutil
  (vibe "Siri/alive"). Los glyphs de proyecto mantienen el modo calmado por defecto.
- **Secuencia de bienvenida (una sola vez)**: al primer arranque sin vault, en el hueco del
  metaball entra con fade/slide *"Hi! First time using Nidus?"*; el **"?" inferior se ilumina en
  accent** un momento; luego el texto se desvanece y el **metaball florece desde la nada en el
  centro hacia fuera** (aglomerándose hasta su tamaño final; `introStart` autocontenido en el
  `TimelineView`, órbita y radio escalados por un `p` smoothstep, así nunca excede su órbita en
  reposo → **sin recorte lateral**) y queda **vivo y centrado**. Persistida con
  `@AppStorage("nidus.intro.welcomeSeen")`.
- **Botón "?" inferior centrado** → abre un **popup glass líquido** ("Welcome to Nidus"),
  cerrable por la X o tocando fuera. Dos bloques en scroll: arriba una **guía práctica para
  novato** (qué es Nidus, crea tu vault primero, crea proyectos enlazados a carpetas reales,
  workspace de una sola pantalla con sus tools, botón de ayuda siempre disponible) — primaria y
  legible sin scroll; debajo, tras un divider, el **blurb condensado estilo repo** (filosofía,
  open-source, datos propios en Markdown, sin nube/subs) en gris pequeño para quien lo quiera.
  *Razón*: quien abre la app por primera vez necesita orientación práctica, no el README.
- **Bug corregido (importante)**: la secuencia se programaba con `.task` + `Task.sleep` y `try?`;
  al re-renderizarse la vista al arrancar, el task se cancela, `Task.sleep` lanza
  `CancellationError`, `try?` se lo traga y **todas las esperas se saltaban de golpe** (saltaba al
  estado final al instante). Reescrita con `DispatchQueue.main.asyncAfter` en tiempos absolutos,
  inmune a re-renders. *(Lección hermana del crash de resize: cuidado con timing frágil ligado al
  ciclo de vida de la vista.)*

> Nota técnica: el build de macOS **no está sandboxed** (entitlements: solo
> `files.user-selected.read-write` + `get-task-allow`), pero existe un Container *stale* de un
> build sandbox antiguo (`~/Library/Containers/ProjectOrchestrator.Nidus`, 20-jun) que confunde a
> `defaults`/cfprefsd al leer prefs. No afecta a la app; conviene borrar ese Container.

---

## Plan readaptado (foundation-first) + pulido del grid · Domingo, 21 de junio de 2026

Decisión: **depurar TODA la base (Greeting + Workspace) antes de entrar a las tools**, para que
las tools hereden una arquitectura ya estable y no haya que migrarlas. Plan reordenado:
- **Fase A — base impecable (2 capas)**: A1 infra Workspace (esto), A2 Greeting Panel
  (cambios previstos + pulido), A3 estética base (gradientes de color editables, etc.).
- **Fase B — tools una a una** sobre la arquitectura estable (+ editor Markdown + share info).
- **Fase C diferido**: deadlines + Deadline Calendar, watcher externo, extensión Raycast.

### Ordenado más inteligente del grid (A1)
- **Memoria de tamaño**: al re-adjuntar una instancia desde la library, intenta primero su
  ÚLTIMO tamaño; si no cabe en el hueco, cae al más parecido que sí (`NidusModel.attachTool`).
- **Detección por cursor**: el swap se detecta por la celda **bajo el cursor** (coordinate space
  `nidusGrid`), no por la traslación redondeada → ya detecta bien pequeña→grande y laterales.
- **Adaptación reactiva**: al arrastrar sobre un tile de distinto tamaño, el arrastrado **empieza
  a adoptar el tamaño destino** (preview animado del swap-con-resize).
- **Placeholder vivo**: al levantar un tile, su hueco aparece **al instante** (el grid se siente
  pre-ubicado, no surge de golpe al aterrizar) — el tile arrastrado se excluye de la ocupación.
- **Glare del placeholder**: al pasar el cursor por todo el área de un hueco, el placeholder
  entero reacciona (borde + relleno + "+" se iluminan), no solo el círculo.
- Movimiento a hueco vacío: traslación (mantiene el "grab feel"); swap: celda del cursor.

### Drag/resize — segunda pasada de afinado (A1)
- **Resize-to-fit al soltar**: si sueltas un tile en un hueco donde su tamaño actual no cabe pero
  sí un tamaño válido menor, se redimensiona al mayor que entra y se coloca (gradual, no de golpe)
  — `shrinkToFitDetail`.
- **Haptic magnético**: al entrar en una celda destino válida (swap o hueco válido) salta un tap
  háptico, una sola vez por celda.
- **Anclaje a esquina natural** al encoger por el menú de resize: un tile pegado al borde derecho
  tiende a la derecha; al izquierdo, a la izquierda; interior mantiene su origen (peso izquierdo).
- **Adaptación reactiva refinada**: (a) **hover delay** (~0.5s) — nada ocurre al sobrevolar, se
  puede barrer libremente; (b) **soft morphism** — el tile no muestra la forma final sino ~20% del
  camino hacia ella (shape intermedia viva); al soltar termina de morfear con muelle, no de golpe.

### Drag/resize — tercera pasada: reflow + detección por cursor (A1)
- **Detección por el rectángulo del cursor** (`tile(at:)` / `swapPartnerAt`): si el ratón está
  sobre el tile (todo su área), cuenta — adiós a "no detecta hasta cierta parte" en pequeña→grande.
- **Resize-to-fit solo encoge**: `shrinkToFitDetail` filtra a tamaños ≤ el actual. Un 1×1 ya no se
  auto-expande a 1×2 en un drop fallido.
- **Reflow / reorganización** (`reflowPlacement`, backtracking en el grid 5×2): al soltar donde no
  cabe el tamaño completo y no hay swap, reorganiza a los vecinos (sin redimensionarlos) para
  abrir hueco al tamaño completo del arrastrado. Candidatos ordenados por **menor movimiento** y
  hacia el **lado más holgado** (desempate izquierda). Si no se puede empaquetar → resize-to-fit.
- **Prioridad al soltar**: 1) mover a hueco vacío · 2) **swap** (gana si el tile es intercambiable)
  · 3) **reflow** · 4) resize-to-fit · 5) vuelve.
- **Amago de los vecinos**: tras el hover delay, los tiles que se moverían hacen un preview del
  ~20% hacia su nueva posición (`reflowGhost`); al soltar completan el movimiento con muelle.
- **Commit suave**: en el commit, `base→nueva` y `translation→0` animan sincronizados (el
  arrastrado queda quieto) mientras vecinos / partner de swap se reacomodan con muelle.
- **Más reactivo**: hover delay 0.5→**0.3 s**.

### Top bar reestructurado (A3 — estética del workspace fuera del grid)
Según mockup del usuario. El `topZone` de WorkspaceView pasa a 3 zonas:
- **Izquierda — card de proyecto +20%** (440×150 → 528×180): sphere/logo más grande, nombre,
  disciplina, **descripción** (placeholder "Add a description…" si está vacía, editable luego en
  el panel-editor), y **Open Folder más grande** (controlSize `.regular`).
- **Centro-derecha — slot de tool anclado landscape** (400×180): único hueco de tools de overview
  (calendar, pomodoros, abrir carpetas, links…). Ahora maqueta el Deadline Calendar partido en
  **mini-mes** (mes actual real, hoy marcado) + **lista de next deadlines** (estilo Reminders,
  vacía). Pasivo hasta T2.4c.
- **Borde derecho — columna de 4 botones circulares** + wordmark **NIDUS**: Toggle · Customize
  (⌘E) · Search tools (llave → GitHub) · "?" About (→ GitHub). Enlaces = placeholder a
  `github.com/ParamoStudio/Nidus` vía `openURL`.
- Hueco central flexible (`Color.clear`) = el respiro que crece en ventanas anchas.

### Vault picker — fixes (verificado en vivo)
- **Create no hacía nada** → eran **dos `.fileImporter` en la misma vista** (SwiftUI solo respeta
  uno; locate ganaba). Unificado en **un solo `fileImporter` + `mode`**. Ahora Create abre el
  diálogo y crea/transiciona al greeting (verificado).
- **Ventana enorme** → el picker se mostraba con `isPanel=false`. Ahora `isPanel = openProject==nil`
  (picker + greeting son panel pequeño). `WindowConfigurator` acepta `panelSize` y redimensiona
  (no animado, seguro) también al cambiar de tamaño: **picker 420×460**, **greeting 360×600**.
- Picker reestilizado con estética greeting (NIDUS, glass, botones capsule; Create accent-tinted).

### Primer arranque del vault: Create / Locate + marcador de validez
- **Marcador de validez** `.nidus-vault` (token constante `nidus-vault-v1`) que Nidus escribe en
  cada vault que crea (en `ensureConfigExists`). Open-source → no es un secreto real, solo un
  marcador para no apuntar a una carpeta cualquiera por error. `VaultStore.isValidVault(at:)`.
- **`restore()` ahora valida**: si la carpeta del vault no existe o no tiene marcador, **olvida el
  bookmark** y lanza `notAVault` → primer arranque limpio (antes `ensureConfigExists` la **re-creaba
  en silencio** — por eso "revivía" en Descargas).
- **`VaultPickerView` con dos opciones**: **Create new vault…** (elige ubicación → Nidus crea
  `NidusVault` con marcador) y **Locate existing…** (elige una carpeta NidusVault; se rechaza si no
  lleva el marcador, con mensaje claro). `model.openExistingVault(at:)` + `VaultStore` bookmarkea
  el vault directo (flag `direct`) vs el parent (create).

### Picker que se ajusta + carpeta `_icons/` de usuario en el vault
- **Popover del picker**: alto se ajusta al nº de iconos (hasta 3 filas de chips); si hay más,
  **scroll sin barra** (`scrollIndicators(.hidden)`). `pickerHeight` calcula filas visibles.
- **Carpeta `_icons/` en el vault** (se crea junto a `_inbox-global/` en `ensureConfigExists`): el
  usuario suelta ahí sus **SVG/PNG** y aparecen en la **biblioteca de iconos** del picker
  (`VaultStore.userIconFiles()` → `model.userIcons`). Se renderizan **monocromos** (template
  `.primary`, adaptan a dark/light) y, al elegirlos, se importan rasterizados a 256px en el proyecto.
- `setProjectIconImage` rasteriza a **256px** (preserva alpha) — soporta SVG (vía NSImage en Mac).

### Iconos: 14 Bauhaus + imágenes importadas monocromas (integradas como la app)
- Bauhaus: quitados **corazón** y **círculo lleno** → **14** formas (ring, dome, crescent, leaf,
  quatrefoil, flor-6, peanut, sparkle, teardrop, target, pill, cluster, wave, elipse).
- **Imágenes importadas como template**: se renderizan con `renderingMode(.template)` tintadas a
  `.primary` (blanco en dark / negro en light) → un logo custom se integra exactamente como los
  glifos. (Funciona ideal con logos con transparencia; una foto opaca queda como silueta sólida —
  si hace falta soportar fotos, haría falta un pase de monocromizado por luminancia.)
  Se renderiza fit + inset como los demás glifos (ya no contenida/a color).

### Iconos: set Bauhaus orgánico + imagen llena el círculo + Enter crea
- **Glifos Bauhaus → orgánicos** (16, antes 20): fuera los cuadrados/picos (rounded-square, plus, X,
  diamante, triángulo, chevron, zigzag, staircase, starburst). Dentro redondos: circle, ring, dome,
  crescent, leaf, quatrefoil, flor-6, **peanut**, **sparkle 4-puntas cóncava**, teardrop, heart,
  target, pill, cluster-3-bolas, wave, elipse. (Dirección que pidió el usuario.)
- **Imagen importada LLENA el círculo** (antes quedaba contenida): `ProjectGlyph` con `circled` →
  imagen rellena el `size` completo y clipa a círculo; metaball/bauhaus quedan insetados (0.72).
  Call sites pasan el diámetro completo. En el add, la imagen ocupa el círculo de 84.
- **Imagen en greeting**: greyscale + ligera translucidez (opacity 0.9) → "integrada"; color en workspace.
- **Enter en "What lives here?" crea** el workspace (`onKeyPress(.return)`), ya no se queda colgado.

### Picker de icono: 20 glifos Bauhaus + import de imagen + metaball más vivo
- **20 glifos Bauhaus** (`BauhausIcon`): recreados **proceduralmente** con `Canvas` (no extraídos de
  la imagen — vectorizar píxeles no sale fiable), monocromos y de alto contraste. Sin assets.
- **Picker** (popover bajo el icono): botón **Import image…** + chip para mantener el metaball +
  rejilla de los 20 Bauhaus. Selección → `iconChoice`.
- **Import de imagen**: `fileImporter` → al crear se guarda re-encodeada a PNG en la carpeta del
  proyecto (`.nidus-icon.png`, `model.setProjectIconImage`), `icon = "image"`. Se muestra
  **center-cropped a círculo**: en **color** en el Workspace, **monocromo** en el Greeting.
- `ProjectGlyph` unificado ahora resuelve metaball / bauhaus / imagen / SF Symbol; recibe
  `folderURL` + `monochrome`. Propagado a `SphereView`, resultados de búsqueda y sphere del workspace.
- Metaball: menos bolas más grandes + órbitas amplias → más separación/viscosidad (verificado).
- "What lives here?": línea baseline + ghost original en 2 líneas, sin caja (verificado en vivo).
- (Carpeta `project-icons` antigua: ignorada, no gusta.)

### Metaball afinado + "What lives here?" corregido + DerivedData limpio (verificado en vivo)
- **DerivedData**: borradas las 3 carpetas `Nidus-*` duplicadas (Xcode regenera una limpia) — eran
  la causa de ver builds viejos al verificar.
- **Metaball más separado/viscoso**: menos bolas (central + 2–3) pero más grandes y con **órbitas
  más amplias** (0.20–0.38) + blur 0.095 → se identifican como masas distintas, se estiran en necks
  y se separan/juntan (fiel a la referencia). Verificado en vivo (zoom: forma de 3 blobs con neck).
- **"What lives here?"**: revertido el rectángulo → **línea baseline** + ghost original
  ("one single line to keep focused on the project when you most need it") que ocupa **2 líneas**
  sin cortarse y desaparece al escribir; campo crece a 3 líneas y luego scroll.

### Metaball VIVO + fulgor + "What lives here?" acotado (verificado en vivo)
- **`MetaballView` ahora anima** (era estática): blobs en órbita con frecuencias distintas, fusión/
  separación gooey vía `TimelineView` (~30fps). Verificado en vivo (el blob cambia de forma).
- El botón bajo el metaball **ya no aleatoriza**: es la **entrada al picker** (icono `photo`) para
  elegir icono/imagen — el metaball animado es el DEFAULT. (Picker completo = paso siguiente.)
- **`GlowingRing`**: anillo con fulgor suave y pulsante en los círculos de icono (SphereView + add)
  → sensación de presencia/actividad effortless.
- **"What lives here?"**: label más grande (subheadline semibold) que el ghost; celda **multilínea
  acotada** (2–3 líneas, fondo sutil) — el texto ya no se sale por la derecha.
- Enter en nombre/disciplina crea (si válido).

### Icono de proyecto: metaball procedural (decisión del usuario)
- Nuevo `MetaballView(seed:)`: blobs borrosos fusionados con `alphaThreshold` en una silueta gooey,
  determinista por semilla, alto contraste (casi negro en claro / casi blanco en oscuro). Honestidad:
  es un look 2D líquido, no el 3D clay de los renders (el usuario lo eligió aun así).
- `ProjectGlyph(icon:size:)`: render unificado — si `project.icon` es `"metaball:<seed>"` dibuja el
  metaball; si es nombre de SF Symbol, dibuja el símbolo. Usado en greeting recents (`SphereView`),
  resultados de búsqueda, y el sphere del proyecto en el workspace.
- `AddProjectView`: el icono es un metaball con semilla aleatoria; el botón (dado) la **baraja**.
  Al crear se guarda `icon = "metaball:<seed>"` (estable). El picker completo (import imagen +
  recorte + banco) es el **paso siguiente**.

### Greeting + Add — pulido estético (verificado en vivo, sin crash)
- **Panel más estrecho y largo**: 410×540 → **360×600** (extrapolado de la referencia del usuario).
- **Círculos de icono casi transparentes**: `SphereView` y el icon-sphere del add pierden el fill
  blanco/frosted → solo un **borde tenue + glare**; el **glyph a `.primary`** (casi negro en claro,
  casi blanco en oscuro) = mucho más contraste. Recents a diameter 52 para caber en 360.
- **Add reestructurado como ritual** (estructura del mockup): NIDUS izq + **X** (cancel) dcha;
  icono transparente; "NEW PROJECT"; **"What are you building?"**; **nombre** (celda prominente,
  el momento); **disciplina** typeahead **discreta** (elige/crea); **"What lives here?"** + una
  sola línea sutil (ghost), fuera el bloque fantasma; botón **Create Workspace** + "Press Enter to
  create". Enter crea.

### Fix crash al abrir add-project (NSException) — solución definitiva
- Causa (report de Apple): redimensionar la ventana del panel desde SwiftUI durante el ciclo de
  layout revienta: `NSHostingView.updateAnimatedWindowSize → -[NSThemeFrame setFrameSize:] →
  _postWindowNeedsUpdateConstraints` → **NSException** (re-entrante). `.resizable` NO lo arregló.
- **Fix de raíz: no redimensionar la ventana del panel.** Eliminado todo el resize dinámico
  (`animateHeight`/`panelHeight`/plumbing). El Greeting es un **panel de tamaño fijo** (410×540),
  igual mecanismo que la transición panel↔workspace (que nunca crasheó). El morph `.blurReplace`
  no cambia el tamaño, así que no entra por ese camino.
- Consecuencias UX: los **resultados de búsqueda hacen scroll interno** (maxHeight 240) en vez de
  crecer la ventana; el bloque del Greeting se **centra verticalmente** (search ~al centro). El
  add-form entra holgado en 540.
- Endurecido aparte: pulso de la search con `TimelineView` (no `repeatForever`); fuera
  `contentTransition(.symbolEffect)`.

### Add-project — morph en la misma superficie (fase 1)
Nuevo `AddProjectView`. El Greeting **morfea con blur** hacia él (`.transition(.blurReplace)`,
sin sheet/popup); Cancel morfea de vuelta, Create crea+abre (cierra el Greeting). El panel crece
animado a ~600 para la forma. Layout centrado: **icono sphere** (SF Symbol aleatorio + dropper
→ popover con set curado de iconos), subheader "New project", título "What are you creating?",
**celda typeahead de disciplina** (escribir → sugiere existentes / crea nueva al confirmar),
**celda de título** (más grande/gruesa), **descripción sin celda** con ghost amable, y botones
**Cancel/Create** (glass pill reactivos, Create deshabilitado hasta válido). Celdas = glass exacto
del Greeting (capsule ultraThinMaterial + borde). `createProject` ahora guarda **descripción +
icono**. Folder de trabajo: fuera de este panel (se vincula luego). Iconos fase 1 = SF Symbols
curados; **banco de 180 SVG + import de imagen custom = siguiente paso**.

### Greeting Panel — tercera ronda de correcciones
- **Nombre editable**: el foco ahora aparece al instante con el doble-click (`nameFocused` en el
  siguiente runloop vía async — SwiftUI no enfocaba un campo recién creado).
- **Recents centrados**: la fila de circles se centra en el panel (`.frame(maxWidth:.infinity)`),
  etiqueta a la izquierda.
- **Tipografía del saludo**: "Ready when you are." 29→**32pt, weight .medium, `.primary`** (más
  impacto/contraste); salutation 14→**15** y `.primary` 0.7.
- **Resize más suave**: contenido `.clipped()` al marco (oculta el solape momentáneo durante la
  animación de alto) + transición de opacidad en el cambio resultados↔recientes.

### Greeting Panel — segunda ronda de correcciones
- **Más estrecho**: panel 440→**410** ancho; recents más juntos (spacing 8, `SphereView` frame
  `diameter+18`) y search más corta (sigue el ancho del panel).
- **Alto dinámico animado**: la ventana **crece** con los resultados y **vuelve al original** al
  borrar, con animación (`WindowConfigurator.animateHeight` vía `NSWindow.animator().setFrame`,
  top anclado; `GreetingPanelView` reporta `desiredHeight` → `RootWindowView` → configurator).
- **Aún más translúcida**: tinte del panel dark ~0.30 (era 0.40).
- **Saludo más contraste**: "Ready when you are." a `.primary` 0.95 y **29pt** (+~5%); salutation
  a `.primary` 0.6.
- **Nombre editable in-situ**: doble-click en el nombre → lo borra, cursor (accent) esperando,
  escribes, **Enter fija y guarda** (`@AppStorage "nidus.userName"`, local). Sin popups. ESC cancela.
- **Flechas ↑/↓ navegan los resultados** (no el cursor del texto) vía `onKeyPress` (consumidas);
  Enter abre el seleccionado; hover mueve la selección.
- **Resultados en capsule** (a juego con la search bar): selección translúcida + fulgor accent
  sticky.

### Greeting Panel — correcciones tras feedback
- **Más glass**: `AmbientBackground(reduced:)` baja la opacidad del tinte en el panel (dark ~0.40
  vs ~0.78) y se quitó el frost → el escritorio difuminado se reconoce a través. Lo activa
  `RootWindowView` con `isPanel`.
- **Más snug**: panel 440×640 → **440×460** (recorta el padding vertical sobrante; ancho intacto
  para las 4 circles).
- **Circles**: fulgor **siempre presente** que crece al hover (no de nada→algo).
- **NIDUS**: fuera el emboss (ilegible) → dark-grey legible, **arriba-izquierda alineado con los
  botones** de la derecha.
- **Saludo**: subrayado, +5%, **centrado** sobre…
- **"Ready when you are."**: vuelto al original — **centrado, mayúscula, 27pt** (más impactante).
- **Pulso de la search**: más visible y profundo mientras está en uso (`glowActive` = focused/typing).
- **Fuzzy search inteligente** (`searchProjects`): matchea por nombre de proyecto **y de
  disciplina** (fuzzy); escribir "ceram" trae proyectos de Cerámica por recencia aunque el nombre
  no contenga "ceram". Name-match siempre por encima. Resultados: selección **translúcida + fulgor
  accent sticky** (fuera el naranja sólido), **navegable con flechas + Enter**, hover mueve la
  selección. (Todo en memoria sobre el config — sin necesidad de `fd`.)

### Greeting Panel — remake minimalista (según mockup del usuario)
Reescrito `GreetingPanelView`. Punto de entrada mínimo, keyboard-first, glass.
- **Fuera disciplinas**: sección de disciplinas + orbit watchOS + máquina de estados de hover +
  `DisciplineAnchorKey` + `OrbitClusterView` eliminados.
- **NIDUS** top-left, azul-grís profundo, **embossed** (shadow blanco y:1).
- **Saludo humano**: subheader "Good morning/afternoon/evening, <nombre>" (detecta franja horaria
  + `NSFullUserName` en Mac) sobre **"ready when you are."** grande, left-aligned.
- **Search viva**: cápsula glass con **pulso azul** que respira (repeatForever) y **se intensifica
  al escribir** (`glowOpacity`/`glowRadius` reaccionan a `isSearching`).
- **Separador** con fulgor + **recientes** (botón "+" y 3 últimos abiertos) con `SphereView`.
- **Arriba-derecha**: toggle claro/oscuro + **"?"** → GitHub (placeholder `openURL`).
- **Glass**: frost ligero (`ultraThinMaterial` .3) sobre el ambient azul/blanco — ignora el
  escritorio sin depender de él.
- **SphereView**: hover más *sticky* (muelle, scale 1.06), borde radiante + fulgor blanco.
- **Panel** más estrecho: 480×660 → **440×640** (no redimensionable, así que "se ajusta/vuelve"
  queda cubierto).
- Iconos de las circles: placeholder (SF Symbol actual); el **banco de 180 SVG** + auto-asignación
  llega con el add-project panel.

### Sidebar — pulido final de las cards de proyecto
- Forma de la card de proyecto: de `RoundedRectangle` opaco a **liquid glass `.clear` interactivo
  en `Capsule`** (fully-rounded squircle) — casi inexistente en reposo, se ilumina en hover,
  tintada con accent cuando está activa.
- **Fulgor del nombre** ahora en **accent color** (no blanco) en hover — contraste cálido sutil.

### Sidebar — afinado de jerarquía y aire
- **NIDUS** vuelve a pequeño: subheader centrado arriba (HelveticaNeue-Medium 11, tracking 3),
  sustituye al header "Projects" (quitado).
- **Más aire** entre NIDUS y la primera disciplina (padding 30).
- **Títulos de disciplina**: **HelveticaNeue-Thin** 18, uppercase + tracking — fina, en la línea
  de NIDUS pero más ligera.
- **Cada proyecto, su propio espacio**: card sutil por proyecto (`white .035`, hover `.09`,
  activo `.10`, radio 10), HelveticaNeue 14 (Medium si activo). Mantiene el fulgor + nudge a la
  derecha en hover. Ya no es una lista plana.

### Sidebar — menos plano, más jerárquico y reactivo
- **Jerarquía tipográfica** NIDUS (18, bold, tracking 3) > **disciplina** (16, bold, uppercase,
  tracking 1.2, estilo NIDUS) > **proyecto** (14, medium). NIDUS sigue centrado arriba.
- **Separadores entre disciplinas**: línea sutil (`white .14`) con un ligero **fulgor** (shadow).
- **Proyectos reactivos al hover**: el nombre **brilla** (radiance, shadow blanco suave), pasa a
  primario y se **desplaza ~5px a la derecha** ("you're about to select me"), con muelle.
- **Botón "+" nuevo proyecto**: **centrado**, más grande (46), glass interactivo + scale en hover.
  Llama a `onNewProject` (placeholder hasta construir el panel de nuevo proyecto).
- Resto del sidebar intacto.

### Top bar — segunda ronda de correcciones
- **Mínimo de ventana reforzado**: `contentMinSize` (1240×820) se re-aplica en CADA update (SwiftUI
  lo reseteaba), así que ya no se puede arrastrar a estado estrecho. **Red de seguridad**: si aun
  así baja de 1160×720, el workspace se **difumina (blur 18)** y aparece *"Make the window bigger"*.
- **Full screen — padding inferior**: quitado el cap de altura de celda del grid
  (`maxCellHeight: .infinity`) → el grid **usa el espacio de abajo** en lugar de dejar hueco muerto.
- **Top bar no roza los controles**: `.padding(.top)` 18→30 — el wordmark del title bar ya no toca
  el toggle/calendar en full screen.
- **NIDUS en el sidebar**: wordmark centrado arriba del panel de proyectos.

### Top bar — correcciones tras feedback
- **Bug del grid (crítico)**: el `Color.clear.frame(maxWidth:.infinity)` se expandía también en
  vertical e inflaba el top band, aplastando el grid. Sustituido por `Spacer(minLength:16)`
  (horizontal) + el top band **fijado a 180** para que el grid de abajo NO se toque nunca.
- **Wordmark NIDUS** movido al **title bar real** (a la derecha) vía `NSTitlebarAccessoryViewController`
  (`layoutAttribute = .trailing`), fuera del layout — ya no va encima de los botones ni desplaza
  espacio útil. (macOS; en iPad no hay title bar.)
- **Tamaño mínimo funcional**: `contentMinSize` del workspace = 1240×820 (default 1320×880) — la
  app ya no escala a estados apretados.
- **Botones reactivos otra vez**: `IconButton` recupera reacción en hover (scale 1.12 con muelle)
  y todo el círculo es clicable (`contentShape(Circle())`), no solo el símbolo.

**Siguiente (pendiente)**: panel-editor de proyecto compartido greeting↔workspace (botón "+"/editar
en Customize Mode), con logo de imagen custom + selector de los 180 iconos prefab de
`Xcode/project-icons` (importar SVG al asset catalog), nombre, descripción y ruta.

### Reflow sin cascada (A1 — afinado)
- El reflow ya **no re-empaqueta todo el grid**. Modelo nuevo: **solo el vecino directamente
  tapado** se aparta a su hueco libre; los tiles que `a` no toca **nunca se mueven** (reservados)
  → adiós a las reorganizaciones masivas en cadena. El amago (`reflowGhost`) ahora solo afecta al
  vecino que de verdad se mueve.
- **Decisión de tacto (usuario)**: entre las celdas cercanas al drop, el reflow elige la que hace
  que el vecino **viaje lo mínimo** (coste = movimiento del vecino + distancia de `a` al drop;
  desempate por menor movimiento del vecino). Caso Task·Ideas(2×2)·Inbox → soltar Inbox sobre
  Ideas deja Inbox entre Task e Ideas e Ideas solo se desplaza 1.
- Nueva prioridad al soltar: 1) hueco vacío exacto · 2) swap · 3) **reflow sin cascada** ·
  4) **hueco vacío más cercano** (nadie más se mueve) · 5) resize-to-fit · 6) vuelve.

### TidyScroll endurecido
- Se reemplaza el `GeometryReader` en `.background` + PreferenceKey por **`onGeometryChange`**
  (mide la vista directamente, sin doble pase de layout) — para erradicar el parpadeo/solape de
  texto intermitente detectado tras quitar la scrollbar. (Vigilar si reaparece.)

---

## Arquitectura Customize — Sub-paso A (instancias) + B (library) · Domingo, 21 de junio de 2026

Foundation-first: definir bien Customize antes de pulir tools. Decisión del usuario sobre
archivos: el `.md` se llama como la tool (sufijo en duplicados) y lleva DENTRO su contexto.

### Modelo de instancias (A)
- `ToolSlot` evoluciona a **instancia**: `id` estable, `tool` (tipo), `name` custom opcional,
  `files` resueltos. Decodificación tolerante (configs viejas siguen leyéndose).
- **Cabecera autodescriptiva** en cada `.md`: `# <name>` + `Tool: <tipo>` + `Tool name: <name>`
  (legible sin Nidus; la LLM entiende el contexto). El parser la salta.
- `ToolContext.fileMap` (declarado→resuelto): dos instancias de "Ideas" escriben en archivos
  distintos (ideas.md, ideas-2.md). `NidusModel.addTool` resuelve id+archivos únicos, crea los
  `.md` con cabecera, y **permite duplicados**; los duplicados salen numerados ("Ideas 2") hasta
  el rename.
- `ToolDescriptor` declara ahora `defaultName`, `summary` (qué hace) y `allowsMultiple`
  (Inbox = singleton). Inbox no eliminable ni duplicable.

### Library (B)
- `ToolLibraryPanel`: panel **Liquid Glass** (vía overlay, no sheet) con lista de cards; cada
  card lee del descriptor: **nombre + descripción + tamaños en pills**. Sin hardcode.
- El **hueco vacío entero** es el botón de añadir: "+" grande, glass, reactivo (`.glassEffect`).

### Drag (C) + Resize (D)
- **C — Drag para mover**: en Customize, arrastras una tile; sigue al cursor (scale + sombra) y
  al soltar va a la celda destino (redondeo a la rejilla). Valida límites y solapes; si el destino
  lo ocupa una tile del **mismo tamaño**, hace **swap**; si no cabe, vuelve. Persiste con spring.
  (`onCommitGrid` → `NidusModel.setGrid`.)
- **D — Resize**: tirador glass en la esquina inferior-derecha (solo si la tool tiene >1 tamaño).
  Arrastras y **ajusta al tamaño válido** más cercano (1x1/1x2/2x2; no existe 2x1). Solo confirma
  si cabe (límites + sin solape). Preview en vivo.

### Correcciones de uso + rename (cierre de la arquitectura)
- **#1 Drag/resize no iban**: el drag movía la VENTANA (`isMovableByWindowBackground`). Ahora eso
  solo aplica al panel flotante del Greeting; en el Workspace está off → la tile entera se arrastra
  como contenedor (y el tirador de resize funciona).
- **#2 "Ad infinitum" al reañadir**: borrar dejaba el `.md` en disco y reañadir creaba ideas-2, -3…
  Solución: al borrar, la instancia pasa a **`detached`** (no se pierde). El panel ahora separa
  **Template tools** (tipos → instancia nueva) y **Project tools** (instancias usadas y quitadas,
  por su **nombre**, re-adjuntables sin duplicar). Inbox singleton.
- **#3 Rename**: lápiz en la tile (Customize) → diálogo; actualiza el título y reescribe la
  cabecera del `.md` (`# <name>` y `Tool name:`), sin tocar tipo, archivo ni contenido. Probado.

### Pulido de Customize (feedback)
- **Drag desde todo el contenedor** (no solo el icono): `.contentShape(Rectangle())` en la tile.
- **Animación del soltar**: ya no vuelve al origen para luego moverse. Desliza **desde donde
  sueltas** hasta la celda (spring) y commit silencioso (sin salto).
- **Nombres centrados y más grandes** (icono + nombre `.title3`, centrados arriba). Pencil (rename)
  y ✕ (quitar) pasan a **overlays simétricos** (arriba-izq / arriba-dcha).
- Cards del panel library más translúcidas (acorde al glass general).

### Pulido de Customize (2)
- **Resize MAGNÉTICO** (el libre relayout-eaba cada frame → lag): el drag elige el tamaño válido
  más cercano (umbral de media celda) y la tile **springa** a él; **commit inmediato al soltar**
  (ya está en un tamaño válido). Haptic al cruzar de tamaño; handle con `minimumDistance:2` +
  `highPriorityGesture` para no confundirse con el drag. Sin relayout por frame → fluido.
- **Señal "would move"**: al arrastrar sobre una tile del mismo tamaño que se intercambiaría,
  esa tile **encoge + se atenúa** (Apple-icon-style), sin reorganizar todo el grid.
- **Levitate tras mover**: el commit del drag no usa `disablesAnimations`; la tile sigue levitando.

### Resize por MENÚ de tamaños (se abandona el drag-resize)
- El drag-resize fluido relayout-eaba cada frame (lag, vibración, se resistía). **Sustituido por
  un selector**: el botón de resize (Button redondo entero, glass `.interactive()` con reacción al
  hover — fácil de pulsar, no se confunde con el drag) abre un **menú glass** con las **formas
  disponibles** (cuadrado/ancho/alto/grande). Elegir → **snap inmediato** (spring).
- **Disponibles = tamaños válidos del tool ∩ los que caben** según huecos vacíos contiguos
  (reusa `resized()`). Añadido **2x1 (ancho)** al modelo y a los tools.
- **Levitate re-kick** (`levitateKick`) tras mover/redimensionar: ya no se apaga al mover.
- Pendiente (anotado): swap en drag entre tools de **distinto** tamaño con resize mutuo.

### Resize multidireccional + swap con resize + scroll sin barra
- **Resize en cualquier dirección con pesos**: `resized()` crece hacia derecha/abajo si hay hueco
  (prioridad), y hacia izquierda/arriba si solo hay ahí. El menú muestra más tamaños disponibles.
- **Swap con resize entre tamaños distintos**: arrastrar un tool sobre otro de distinto tamaño,
  si **ambos admiten** el tamaño del otro, los intercambia **y redimensiona** a sus huecos
  mutuos. La señal "would move" también lo refleja. (`placed()` / `swapPartner()`.)
- **`TidyScroll`**: barras de scroll fuera. En su lugar un **"…" muy sutil** abajo (pill glass)
  cuando hay más material; aplicado a las listas de tools. Paneles con indicadores ocultos.
  (Gestión de espacio — sin clutter.)

### Estado
- Customize **completa y pulida**: drag (settle + swap con resize), resize por menú multidireccional,
  templates + project tools (sin duplicar), rename. Siguiente: **pulir las tools** una a una.

### Verificación
- `xcodebuild` macOS + iOS → **BUILD SUCCEEDED**. Parser de metadata probado en aislado.

---

## GIRO: editor visual de Markdown — Fase 0.1 (sistema glass) · Sábado, 21 de junio de 2026

Reenfoque foundation-first (ver memoria). La mayoría de tools = instancias de un "notes tool"
genérico **duplicable/renombrable**; **Inbox = madre singleton** que enruta; cards con expanded
view **tipo-específico** + menú "Move to…". Norte visual: render del usuario.

### Fase 0.1 — Sistema glass + ambiente (primer pase)
- `GlassStyle.swift`: `glassCard(frosted:)` (material + borde hairline + sombra suave, radio
  continuo 20) y `AmbientBackground` (gradiente cálido→frío contenido + bloom azul, variantes
  claro/oscuro). El glass ahora vive sobre el **ambiente propio de la app** (como el render),
  no sobre el escritorio.
- Aplicado a: tiles, tarjetas de identidad/overview, panel de Ideas, command palette, quick add.
- Tile: badge de tamaño solo en Customize; títulos algo más fuertes; más padding.
- (Inmediatas previas incluidas: **levitación** de vuelta —ya sin parpadeo por `.id`— y **onda**
  difusa diagonal con gaussian blur y cola larga.)

### Verificación
- `xcodebuild` macOS + iOS → **BUILD SUCCEEDED**.

### Fase 0.1 — correcciones (mockup = fuente de verdad estética)
- **#2 Parpadeo (causa raíz real):** los 4 tools ya **leen su lista del archivo en cada render**
  (computed, sin `@State` de datos), así que recrear el `AnyView` nunca muestra estado vacío.
  La **levitación se mantiene** y ya no parpadea.
- **#4 Borde refractivo:** `glassCard` lleva un rim especular (gradiente claro arriba-izq.) →
  las tools se identifican mejor sobre el ambiente monocromático.
- **#3 Sidebar hacia el render:** glass más clear, barra de acento en el proyecto activo,
  cabeceras de disciplina sutiles, "…" arriba y "New project" abajo, borde refractivo.
- **#1 Onda visible:** barrido diagonal translúcido (TR→BL) que se ve, conmuta el tema **debajo**
  a su punto álgido y se retira. (El cambio de esquema en sí es instantáneo en SwiftUI; la onda
  lo enmascara — un crossfade real necesitaría snapshot AppKit, anotado por si lo quieres luego.)

### Fase 0.1 — correcciones 2
- **#6 BUG full-screen (crítico):** la app ya no abre en full-screen. `WindowConfigurator` fuerza
  salir de full-screen al arrancar y desactiva la restauración de estado (`isRestorable = false`).
- **#1 Onda azul:** la onda usa el azul eléctrico (ZERONODE) que se ve sobre claro Y oscuro
  (antes el wash blanco→fondo claro era invisible y parecía instantáneo). Más lenta y con cola
  larga; conmuta el tema bajo el bloom en su punto álgido.
- **#2 Sidebar fiel al mockup:** más estrecha (196), pure glass translúcido (se ve detrás),
  "…" arriba, "+" pequeño abajo, barra de acento en el activo.
- **#4 Borde refractivo suavizado.**
- **#5 Modo claro menos monocromático:** más presencia de bloom azul (ZERONODE) en el ambiente
  para que las tools glass resalten.

### Fase 0.1 — correcciones 3
- **#1 Toggle = fade general suave** (sin expansión radial): disolución a pantalla completa a
  través del tono (negro/blanco), conmuta bajo cobertura total, calmado (~0.5s + 0.55s).
- **#4 Translucidez de vuelta:** `GlassBackground` (desktop difuminado) de base + `AmbientBackground`
  como **tinte translúcido** encima (base con alpha ~0.62–0.78). Se vuelve a ver el wallpaper.
- **#2 Sidebar:** más estrecha (168) y **legible** (`.regularMaterial`, no el 0.6 que costaba leer).

### Fase 0.1 — correcciones 4
- **#2 Toggle = crossfade del fondo, sin tapar:** quitado el overlay opaco que dejaba la pantalla
  en negro/blanco total. Ahora `ThemeController.darkness` (0..1) se anima y `AmbientBackground`
  **interpola** sus colores → el fondo cruza oscuro↔claro suavemente. El esquema (materiales/texto)
  conmuta una sola vez a mitad del fade. El contenido se ve todo el rato.
- **#1 Sidebar punto medio:** `.thinMaterial` (entre el frosted opaco y el demasiado translúcido).

### Fase 0.1 — correcciones 5
- **Sidebar** → `.ultraThinMaterial` (más translúcida, se ve detrás).
- **Toggle** más lento/gradual (crossfade del fondo 1.2s, conmuta a 0.55s).
- **Tarjeta de proyecto al mockup:** tamaño fijo 440×150, esfera glossy, jerarquía nombre/desc/
  disciplina, **"Open Folder" como pill**; back movido a un botón redondo a la izquierda; top zone
  con la tarjeta a la izquierda y controles+calendario a la derecha, con aire entre medias.

### Fase 0.1 — correcciones 6
- **#1 Toggle = crossfade real por snapshot (macOS):** se captura la apariencia actual, se conmuta
  el esquema debajo, y la captura se **funde** (0.55s). Cards, texto y fondo se disuelven juntos,
  sin salto ni slow-then-jump. (`ThemeCrossfadeView`.) iOS conmuta instantáneo de momento.
- **#2 Sidebar slide real:** el panel está siempre en el árbol y entra/sale por **offset**
  (−184→0) + opacidad, así desliza de verdad y no parpadea su borde.
- **#3 Grid restaurado:** el calendario tenía `maxHeight: .infinity` y se comía el grid; ahora
  altura fija (150). La tarjeta de proyecto queda pequeña arriba-izquierda como pediste, sin
  romper los ratios del 5×2.

### Fase 0.1 — correcciones 7
- **Sidebar arreglada:** la causa de que no abriera era un `onHover` en el panel que detectaba
  "fuera" durante el slide-in y lo cerraba al instante. Quitado. Ahora abre por hover **o clic**
  en el borde, cierra al clicar fuera o elegir proyecto. Desliza limpio.
- **Toggle simplificado:** fuera el crossfade por snapshot (over-engineered, se calaba). Ahora un
  **fade in/out** corto a pantalla completa (0.28s + 0.34s) a través del tono, conmutando bajo
  cobertura. Sencillo y calmado. (Pico/duración fáciles de ajustar.)

### Fase 0.1 — Liquid Glass nativo aplicado (base)
- **`glassCard` → `.glassEffect(.regular/.clear, in:)`** nativo (macOS/iOS 26): refracción y bordes
  reales en tiles, tarjetas de identidad/overview, paneles (Ideas/palette/quick add).
- **`IconButton` → `.glassEffect(.regular.interactive(), in: Circle())`** (+ tint cuando activo):
  respuesta de hover/press nativa, sin animaciones a mano.
- **Sidebar → `.glassEffect(.regular, …)`**: ahora es liquid glass de verdad. Y **autocierra al
  salir** con gracia de 380ms (cancela si vuelves; ya no se cerraba durante el slide-in).
- **Toggle: vuelta al crossfade del fondo por interpolación** (`darkness` 0→1, 1.0s), conmutando
  el esquema a mitad. **Sin overlay, sin blackout** — los elementos se ven todo el rato.
- Pendiente para 0.2: `GlassEffectContainer` + `.glassEffectID` para el **morphing de cards**.

### Fase 0.1 — afinado glass/sidebar/toggle
- **Sidebar: una sola zona de hover** cuyo ancho de hit salta a 168 al abrir (sin race de
  slide-in). Entrar en los ~14px del borde abre **al instante**; salir cierra al instante; la
  animación es suave (0.4s). Fuera el grace de 380ms.
- **Toggle: `.linear(duration: 2.0)`** (velocidad constante, sin el acelerón del `easeInOut` que
  se notaba como golpe), conmuta el esquema a la mitad. Sin overlay/blackout.
- **Regla:** todo botón/toggle custom usa **Apple Liquid Glass** (`.glassEffect(.interactive())`).

### Fase 0.1 — toggle (golpe de los tools)
- Diagnóstico del usuario: el golpe eran los **tools** (glass nativo + texto) conmutando de
  esquema **a mitad** del fade del fondo. El glass/texto no se pueden fundir entre esquemas en
  SwiftUI → conmutan de golpe. Solución: **conmutar tools/texto al instante del clic** (cambio
  esperado) y dejar que el **fondo se acerque** con `easeOut(0.9s)`. Sin mismatch a mitad. Más rápido.

### Siguiente
- Verificar legibilidad del glass sobre texto, y entrar en **0.2 — modelo Card**.

---

## Tramo 2 · sub-paso 4b — Correcciones 3 (causas reales) · Sábado, 21 de junio de 2026

Estado: **completado, a la espera de verificación humana.**

### #1 Parpadeo infinito — CAUSA REAL encontrada y corregida
- Era pérdida de `@State`: `descriptor.makeView` se envuelve en `AnyView` y, al re-renderizarse
  la tile en modo edición, SwiftUI recreaba la vista de la tool reseteando su estado (vacío →
  carga → vacío…). Fijado con **`.id(slot.id)`** en el cuerpo de la tool (identidad estable) +
  **eliminada la levitación en bucle** (`repeatForever`) que forzaba re-renders. Tiles estables.

### #3 Popover de Ideas — reemplazado por panel translúcido propio
- El `.popover` estaba dentro del `ForEach` → varios popovers al mismo binding se autocerraban.
  Nuevo `WorkspaceOverlay` (presentador a nivel de Workspace): la idea abre un **panel glass
  translúcido** centrado sobre un **fondo difuminado** (`.ultraThinMaterial`, gaussiano) — no un
  popover de flecha. Clic fuera o ✕ cierra. (`IdeaDetailPanel`.)

### #2 Onda del toggle — ahora visible
- Antes se desvanecía mientras crecía (invisible). Ahora: una onda translúcida (radial suave,
  ~0.5 alpha en el centro) **crece desde el botón → conmuta el tema debajo → se desvanece**.
  Translúcida (el glass sigue viéndose), no un flash sólido. Nota: va por encima del contenido
  (más visible); el "bajo la glass" literal queda como ajuste si lo prefieres.

### #4 Hotkeys — confirmados OK por el usuario.

### Verificación
- `xcodebuild` macOS + iOS → **BUILD SUCCEEDED**.

---

## Tramo 2 · sub-paso 4b — Correcciones 2 + bug de tiles + Ideas + watcher · Viernes, 20 de junio de 2026

Estado: **completado, a la espera de aprobación humana.**

### Bug grave corregido — parpadeo infinito de las tiles (#3)
- Quitadas las animaciones implícitas (`.animation(_:value:)`) de `ToolTileView` y la
  `.animation(value: gridIDs)` del grid: causaban un crossfade permanente entre el contenido y
  el estado vacío al re-añadir tools. El resaltado y la edición animan ahora vía `withAnimation`
  en su origen. Tiles estables.

### Bug corregido — hotkeys planos al escribir (#4)
- `NidusModel.isEditingText` + `ToolAddField` reporta su foco; `handleKey` ignora F/T/I mientras
  hay una celda de texto activa. Escribir ya no dispara atajos.

### Otras correcciones
- **#1 ESC**: reintroducido **solo** para cerrar el command palette (`onKeyPress(.escape)`).
- **#2 Onda del toggle**: ya no es un bloque opaco que lo cubre todo de blanco/negro. Ahora el
  tema conmuta al instante y una **onda translúcida** (radial, blend multiply/screen) se expande
  desde el botón y se desvanece, sin opacar el glass.
- **#5 Ideas rediseñado**: lista **numerada cronológica** `1. Título` + subheader de fecha
  discreto + **botón expandir** que abre un **popover glass** con las notas (ver y añadir).
  Modelo idea = título + notas (notas bajo el header en `ideas.md`). Divisores sutiles + más
  espaciado; mismo espaciado/divisores aplicado a Inbox/Archive.

### 4c (parcial) — watcher de cambios externos
- Recarga de archivos al **reactivarse la app** (`scenePhase == .active` → `notifyFileChange`).
  Captura ediciones hechas fuera de Nidus al volver. (FS-events en vivo = refinamiento futuro.)

### Verificación
- `xcodebuild` macOS + iOS → **BUILD SUCCEEDED**.

### Pendiente de 4c — deadlines + panel de tarea + Deadline Calendar
Spec del usuario (a implementar): la tarea se crea simple; al clicar una se expande/abre un
popup translúcido (NSPanel on top, dim gaussian del fondo) con **Título · deadline (si hay) ·
fecha añadida · notas** (editables, estética integrada, no celda de texto cruda). El deadline se
elige en un **calendario anual**: día concreto = *hard*; semana o mes = *soft*. El Deadline
Calendar (overview) refleja esos deadlines.

**Conflicto con el blueprint (§2.6 / §10.4) — RESUELTO:** el usuario aprobó **evolucionar a
sub-líneas legibles** (no frontmatter): `- [ ] tarea` + `    - deadline: … (hard|soft)`,
`    - added: …`, `    - note: …`. Al completar se mueve el bloque entero. Pendiente de
implementar en el próximo paso (panel de tarea + calendario + Deadline Calendar overview),
tras verificar a mano los arreglos de este turno.

---

## Tramo 2 · sub-paso 4b — Correcciones de interacción (ethos calma) · Viernes, 20 de junio de 2026

Estado: **completado, a la espera de aprobación humana.** Releído el ethos del blueprint
(Apéndice A: calma, foco, *pull not push*) para guiar estos ajustes.

1. **Atajos directos** (sin Cmd) vía `onKeyPress`, solo cuando no hay celda de texto activa
   (el campo enfocado consume la tecla primero): **F** = buscar en proyecto, **⌘F** = buscar en
   todos, **T** = tarea, **I** = idea. Quitados los botones ocultos con atajo.
2. **Toggle claro/oscuro = onda calmada** (`ThemeController` + `WaveOverlay`): el nuevo tema se
   expande desde el botón (arriba-dcha) como una gota en agua quieta — crece, conmuta debajo,
   y se desvanece. Sustituye el cambio abrupto.
3. **Wiggle → levitación** (`Levitate`): movimiento suave y lento (no la danza ansiosa), cada
   tile con su fase. Acorde al ethos.
4. **Sidebar = slide-over + fade-in** (antes aparecía de golpe): desliza desde la izquierda con
   opacidad, ~0.32s.
5. **Command palette navegable**: flechas ↑/↓ + hover, Enter/clic abre; al elegir un resultado
   del proyecto activo, su tile se resalta con **acento momentáneo** (~1.3s) señalando el lugar;
   un resultado de otro proyecto cambia de ventana.
6. **ESC eliminado**: cierres por clic-fuera / selección / botón; sin navegación por ESC.

### Notas
- Los atajos de letra dependen de `onKeyPress` + foco del contenedor; si tras editar un campo
  los atajos no responden, hacer clic en el lienzo los reactiva (a verificar a mano).
- El origen de la onda es la esquina superior derecha (donde vive el toggle).

### Verificación
- `xcodebuild` macOS + iOS → **BUILD SUCCEEDED**.

---

## Tramo 2 · sub-paso 4b — Controles, feedback y navegación auxiliar · Viernes, 20 de junio de 2026

Estado: **completado, a la espera de aprobación humana** (sub-puerta del T2).

### Controles reubicados + feedback Apple-like
- `IconButton.swift` — botón redondo sin texto con **hover (lift + glow)** y **haptic** al pulsar;
  `AppearanceToggle` compartido (claro/oscuro, fade lento) que ahora vive en Greeting **y** Workspace.
- Workspace: **cluster arriba-derecha, encima del calendario** → `[Customize] [☀︎/☾]` (redondos,
  con comando). Quitado el botón "Customize" de abajo. ⌘E sigue activo.
- `Wiggle.swift` — jiggle sutil tipo home-screen de iOS en las tiles dentro de Customize Mode.
- Haptics en quitar/añadir/quick-add; cambios del grid animados con spring.
- Apuntado a futuro: **"grabbing zone"** para mover tiles de forma intuitiva (con resize/reorder, T3).

### Navegación auxiliar (4b)
- `SidebarView.swift` — sidebar **overlay** (no desplaza el contenido): indicador fino a la
  izquierda, se abre al acercar el cursor; lista solo disciplinas con proyectos y **solo nombres**
  (preserva el aislamiento §10.10). Elegir un proyecto **cambia el proyecto de la ventana**.
- `CommandPaletteView.swift` — **⌘F** busca contenido en el proyecto activo, **⇧⌘F** en todos.
  Resultados etiquetados por archivo/proyecto; un resultado de otro proyecto cambia de ventana.
- `QuickAddView.swift` — **⌘I** idea / **⌘T** tarea → prompt enfocado que hace append al
  `.md` del proyecto activo.
- `MarkdownStore.searchLines` + `NidusModel.searchContent` (+ `ContentHit`).
- `RootWindowView` pasa `onOpen` a `WorkspaceView` (sidebar / búsqueda cross-project).
- ESC en cascada: quick-add → palette → sidebar → Customize → volver al Greeting.

### Verificación
- `xcodebuild` macOS + iOS → **BUILD SUCCEEDED**.

### Sub-gate (probar a mano)
- Controles redondos arriba-derecha; toggle claro/oscuro también en el workspace.
- ⌘E → tiles con wiggle + ✕ (no Inbox) + "+"; feedback al pulsar.
- Acercar el cursor al borde izquierdo → sidebar; elegir proyecto → cambia la ventana.
- ⌘F / ⇧⌘F → búsqueda de contenido; ⌘I / ⌘T → captura rápida.

### Siguiente — sub-paso 4c (cierre del T2)
- Deadlines hard/soft en tareas (sintaxis legible) + **Deadline Calendar activo** (overview).
- Detección de cambios externos en archivos (watcher).

---

## Tramo 2 · sub-paso 4a — Compartimentalización de tools + Customize Mode · Viernes, 20 de junio de 2026

Estado: **completado, a la espera de aprobación humana** (sub-puerta del T2).

### Refactor — una tool por archivo (petición del usuario)
- `BaseToolViews.swift` dividido en `InboxTool.swift`, `IdeasTool.swift`, `TaskManagerTool.swift`,
  `TaskArchiveTool.swift` — cada uno con su vista **y** su `static let descriptor` (módulo
  autocontenido). Componentes comunes a `ToolComponents.swift`.
- `ToolRegistry` ahora ensambla desde `ToolRegistry.all` (lista de descriptores). Añadir o
  importar una tool nueva = nuevo archivo + una línea en `all`. (Base para custom tools, TF-1.)

### Añadido — Customize Mode (⌘E)
- Botón **Customize / Done** abajo-izquierda + atajo **⌘E**. ESC sale de Customize (y si no,
  vuelve al Greeting).
- En modo edición: las tiles muestran borde de acento y un control **quitar** (✕) — salvo
  **Inbox**, que no se puede eliminar (§3.3); su cuerpo queda inerte para no actuar por error.
- Las celdas vacías pasan a **"+"** que abre `ToolLibrarySheet` (tools no colocadas); al elegir,
  se coloca con el mayor tamaño válido que cabe en el hueco.
- `NidusModel.addTool/removeTool` + `mutateProject` → persisten el `layout` en `nidus.json`.
- **Redimensionar/reordenar** NO entran aquí: son del Tramo 3 por el blueprint.

### Verificación
- `xcodebuild` macOS + iOS → **BUILD SUCCEEDED**.

### Sub-gate (probar a mano)
- ⌘E (o botón) entra/sale de Customize; aparecen ✕ en tiles (no en Inbox) y "+" en huecos.
- Quitar una tool → desaparece y queda hueco "+"; añadirla de vuelta desde la biblioteca.
- Reabrir el proyecto: el layout persiste (mirar `nidus.json`).

### Siguiente — sub-paso 4b
- Sidebar oculta (overlay, no desplaza) + command palette (⌘F/⇧⌘F) + atajos ⌘I/⌘T.

---

## Tramo 2 · sub-paso 3 — Las 4 herramientas base + completar · Viernes, 20 de junio de 2026

Estado: **completado, a la espera de aprobación humana** (sub-puerta del T2).

### Añadido
- `HumanDate.swift` — encabezados de fecha legibles ("Monday, 5 May 2026") en el **idioma de
  la app** (usa `Bundle.main.preferredLocalizations`, no el locale del sistema), nunca ISO.
- `MarkdownStore.swift` — lectura/escritura de los `.md` (Markdown estándar; solo append/editar
  línea, nunca destruye): `appendCapture`, `appendIdea`, `addTask`, `readTasks`, `readSections`,
  y `completeTask` (mueve la línea de `tasks-todo.md` a `tasks-done.md` bajo "## Completed: <fecha>").
- `BaseToolViews.swift` — las 4 herramientas:
  - **Inbox**: campo de captura → append `- texto` bajo "## <fecha>"; lista por días.
  - **Ideas**: nueva idea → bloque "## <fecha> — <título>"; lista de bloques.
  - **Task Manager**: checkboxes desde `tasks-todo.md`, añadir tarea, y **completar** (click →
    quita de todo y registra en done con fecha).
  - **Task Archive**: render cronológico read-only de `tasks-done.md`.
  - Helpers compartidos: `ToolAddField`, `ToolSectionList`, `ToolEmptyHint`.

### Cambiado
- `ToolRegistry` instancia las vistas reales de las 4 base.
- `NidusModel.fileChangeTick` / `notifyFileChange()` — al escribir, todas las tiles recargan
  (refresco entre tiles; base para detección de cambios externos más adelante).

### Verificación
- `xcodebuild` macOS + iOS → **BUILD SUCCEEDED**.
- Lógica de Markdown probada en aislado: captura agrupa por fecha; añadir/leer tareas;
  completar mueve todo→done bajo "## Completed: <fecha>".

### Sub-gate (probar a mano, en un proyecto nuevo)
- Inbox: escribir + Enter → aparece bajo la fecha de hoy; mirar `inbox.md` en el vault.
- Task Manager: añadir tareas; click en una → desaparece y aparece en Task Archive (y en
  `tasks-done.md`).
- Ideas: añadir → bloque con fecha.

### Pendiente dentro del T2 (siguiente sub-paso / nota)
- **Deadlines hard/soft** en tareas + el **Deadline Calendar** activo (overview): sintaxis
  legible y parseable a finalizar; ahora el overview es placeholder.
- **Detección de cambios externos** (FS watcher) — hoy se recarga tras escrituras propias.
- Editor markdown rico para Ideas (2x2) y captura auto-enfocada del Inbox → refinamiento.

---

## Tramo 2 · sub-paso 2 — Arquitectura de herramientas · Viernes, 20 de junio de 2026

Estado: **completado, a la espera de aprobación humana** (sub-puerta del T2).

### Añadido
- `ToolDescriptor.swift` — arquitectura de herramientas (Blueprint §3.6):
  - `ToolDescriptor` declara `id`, `title`, `icon`, `validSizes` (subconjunto de los 3 tamaños),
    `files` (los `.md` que toca — contrato de archivos) y `makeView` (su vista por contexto).
  - `ToolContext` da a la herramienta lo que necesita: tamaño, `ProjectRef` y `folderURL`
    (carpeta del proyecto en el vault) + `fileURL(_:)` para sus `.md`.
  - `ToolRegistry` — registro de las 4 base (inbox/ideas/task-manager/task-archive) con sus
    tamaños válidos y archivos; fallback para ids desconocidos. (Herramientas custom → TF-1.)
  - `ToolPlaceholderBody` — cuerpo temporal hasta T2.3.

### Cambiado
- `ToolTileView` resuelve chrome (título/icono) y cuerpo desde el `ToolRegistry`
  (antes tenía un switch hardcoded).
- `WorkspaceGridView` recibe `projectRef`, calcula la `folderURL` del proyecto y construye un
  `ToolContext` por tile.
- `NidusModel.projectFolderURL(_:)` — resuelve la carpeta del proyecto en el vault.

### Verificación
- `xcodebuild` macOS → **BUILD SUCCEEDED**. iOS Simulator → **BUILD SUCCEEDED**.

### Sub-gate
- Los tiles ahora se instancian desde el registro (título/icono/tamaños/archivos declarados);
  el cuerpo muestra "… — T2.3". Sin cambio visual mayor; es el andamiaje para las 4 base.

---

## Tramo 2 · sub-paso 1 — Substrate del grid 5×2 · Viernes, 20 de junio de 2026

Estado: **completado, a la espera de aprobación humana** (sub-puerta del T2).
Greeting Panel aprobado por el usuario (borrador); pulido estético fino → T3.

### Añadido
- `ToolSize.swift` — enum de los tres tamaños permitidos (`1x1`/`1x2`/`2x2`) con columnas/filas.
- `WorkspaceGridView.swift` — motor del grid: 5 columnas × 2 filas, sin scroll, coloca cada
  herramienta por `(col,row)` y la dimensiona por su tamaño (con `GeometryReader`). Filtra
  slots que no caben (defensivo ante layouts malformados).
- `ToolTileView.swift` — tile placeholder (nombre, icono, badge de tamaño) sobre material.
  El contenido real de cada herramienta llega en T2.3.
- `WorkspaceView.swift` — shell del workspace: back + identidad de proyecto + overview
  (placeholder deadline-calendar) + el grid. Sustituye a `WorkspacePlaceholderView`.

### Cambiado
- `GlassBackground` admite `reduced`: Greeting usa glass fuerte (`.hudWindow`); Workspace
  usa glass reducido (`.underWindowBackground`) para legibilidad (GUI workspace §10).
- `RootWindowView` usa `WorkspaceView` y pasa glass reducido al abrir proyecto.

### Eliminado
- `WorkspacePlaceholderView.swift` (sustituido por `WorkspaceView` + grid).

### Ajuste de tiles base + placeholders de grid
- Layout por defecto: **las 4 base a 1x2** (ideas pasa de 1x1 a 1x2), columnas 0–3.
- **Placeholders punteados sutiles** en celdas vacías (`GridArea`): columna libre entera → 1x2
  punteado; celda suelta → 1x1. Visualiza la rejilla sin clutter.
- Nota: proyectos ya creados conservan su layout en `nidus.json` (no se migra para no pisar
  futuras personalizaciones de Customize Mode); crear uno nuevo muestra el default actualizado.

### Ajuste de ratio (sobre feedback con mockups)
- **Top zone con más presencia** (~24% de la altura): identidad y deadline-calendar como
  tarjetas glass más grandes (icono, nombre, descripción, disciplina, Open Folder / overview).
- **Tope de altura de celda** (`maxCellHeight` 300) en el grid: los tiles 1x2 ya no se estiran
  hasta abajo; el grid top-alinea y deja aire inferior + `padding(.bottom)`.
- Pendiente anotado: la **sidebar será overlay** (no desplaza el contenido) → sub-paso 4.
- Alternativa en reserva si hace falta: pasar a **5×3** en vez de 5×2.

### Verificación
- `xcodebuild` macOS → **BUILD SUCCEEDED**. iOS Simulator → **BUILD SUCCEEDED**.

### Pendiente de probar a mano (sub-gate)
- Abrir un proyecto → el grid muestra las 4 base colocadas según `layout` (inbox 1x2 a la izq.,
  ideas 1x1, task-manager 1x2, task-archive 1x2), sin scroll, llenando el área.
- El workspace se ve menos translúcido que el Greeting.

---

## Tramo 1 (v0.6) — Greeting Panel + modelo de ventana · Viernes, 20 de junio de 2026

Estado: **completado, a la espera de aprobación humana.** Reescritura tras la actualización a
Blueprint v0.6 + GUI specs (Greeting Panel y Workspace). Decisiones: todo el proyecto en inglés
con i18n; NSPanel flotante real en Mac + vista centrada en iPad.

### Contexto
El T1 anterior (drill-down de 3 niveles, v0.2) quedó **obsoleto** con el modelo de dos UIs de
v0.6. Se descartó y reescribió.

### Eliminado (obsoleto v0.2)
- `ContentView.swift`, `DisciplineListView.swift`, `ProjectListView.swift`,
  `ProjectWorkspaceView.swift`, `Route.swift`, `SearchField.swift`.

### Parche de T0 (lo que v0.6 añadió a T0)
- `VaultStore` crea `_inbox-global/` en el vault (§2.5) al fijar/restaurar.
- `NidusConfig` ampliado: `cover` (disciplina), `description`/`icon`/`layout` (proyecto).
  `layout` = `overview_tool` + `grid[]` de `ToolSlot {tool,size,col,row}`.
- Al crear: disciplina con `cover` por defecto (esfera dinámica, tint #3A5BFF);
  proyecto con `icon` por defecto y `layout` por defecto (4 base: inbox 1x2, ideas 1x1,
  task-manager 1x2, task-archive 1x2). El grid se *renderiza* en T2; aquí solo se persiste.

### Añadido (Greeting Panel y ventana)
- `NidusApp` — `WindowGroup` con modelo compartido app-wide; `.hiddenTitleBar` en Mac.
  Una ventana = un proyecto; ⌘N nueva ventana, ⌘W cierra (defaults de SwiftUI).
- `RootWindowView` — estado por ventana: sin proyecto → Greeting; con proyecto → Workspace.
  Transición en la misma superficie. Vault compartido.
- `WindowConfigurator` — Mac: estiliza la ventana como panel flotante centrado (sin barra de
  título, nivel floating, no redimensionable) en estado Greeting; se expande al abrir proyecto.
  iPad: no-op (vista centrada).
- `GreetingPanelView` — greeting "Ready when you are.", búsqueda enfocada con fuzzy global de
  proyectos (flechas en Mac + Enter abre), recientes (esferas) + New Project, disciplinas
  (esferas) + New, expansión en abanico de los proyectos de una disciplina.
- `SphereView` — esfera de vidrio procedural (icono SF + tint), hover contenido.
- `Fuzzy` — matching por subsecuencia (acento/caso-insensible); "lum"→Lumen.
- `Color+Hex` — parsea `cover.tint`.
- `VaultPickerView` — primer arranque (extraído de la antigua ContentView).
- `NewProjectSheet` — rehecha: elegir disciplina existente o crear una nueva inline + nombre +
  carpeta vinculada opcional; al crear abre el proyecto.
- `WorkspacePlaceholderView` — destino de la transición (T1): identidad del proyecto, slot de
  overview (deadline-calendar placeholder), lista de tools del layout, botón "Abrir carpeta"
  device-aware, volver al Greeting (botón + ESC en Mac). El grid 5×2 real es T2.

### Recientes
- Estado local del dispositivo (`UserDefaults`, key `nidus.recent.projects`), nunca en el vault.

### Verificación
- `xcodebuild` macOS → **BUILD SUCCEEDED**. iOS Simulator → **BUILD SUCCEEDED**.
- Fuzzy probado en aislado.

### Pendiente de probar a mano (gate)
- Crear disciplina y proyecto desde el Greeting; aparecen esferas, `_inbox-global/` y el
  `nidus.json` con `cover`/`icon`/`layout`.
- Buscar 3 letras → Enter → entra al Workspace; volver con ESC/botón.
- ⌘N abre otra ventana en su propio Greeting; ⌘W cierra.
- En Mac, el Greeting se siente como panel flotante centrado.

### Ajuste 3 — orbit magnético, glass real, toggle pulido
- **Orbit con máquina de estados de hover**: apertura tras retardo de confirmación (~340ms),
  **anclada a la esfera** (anchorPreference) para continuidad magnética; proyectos brotan
  desde el centro con spring (fade + scale → posición final). **Autocierre** al alejarse
  (grace ~260ms), con Esc o clic fuera. (Antes abría/cerraba con parpadeo y centrado fijo.)
- **Más glass**: material `NSVisualEffectView` → `.hudWindow` (translúcido tipo Spotlight),
  ahora se ve el escritorio detrás.
- **Toggle de apariencia**: haptic al pulsar, reactivo al hover (scale + borde + sombra),
  subido a la franja superior derecha; cambio claro/oscuro con fade lento (~0.6s).

### Ajuste 2 — material glass, panel vertical, orbit al hover, modo claro/oscuro
- **Panel = glass refractivo**: ventana transparente (`isOpaque=false`, bg `.clear`) +
  `NSVisualEffectView` (`.underWindowBackground`, behind-window) que refracta el escritorio.
  Eliminado el fondo azul (era del mockup, no diseño). En iPad, material fino.
- **Ventana vertical y más pequeña**: panel 480×660 (antes 820×600 horizontal).
- **Hover sobre disciplina → orbit estilo watchOS**: se difumina el resto (blur 14) y los
  proyectos emergen como esferas orbitando la disciplina (centrado, sobre backdrop). Cierra al
  clicar fuera, con Esc (Mac) o al pasar a otra disciplina. (Antes: expansión en fila/abanico.)
- **Modo claro por defecto + toggle** (sol/luna) arriba-derecha; persistido app-wide
  (`@AppStorage`), aplicado en macOS e iPad vía `preferredColorScheme`.

### Ajuste 1 — hacia el primer mockup de referencia
- Placeholder de búsqueda → "Jump to any project…".
- Añadidos los rótulos de sección "RECENT PROJECTS" / "DISCIPLINES" (mayúsculas, tracking).
- Objeto "New" reordenado al principio de recientes, con círculo punteado (no esfera rellena).
- `SphereView` rehecha con estilos: recientes = vidrio blanco neutro con icono grafito;
  disciplinas = vidrio con tinte sutil; "New" = contorno punteado. Menos saturación, sheen suave.
- Quitado el "+New" de la fila de disciplinas (no está en el mockup); crear disciplina sigue
  disponible inline desde "New Project".
- Bloom azul ambiental más presente (diagonal desde abajo-izquierda).

### Sabido / a pulir (no bloquea T1)
- Icono y tinte de disciplina son por ahora el default para todas (hexagongrid / #3A5BFF). El
  mockup muestra iconos/tintes variados por disciplina (hoja, </>, libro, lápiz) → un selector
  de icono/tinte al crear disciplina es trabajo futuro de creación/personalización.
- NSPanel se logra estilizando la NSWindow de SwiftUI (no un NSPanel literal), para que la
  misma superficie pueda expandirse al Workspace (§12). Si prefieres un panel literal separado,
  lo replanteamos.
- Fidelidad liquid-glass, animación de abanico y transición fina → pulido posterior con assets.

---

## Revisión — Idioma e flujo de vault · Viernes, 20 de junio de 2026

Petición del usuario, aplicada sobre T0+T1 (no es un tramo nuevo).

### Cambiado
- **Flujo de vault**: ahora el usuario elige *dónde* Nidus creará su carpeta. Nidus crea
  una carpeta `NidusVault` dentro de la ubicación elegida, con `nidus.json` dentro.
  - `VaultStore` guarda el bookmark de la **ubicación padre** (lo que concede el sistema) y
    el vault es `<padre>/NidusVault`. Creación idempotente (si ya existe, se reutiliza).
  - **Clave de bookmark nueva** (`nidus.vault.root.bookmark`): cualquier vault elegido en las
    pruebas del T0 queda invalidado → hay que volver a elegir ubicación una vez.
- **Todo el codebase a inglés** (código, comentarios, strings de UI), preparado para
  localizar: `Text`/`LocalizedStringKey` y `String(localized:)` en todas las cadenas visibles.
  Añadido `Localizable.xcstrings` (String Catalog) como sitio de futuras traducciones.
  Xcode fijó `developmentRegion = en`.

### Decisión
- **Contenido de los `.md` universal**: headers de sección en **inglés fijo**
  (`# Inbox`, `# Ideas`, `# Tasks`, `# Done`) — contrato estable y parseable. El idioma solo
  afecta a la UI. (Las fechas, en T2, irán en el idioma activo de la app.) Esto ajusta la
  doctrina §9.8 del blueprint, que pedía español; el usuario lo aprobó explícitamente.

### Verificación
- `xcodebuild` macOS → **BUILD SUCCEEDED**. iOS Simulator → **BUILD SUCCEEDED**.

---

## Tramo 1 — Navegación de los tres niveles · Viernes, 20 de junio de 2026

Estado: **completado, a la espera de aprobación humana.**

### Añadido
- `Slug.swift` — deriva carpetas e ids legibles del nombre (sin acentos, minúsculas,
  guiones) + unicidad con sufijo (`oculo`, `oculo-2`…).
- `Route.swift` — rutas tipadas de la navegación (`discipline`, `project`).
- `SearchField.swift` — campo de búsqueda reutilizable, enfocado al entrar (doctrina §4).
- `DisciplineListView.swift` — Nivel 1: lista buscable + crear disciplina (alert).
- `ProjectListView.swift` — Nivel 2: lista buscable + añadir proyecto (sheet).
- `NewProjectSheet.swift` — alta de proyecto: nombre + `linked_location` opcional
  (picker de carpeta, captura `device_id`/`device_name`/`path` de esta máquina).
- `ProjectWorkspaceView.swift` — Nivel 3 (placeholder T1): muestra las 4 secciones y el
  `linked_location` device-aware. Editores y lógica de contenido → Tramo 2.

### Cambiado
- `ContentView.swift` — la vista puente del T0 se sustituye por `NavigationStack` con
  `path` tipado. ESC retrocede un nivel en Mac (`onExitCommand`); gesto atrás nativo en iPad.
- `VaultStore.swift` — nuevas operaciones de filesystem: `url(forRelativePath:)`,
  `makeDirectory(at:)`, `createProjectScaffold(at:)` (crea los 4 `.md` con header, sin
  sobreescribir nunca).
- `NidusModel.swift` — lookups (`discipline(id:)`, `project(...)`) y mutaciones
  (`createDiscipline`, `createProject`, `linkedLocation(for:)`). Cada alta escribe carpeta(s)
  + archivos + persiste `nidus.json`.

### Decisiones
- **id legible (slug del nombre)**, fijo al crear. `id` de proyecto único entre TODOS los
  proyectos (lo exige `nidus://open?project=<id>` del Tramo 3); `id` de disciplina único
  entre disciplinas. `folder` único dentro de su carpeta padre. Nombre visible conserva acentos.
- No se implementa **renombrar** en T1 (fuera de alcance del tramo).

### Verificación
- `xcodebuild` macOS → **BUILD SUCCEEDED**. iOS Simulator → **BUILD SUCCEEDED**.
- Slug probado en aislado: `Cerámica→ceramica`, `Óculo→oculo`, espacios→guiones, colisión→sufijo.

### Pendiente de probar a mano (en la puerta de aprobación)
- Crear disciplina → aparece carpeta en el vault y entrada en `nidus.json`.
- Crear proyecto (con y sin carpeta vinculada) → carpeta + 4 `.md` con headers + entrada JSON.
- Navegar 3 niveles; ESC retrocede en Mac.

---

## Tramo 0 — Esqueleto Xcode · Viernes, 20 de junio de 2026

Estado: **completado, a la espera de aprobación humana.**

### Añadido
- `DeviceIdentity.swift` — identidad local del dispositivo (UUID estable + nombre editable),
  persistida en `UserDefaults`, nunca en el vault (§2.3 / §9.7).
- `NidusConfig.swift` — modelos `Codable` que espejan `nidus.json` (`NidusConfig`,
  `Discipline`, `Project`, `LinkedLocation`) con claves snake_case del contrato.
- `VaultStore.swift` — bookmark del NidusVault (creación, restauración, refresco si queda
  obsoleto) + lectura/creación de `nidus.json`. Escritura atómica, pretty-printed y legible.
- `NidusModel.swift` — estado raíz `@Observable`: orquesta identidad + vault + config.
- `ContentView.swift` — reescrita: picker de carpeta en primer arranque + vista puente
  que confirma vault e identidad. Sin navegación ni editores (eso es Tramo 1+).

### Descartado / eliminado
- **SwiftData** por completo. El scaffold por defecto de Xcode traía `Item.swift`,
  `@Model`, `ModelContainer` y `@Query` — viola §9.3 (sin base de datos propietaria).
  `Item.swift` eliminado; `NidusApp` y `ContentView` reescritos sin `import SwiftData`.
- **visionOS (xrOS)** retirado de `SUPPORTED_PLATFORMS` y de los deployment targets.
  El blueprint pide solo macOS + iPadOS.
- **iPhone** retirado: `TARGETED_DEVICE_FAMILY` pasa de `"1,2,7"` a `"2"` (solo iPad).

### Decisiones de configuración (pbxproj)
- `ENABLE_APP_SANDBOX = NO`. El Mac corre **sin sandbox** (distribución open source,
  fuera de App Store). El iPad va siempre sandboxed por el propio SO.
- `ENABLE_USER_SELECTED_FILES = readwrite` (irrelevante sin sandbox en Mac; documenta intención).
- Bookmark del vault creado con `options: []` en **ambas** plataformas. `.withSecurityScope`
  solo aplica a apps macOS *sandboxed*, que no es nuestro caso. En iPad el acceso se activa
  con `startAccessingSecurityScopedResource()`; en Mac devuelve `false` sin ser error.

### Esquema de `nidus.json` vacío que se crea en primer arranque
```json
{
  "disciplines": [],
  "version": "1"
}
```

### Verificación
- `xcodebuild` macOS → **BUILD SUCCEEDED**.
- `xcodebuild` iOS Simulator → **BUILD SUCCEEDED** (rama UIKit verificada).

### Pendiente de probar a mano (en la puerta de aprobación)
- Elegir carpeta real, cerrar y reabrir la app → debe recordar el vault.
- Comprobar que `nidus.json` aparece en la carpeta elegida.

### Failsafe futuro anotado (no implementar ahora)
- Si iPadOS se vuelve demasiado problemático, evaluar un frontend web sencillo sobre los
  documentos del NidusVault en iCloud. No cambia la ruta actual (SwiftUI nativo Mac + iPad).
