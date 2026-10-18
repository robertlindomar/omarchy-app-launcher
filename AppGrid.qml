import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Usage.js" as Usage
import "Agents.js" as Agents

// A centered launcher: a manual "Favorites" section on top, then every installed
// application and coding agent below, alphabetical and scrollable.
//
// The app list itself is not ours: the shell's AppLibrary already watches
// DesktopEntries, filters hidden/NoDisplay entries, resolves icon names to
// files (re-indexing after an install), and launches under app-graphical.slice.
// This plugin owns presentation, frecency ordering, and the "just added" badge.
Item {
  id: root

  // Injected by the shell's panel loader.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property var appLibrary: root.shell && root.shell.appLibrary ? root.shell.appLibrary : localAppLibrary

  // Some Omarchy builds expose a scoped shell without appLibrary to third-party
  // menus. DesktopEntries is available to QML directly, so keep the launcher
  // usable when that optional capability is absent.
  QtObject {
    id: localAppLibrary
    signal appsChanged()

    function sortedEntries(query) {
      var q = String(query || "").toLowerCase().trim()
      var entries = DesktopEntries.applications.values || []
      var rows = []
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        if (!entry || entry.noDisplay) continue
        var name = String(entry.name || entry.id || "")
        if (!name || (q && (name + " " + entry.id + " " + (entry.genericName || "") + " " + (entry.comment || "")).toLowerCase().indexOf(q) < 0)) continue
        rows.push({ entry: entry, score: 0, key: name.toLowerCase(), name: name.toLowerCase() })
      }
      rows.sort(function(a, b) { return a.key.localeCompare(b.key) })
      return rows
    }
    function entryName(entry) { return String(entry.name || entry.id || "") }
    function entrySubtext(entry) { return String(entry.genericName || "") }
    function iconSource(icon) { return Quickshell.iconPath(String(icon || "application-x-executable"), true) }
    function refreshIcons() {}
    function launch(id, name) { Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", String(id) + ".desktop"]) }
    function remove(id, name) { Quickshell.execDetached(["omarchy-remove-launcher-entry", String(id), String(name)]) }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { localAppLibrary.appsChanged() }
  }
  readonly property string pluginId: (root.manifest && root.manifest.id) || "tyrsolution.app-launcher"
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/app-launcher"

  property bool opened: false
  property string filterText: ""
  property string category: "Todos"
  readonly property var categories: ["Todos", "Agentes", "Desenvolvimento", "Internet", "Escritório", "Mídia", "Jogos", "Sistema", "Utilitários", "Outros", "Configurações"]
  readonly property var settings: [
    {id:"setting:wifi", name:"Wi-Fi", keywords:"wifi rede internet conexao", panel:"network"},
    {id:"setting:bluetooth", name:"Bluetooth", keywords:"fone dispositivos", panel:"bluetooth"},
    {id:"setting:sound", name:"Som", keywords:"audio volume microfone", panel:"audio"},
    {id:"setting:display", name:"Monitor", keywords:"tela brilho display", panel:"monitor"},
    {id:"setting:power", name:"Energia", keywords:"bateria desligar reiniciar", panel:"power"}
  ]
  function normalized(value) { return String(value || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase() }
  function matchScore(name, extra, query) {
    var n = normalized(name), q = normalized(query).trim()
    if (!q) return 0
    if (n === q) return 0
    if (n.indexOf(q) === 0) return 1
    if (n.split(/[\s_.-]+/).some(function(w) { return w.indexOf(q) === 0 })) return 2
    if (n.indexOf(q) >= 0) return 3
    if (normalized(extra).indexOf(q) >= 0) return 4
    return -1
  }
  function categoryOf(entry) {
    var cats = entry.categories || []
    var rules = [["Desenvolvimento", "Development", "IDE"], ["Escritório", "Office"], ["Mídia", "AudioVideo", "Audio", "Video", "Graphics"], ["Internet", "Network", "WebBrowser", "Email", "Chat"], ["Jogos", "Game"], ["Sistema", "System", "Settings"], ["Utilitários", "Utility"]]
    for (var i=0; i<rules.length; i++)
      for (var j=1; j<rules[i].length; j++) if (cats.indexOf(rules[i][j]) >= 0) return rules[i][0]
    return "Outros"
  }
  function setCategory(value) {
    root.category = value
    contextMenu.hide()
    root.rebuild()
    root.resetSelection()
    allGrid.positionViewAtBeginning()
    keyCatcher.forceActiveFocus()
  }
  function cycleCategory(direction) {
    var i = root.categories.indexOf(root.category)
    root.setCategory(root.categories[(i + direction + root.categories.length) % root.categories.length])
  }
  property var allRows: []
  // Coding agents (claude, codex, gemini, …) launched into a terminal. Probed
  // on open so an agent installed since last time shows up.
  property var installedAgents: []
  property var pendingAgents: []
  property string defaultAgent: ""
  // User-defined agents from ~/.config/omarchy/app-launcher/agents.json, merged
  // over the built-in roster.
  property var customAgents: []
  property bool agentProbePending: false
  readonly property var agentRoster: Agents.mergeRoster(root.customAgents)
  readonly property string agentConfigPath: Quickshell.env("HOME") + "/.config/omarchy/app-launcher/agents.json"
  // Every app with a recorded launch, widest-first. The visible row is a slice
  // of this: a binding, because rebuild() can run before the window is sized
  // and `panel.columns` is only known once it is.
  property var favoritePool: []
  readonly property var favoriteRows: root.searching
    ? []
    : root.favoritePool

  // Selection spans two grids, so it needs a section as well as an index.
  property string selectedSection: "all"
  property int selectedIndex: 0
  // Usage state loads from disk after the window is up, so the frequent row can
  // appear a moment after open(). Until the user touches anything, let it take
  // the caret; after that, leave the selection where they put it.
  property bool interacted: false

  // Persisted state. `usage` drives the frequent row, `seenIds` drives badges.
  property var usage: ({})
  property var favorites: ({})
  property var seenIds: ({})
  property bool seenLoaded: false
  property var newIds: ({})

  // Tunable per summon: `omarchy-shell shell toggle tyrsolution.app-launcher '{"iconScale":1.4}'`
  property real iconScale: 1.0
  property string fontFamily: Style.font.menuFamily

  // Searching collapses the two sections into one result grid: ranking by
  // relevance and ranking by frecency at the same time reads as noise.
  readonly property bool searching: root.filterText.length > 0
  readonly property bool showFavorites: !root.searching && root.favoriteRows.length > 0

  // Follows the active Omarchy theme through the shared menu color tokens.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color scrim: Color.menu.scrim
  property color accent: Color.accent
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))

  readonly property int cornerRadius: Style.cornerRadius
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int iconSize: Math.round(Style.space(52) * root.iconScale)
  readonly property int cellWidth: root.iconSize + Style.space(44)
  readonly property int cellHeight: root.iconSize + Style.space(52)
  readonly property int headerHeight: Math.max(Style.space(34), Style.font.heading + Style.spacing.controlPaddingY * 2)
  readonly property int footerHeight: Style.font.caption + Style.spacing.md * 2
  readonly property int sectionLabelHeight: Style.font.caption + Style.spacing.md * 2
  readonly property int scrollBarWidth: Style.space(4)

  // ------------------------------------------------------------ lifecycle

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    if (payload.fontFamily) root.fontFamily = payload.fontFamily
    if (Number(payload.iconScale) > 0) root.iconScale = Number(payload.iconScale)

    root.category = "Todos"
    root.filterText = String(payload.query || "")
    contextMenu.hide()
    root.opened = true

    // Icons for packages installed since the shell started may not be in Qt's
    // theme cache yet; AppLibrary rescans on demand.
    if (root.appLibrary) root.appLibrary.refreshIcons()
    // Re-probe the agent roster on every summon, so an agent installed since
    // the last open shows up without a shell restart.
    root.probeAgents()
    root.interacted = false
    root.refreshNewIds()
    root.rebuild()
    root.resetSelection()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    if (!root.opened) return
    root.opened = false
    contextMenu.hide()
    // Everything on screen at close time counts as seen, so badges clear once
    // you've actually had a chance to look at them.
    root.markAllSeen()
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // ------------------------------------------------------------ app list

  function liveIdMap() {
    var out = ({})
    for (var a = 0; a < root.installedAgents.length; a++)
      out[Agents.rowId(String(root.installedAgents[a]))] = true
    if (!root.appLibrary) return out
    var rows = root.appLibrary.sortedEntries("")
    for (var i = 0; i < rows.length; i++) {
      var id = String((rows[i].entry && rows[i].entry.id) || "")
      if (id) out[id] = true
    }
    return out
  }

  function rebuild() {
    if (!root.appLibrary) { root.allRows = []; root.favoritePool = []; return }
    // sortedEntries returns search rows ({ entry, score, key, name }), not the
    // DesktopEntry itself — the entry is one level down. With no query it is
    // already alphabetical; with one it is ranked by the shell's fuzzy matcher.
    var matches = root.appLibrary.sortedEntries("")
    var now = Date.now()
    var out = []
    for (var i = 0; i < matches.length; i++) {
      var entry = matches[i].entry
      var id = String((entry && entry.id) || "")
      if (!id) continue
      out.push({
        id: id,
        category: root.categoryOf(entry),
        searchExtra: [entry.genericName || "", entry.comment || "", (entry.keywords || []).join(" "), id].join(" "),
        kind: "app",
        name: root.appLibrary.entryName(entry),
        subtext: root.appLibrary.entrySubtext(entry),
        icon: String(entry.icon || ""),
        iconUrl: "",
        monogram: "",
        score: Usage.effectiveScore(root.usage[id], now),
        isNew: root.newIds[id] === true
      })
    }

    out = root.agentRows().map(function(row) { row.category = "Agentes"; return row }).concat(out)
    if (root.searching || root.category === "Configurações") {
      out = out.concat(root.settings.map(function(item) {
        return { id:item.id, kind:"setting", name:item.name, category:"Configurações", searchExtra:item.keywords,
          command:["omarchy-shell", "shell", "toggle", "robertlindomar.omarchy-ptbr." + item.panel],
          icon:"preferences-system", iconUrl:"", monogram:"", subtext:"Configuração do sistema", isNew:false }
      }))
    }
    out = out.filter(function(row) {
      if (root.category !== "Todos" && row.category !== root.category) return false
      row.searchRank = root.matchScore(row.name, row.searchExtra || row.subtext || "", root.filterText)
      return row.searchRank >= 0
    })
    out.sort(function(a,b) {
      return a.searchRank - b.searchRank || String(a.name).localeCompare(String(b.name), "pt-BR")
    })

    root.allRows = out
    root.favoritePool = root.pickFavorites(out)
    root.clampSelection()
  }

  // Agents ship marks for a couple of providers only, so the rest get a
  // monogram tile rather than nine identical terminal icons.
  function agentIconUrl(definition) {
    if (!definition) return ""
    // A custom agent may point at a file; a bare name falls through to the
    // themed lookup the app tiles already use.
    var custom = String(definition.icon || "")
    if (custom.indexOf("file://") === 0) return custom
    if (custom.charAt(0) === "/") return Util.fileUrl(custom)
    if (!definition.asset) return ""
    var dir = root.omarchyPath + "/shell/plugins/agents/assets/"
    var light = root.isLightSurface() ? dir + definition.asset + "-light.svg" : ""
    // Same convention the agents panel uses: <id>-light.svg on light surfaces
    // when one ships, otherwise <id>.svg.
    if (light && definition.asset === "codex") return Util.fileUrl(light)
    return Util.fileUrl(dir + definition.asset + ".svg")
  }

  function isLightSurface() {
    var c = root.background
    function channel(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return (0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)) >= 0.5
  }

  // A themed icon name (not a path) is resolved by AppLibrary like any app icon.
  function agentThemedIcon(definition) {
    var custom = String((definition && definition.icon) || "")
    if (!custom || custom.charAt(0) === "/" || custom.indexOf("file://") === 0) return ""
    return custom
  }

  // The monogram is the fallback: only drawn when no mark and no themed icon.
  function agentMonogram(definition) {
    if (!definition) return ""
    if (definition.asset || String(definition.icon || "").length > 0) return ""
    return definition.monogram
  }

  // The roster can change while a probe is in flight (the config file loads
  // after open() has already started one), so queue instead of dropping it.
  function probeAgents() {
    if (agentProbe.running) { root.agentProbePending = true; return }
    agentProbe.running = true
  }

  function agentRows() {
    var now = Date.now()
    var out = []
    for (var i = 0; i < root.installedAgents.length; i++) {
      var definition = Agents.definitionFor(root.agentRoster, String(root.installedAgents[i]))
      if (!definition) continue
      var id = Agents.rowId(definition.id)
      out.push({
        id: id,
        agentId: definition.id,
        kind: "agent",
        name: definition.name,
        subtext: "Agente de código",
        icon: root.agentThemedIcon(definition),
        iconUrl: root.agentIconUrl(definition),
        monogram: root.agentMonogram(definition),
        argv: definition.argv,
        score: Usage.effectiveScore(root.usage[id], now),
        isNew: root.newIds[id] === true
      })
    }
    if (!root.searching) return out
    var matched = []
    for (var j = 0; j < out.length; j++)
      if (Agents.matches(out[j], root.filterText)) matched.push(out[j])
    return matched
  }

  // Apps with no recorded launch never appear here, so a fresh install shows no
  // section at all rather than an arbitrary one.
  function pickFavorites(rows) {
    var scored = []
    for (var i = 0; i < rows.length; i++)
      if (root.favorites[rows[i].id] === true) scored.push(rows[i])
    return scored
  }

  function setFilter(next) {
    root.filterText = next
    root.rebuild()
    root.resetSelection()
    allGrid.positionViewAtBeginning()
  }

  function rowsFor(section) {
    return section === "favorites" ? root.favoriteRows : root.allRows
  }

  function rowAt(section, index) {
    var rows = root.rowsFor(section)
    if (index < 0 || index >= rows.length) return null
    return rows[index]
  }

  function selectedRow() {
    return root.rowAt(root.selectedSection, root.selectedIndex)
  }

  function select(section, index) {
    root.selectedSection = section
    root.selectedIndex = index
  }

  function resetSelection() {
    root.select(root.showFavorites ? "favorites" : "all", 0)
  }

  function clampSelection() {
    var rows = root.rowsFor(root.selectedSection)
    if (rows.length === 0) { root.resetSelection(); return }
    if (root.selectedIndex >= rows.length) root.selectedIndex = rows.length - 1
    if (root.selectedIndex < 0) root.selectedIndex = 0
  }

  // Arrow keys move within a section; up/down cross the divider, keeping the
  // column so the caret lands where the eye expects it.
  function moveSelection(dx, dy) {
    root.interacted = true
    var columns = Math.max(1, panel.columns)
    var rows = root.rowsFor(root.selectedSection)
    if (rows.length === 0) return

    if (dx !== 0) {
      root.selectedIndex = Math.max(0, Math.min(rows.length - 1, root.selectedIndex + dx))
      return
    }

    var column = root.selectedIndex % columns
    if (dy > 0) {
      if (root.selectedSection === "favorites" && root.selectedIndex + columns >= rows.length) {
        if (root.allRows.length === 0) return
        root.select("all", Math.min(column, root.allRows.length - 1))
        return
      }
      root.selectedIndex = Math.min(rows.length - 1, root.selectedIndex + columns)
      return
    }

    if (root.selectedSection === "all" && root.selectedIndex < columns) {
      if (!root.showFavorites) return
      root.select("favorites", Math.min((Math.ceil(root.favoriteRows.length / columns) - 1) * columns + column, root.favoriteRows.length - 1))
      return
    }
    root.selectedIndex = Math.max(0, root.selectedIndex - columns)
  }

  // ------------------------------------------------------------ launching

  // Do NOT call shell.appLibrary.launch / localAppLibrary.launch — both hit
  // "Property 'launch' of object QObject_QML_* is not a function" (invalid
  // QQmlVMEMetaObject context) from this third-party overlay. Exec the same
  // uwsm-app + gtk-launch line AppLibrary uses, via Util (module singleton).
  function launchDesktop(id) {
    var desktopId = String(id || "")
    if (!desktopId) return
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(desktopId + ".desktop"))
  }

  function removeDesktop(id, name) {
    var desktopId = String(id || "")
    if (!desktopId) return
    Util.execDetached("omarchy-remove-launcher-entry " + Util.shellQuote(desktopId) + " " + Util.shellQuote(String(name || desktopId)))
  }

  function launch(row) {
    if (!row) return
    if (row.kind === "setting") { Quickshell.execDetached(row.command); root.dismiss(); return }
    if (row.kind === "agent") { root.launchAgent(row); return }
    var id = String(row.id || "")
    var name = String(row.name || "")
    root.usage = Usage.record(root.usage, id, Date.now())
    root.persistUsage()
    // Start the app before dismiss so we never rely on component methods
    // after the overlay begins tearing down.
    root.launchDesktop(id)
    root.dismiss()
  }

  // Agents are CLIs, so they go into a terminal through omarchy-launch-tui with
  // the shared org.omarchy.agent app-id — the same window class Omarchy's own
  // agent keybinding produces, so existing window rules still apply. Starting in
  // ~/Work mirrors omarchy-agent: agents refuse to remember trust for $HOME.
  function launchAgent(row) {
    if (!row) return
    root.usage = Usage.record(root.usage, row.id, Date.now())
    root.persistUsage()

    var quoted = []
    for (var i = 0; i < row.argv.length; i++) quoted.push(Util.shellQuote(String(row.argv[i])))
    Util.execDetached('[[ -d "$HOME/Work" ]] && cd "$HOME/Work"; exec omarchy-launch-tui --app-id=org.omarchy.agent ' + quoted.join(" "))
    root.dismiss()
  }

  // Sets the default and launches it — that is what the omarchy command does.
  function setDefaultAgent(row) {
    if (!row || !row.agentId) return
    root.dismiss()
    Util.execDetached("omarchy default agent " + Util.shellQuote(row.agentId))
  }

  function launchSelected() {
    root.launch(root.selectedRow())
  }

  // .desktop Actions ("New Window", "New Incognito Window", ...). AppLibrary's
  // gtk-launch path can't address an action, so run the action's own argv
  // under the same uwsm scope the shell uses for apps.
  function launchAction(row, action) {
    if (!row || !action) return
    var id = String(row.id || "")
    root.usage = Usage.record(root.usage, id, Date.now())
    root.persistUsage()

    var argv = action.command || []
    if (argv.length > 0) {
      var quoted = []
      for (var i = 0; i < argv.length; i++) quoted.push(Util.shellQuote(String(argv[i])))
      Util.execDetached("uwsm-app -- " + quoted.join(" "))
    } else {
      try { action.execute() } catch (e) { console.warn("app-grid: action execute failed:", e) }
    }
    root.dismiss()
  }

  function actionsFor(row) {
    if (!row) return []
    var entry = DesktopEntries.byId(row.id)
    return (entry && entry.actions) ? entry.actions : []
  }

  function removeEntry(row) {
    if (!row) return
    var id = String(row.id || "")
    var name = String(row.name || "")
    root.removeDesktop(id, name)
    root.dismiss()
  }

  function resetUsage(row) {
    if (!row) return
    root.usage = Usage.forget(root.usage, row.id)
    root.persistUsage()
    root.rebuild()
  }

  // ------------------------------------------------------- new-app badges

  function refreshNewIds() {
    if (!root.seenLoaded) return
    var live = root.liveIdMap()
    var next = ({})
    for (var id in live) if (root.seenIds[id] !== true) next[id] = true
    root.newIds = next
  }

  function markAllSeen() {
    var live = root.liveIdMap()
    root.seenIds = live
    root.newIds = ({})
    seenFile.setText(Usage.serializeSeen(live))
    // An app that is gone has no score worth keeping.
    var pruned = Usage.prune(root.usage, live)
    if (JSON.stringify(pruned) !== JSON.stringify(root.usage)) {
      root.usage = pruned
      root.persistUsage()
    }
  }

  function toggleFavorite(row) {
    if (!row || row.kind === "setting") return
    var next = ({})
    for (var id in root.favorites) next[id] = true
    if (next[row.id]) delete next[row.id]
    else next[row.id] = true
    root.favorites = next
    favoritesFile.setText(Usage.serializeSeen(next))
    root.rebuild()
    // Keep the same app selected when the favorites section changes.
    for (var i = 0; i < root.allRows.length; i++) {
      if (root.allRows[i].id === row.id) { root.select("all", i); break }
    }
  }

  function persistUsage() {
    usageFile.setText(Usage.serializeUsage(root.usage))
  }

  Component.onCompleted: Util.execDetached("mkdir -p " + Util.shellQuote(root.stateDir))

  // Non-login shell on purpose: the shell's PATH already carries the mise
  // shims, and sourcing the profile would touch ~/.local/share, which the
  // desktop-entry watcher monitors.
  Process {
    id: agentProbe
    command: ["bash", "-c", Agents.probeCommand(root.agentRoster)]
    stdout: SplitParser {
      onRead: function(line) {
        var id = String(line || "").trim()
        if (id.length > 0) root.pendingAgents.push(id)
      }
    }
    onStarted: root.pendingAgents = []
    onExited: {
      root.installedAgents = root.pendingAgents.slice()
      root.refreshNewIds()
      root.rebuild()
      if (root.agentProbePending) {
        root.agentProbePending = false
        agentProbe.running = true
      }
    }
  }

  FileView {
    path: root.agentConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.customAgents = Agents.parseCustom(text())
      root.probeAgents()
    }
    onFileChanged: reload()
    onLoadFailed: {
      root.customAgents = []
      root.rebuild()
    }
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/defaults/agent"
    watchChanges: true
    printErrors: false
    onLoaded: root.defaultAgent = String(text() || "").trim()
    onFileChanged: reload()
    onLoadFailed: root.defaultAgent = ""
  }

  FileView {
    id: favoritesFile
    path: root.stateDir + "/favorites.json"
    atomicWrites: true
    watchChanges: true
    printErrors: false
    onLoaded: { root.favorites = Usage.parseSeen(text()) || ({}); root.rebuild() }
    onFileChanged: reload()
    onLoadFailed: { root.favorites = ({}); root.rebuild() }
  }

  FileView {
    id: usageFile
    path: root.stateDir + "/usage.json"
    atomicWrites: true
    printErrors: false
    onLoaded: { root.usage = Usage.parseUsage(text()); root.rebuild() }
    onLoadFailed: { root.usage = ({}); root.rebuild() }
  }

  FileView {
    id: seenFile
    path: root.stateDir + "/seen.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var parsed = Usage.parseSeen(text())
      root.seenIds = parsed || ({})
      root.seenLoaded = true
      // A missing/corrupt file means first run: adopt the current list as the
      // baseline instead of badging every installed app as new.
      if (!parsed) root.markAllSeen()
      else root.refreshNewIds()
      root.rebuild()
    }
    onLoadFailed: {
      root.seenIds = ({})
      root.seenLoaded = true
      root.markAllSeen()
      root.rebuild()
    }
  }

  // The app set changed under us — a package landed, a web app was added, an
  // entry was removed. Reflow immediately; that is the whole point.
  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      root.refreshNewIds()
      root.rebuild()
    }
  }

  // ------------------------------------------------------------------ UI

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-app-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // Whole columns only, so the grid sits centered without a ragged gutter.
    // The scroll bar lives in the margin beside it.
    readonly property int maxGridWidth: Math.min(Style.space(880), panel.width - Style.gapsOut * 2 - root.contentMargin * 2 - root.scrollBarWidth - Style.spacing.md)
    readonly property int columns: Math.max(1, Math.floor(maxGridWidth / root.cellWidth))
    readonly property int gridWidth: columns * root.cellWidth

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: panel.gridWidth + root.contentMargin * 2 + root.scrollBarWidth + Style.spacing.md
      height: Math.min(Style.space(620), panel.height - Style.gapsOut * 2)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: contextMenu.hide()
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (contextMenu.visible) {
            if (event.key === Qt.Key_Escape) { contextMenu.hide(); event.accepted = true }
            return
          }

          if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
            root.toggleFavorite(root.selectedRow())
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else if (root.category !== "Todos") root.setCategory("Todos")
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.cycleCategory((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.launchSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.moveSelection(1, 0); event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.moveSelection(-1, 0); event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.moveSelection(0, 1); event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.moveSelection(0, -1); event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.resetSelection(); event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.select("all", Math.max(0, root.allRows.length - 1)); event.accepted = true
          } else if (event.key === Qt.Key_Menu) {
            contextMenu.showForSelection(); event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Item {
        id: content
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        // ---------------------------------------------------------- header

        Item {
          id: header
          anchors { top: parent.top; left: parent.left; right: parent.right }
          height: root.headerHeight

          Text {
            id: query
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: parent.width - counter.width - Style.spacing.lg
            text: root.filterText || "Buscar aplicativos e configurações…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideLeft
          }

          Rectangle {
            id: caret
            anchors.verticalCenter: query.verticalCenter
            x: Math.min(query.x + query.contentWidth + Style.space(2), query.x + query.width)
            width: Math.max(1, Style.space(1))
            height: Style.font.heading
            color: root.foreground
            visible: root.filterText.length > 0
            opacity: 0.8
            SequentialAnimation on opacity {
              running: caret.visible
              loops: Animation.Infinite
              NumberAnimation { to: 0.05; duration: 520 }
              NumberAnimation { to: 0.8; duration: 520 }
            }
          }

          Text {
            id: counter
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: {
              var agents = 0
              for (var i = 0; i < root.allRows.length; i++)
                if (root.allRows[i].kind === "agent") agents++
              var apps = root.allRows.length - agents
              var label = apps + (apps === 1 ? " aplicativo" : " aplicativos")
              if (agents > 0) label += " · " + agents + (agents === 1 ? " agente" : " agentes")
              return label
            }
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Flickable {
          id: categoryBar
          anchors { top: header.bottom; left: parent.left; right: parent.right }
          height: Style.space(42)
          contentWidth: categoryRow.width
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          Row {
            id: categoryRow
            spacing: Style.space(6)
            Repeater {
              model: root.categories
              delegate: Rectangle {
                required property string modelData
                width: categoryText.implicitWidth + Style.space(18)
                height: Style.space(30)
                radius: Style.space(8)
                color: root.category === modelData ? root.accent : "transparent"
                Text {
                  id: categoryText
                  anchors.centerIn: parent
                  text: modelData
                  color: root.category === parent.modelData ? root.background : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea { anchors.fill: parent; onClicked: root.setCategory(parent.modelData) }
              }
            }
          }
        }

        Rectangle {
          id: headerRule
          anchors { top: categoryBar.bottom; left: parent.left; right: parent.right }
          height: Math.max(1, Style.space(1))
          color: root.foreground
          opacity: 0.12
        }

        // ------------------------------------------------- frequently used

        Text {
          id: favoritesLabel
          visible: root.showFavorites
          anchors { top: headerRule.bottom; left: parent.left }
          height: visible ? root.sectionLabelHeight : 0
          verticalAlignment: Text.AlignVCenter
          text: "Favoritos"
          color: root.foreground
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        GridView {
          id: favoritesGrid
          visible: root.showFavorites
          anchors { top: favoritesLabel.bottom; horizontalCenter: parent.horizontalCenter }
          width: panel.gridWidth
          height: visible ? root.cellHeight * Math.min(2, Math.ceil(root.favoriteRows.length / panel.columns)) : 0
          cellWidth: root.cellWidth
          cellHeight: root.cellHeight
          interactive: true
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.favoriteRows
          delegate: tileComponent

          property string section: "favorites"
        }

        Rectangle {
          id: sectionRule
          visible: root.showFavorites
          anchors { top: favoritesGrid.bottom; left: parent.left; right: parent.right }
          anchors.topMargin: visible ? Style.spacing.sm : 0
          height: visible ? Math.max(1, Style.space(1)) : 0
          color: root.foreground
          opacity: 0.12
        }

        // ------------------------------------------------------- all apps

        Text {
          id: allLabel
          visible: root.showFavorites
          anchors { top: sectionRule.bottom; left: parent.left }
          height: visible ? root.sectionLabelHeight : 0
          verticalAlignment: Text.AlignVCenter
          text: "Todos os aplicativos"
          color: root.foreground
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Item {
          id: allArea
          anchors {
            top: allLabel.visible ? allLabel.bottom : headerRule.bottom
            bottom: footer.top
            left: parent.left
            right: parent.right
            topMargin: Style.spacing.md
            bottomMargin: Style.spacing.xs
          }

          // Snap the viewport to whole rows so the last visible row is never
          // sliced in half — the scroll bar is what says "there is more".
          readonly property int visibleRows: Math.max(1, Math.floor(height / root.cellHeight))

          GridView {
            id: allGrid
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: panel.gridWidth
            height: allArea.visibleRows * root.cellHeight
            clip: true
            cellWidth: root.cellWidth
            cellHeight: root.cellHeight
            model: root.allRows
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: root.cellHeight * 4
            delegate: tileComponent

            property string section: "all"
          }

          // Scroll bar: track in the right margin, handle sized by how much of
          // the list fits. Drag it, or click the track to jump.
          Rectangle {
            id: scrollTrack
            visible: allGrid.contentHeight > allGrid.height
            anchors {
              right: parent.right
              top: allGrid.top
              bottom: allGrid.bottom
            }
            width: root.scrollBarWidth
            radius: width / 2
            color: root.foreground
            opacity: 0.1

            readonly property real maxContentY: Math.max(1, allGrid.contentHeight - allGrid.height)

            MouseArea {
              anchors.fill: parent
              onClicked: function(mouse) {
                var ratio = Math.max(0, Math.min(1, (mouse.y - scrollHandle.height / 2) / Math.max(1, scrollTrack.height - scrollHandle.height)))
                allGrid.contentY = ratio * scrollTrack.maxContentY
              }
            }
          }

          Rectangle {
            id: scrollHandle
            visible: scrollTrack.visible
            x: scrollTrack.x
            width: scrollTrack.width
            radius: width / 2
            color: root.foreground
            opacity: handleArea.pressed ? 0.5 : (handleArea.containsMouse ? 0.38 : 0.26)

            height: Math.max(Style.space(28), scrollTrack.height * Math.min(1, allGrid.height / Math.max(1, allGrid.contentHeight)))
            y: scrollTrack.y + (allGrid.contentY / scrollTrack.maxContentY) * (scrollTrack.height - height)

            Behavior on opacity { NumberAnimation { duration: 90 } }

            MouseArea {
              id: handleArea
              anchors.fill: parent
              hoverEnabled: true
              preventStealing: true

              property real grabOffset: 0

              onPressed: function(mouse) { handleArea.grabOffset = mouse.y }
              onPositionChanged: function(mouse) {
                if (!handleArea.pressed) return
                // Work in track space and drive contentY directly; binding the
                // handle's y to both the drag and the view would loop.
                var trackY = scrollHandle.y + mouse.y - handleArea.grabOffset - scrollTrack.y
                var span = Math.max(1, scrollTrack.height - scrollHandle.height)
                var ratio = Math.max(0, Math.min(1, trackY / span))
                allGrid.contentY = ratio * scrollTrack.maxContentY
              }
            }
          }
        }

        Text {
          anchors.centerIn: allArea
          visible: root.allRows.length === 0
          text: root.filterText ? "Nenhum resultado para “" + root.filterText + "”" : "Nenhum aplicativo nesta categoria"
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        // ---------------------------------------------------------- footer

        Item {
          id: footer
          anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
          height: root.footerHeight

          Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            text: "Tab categorias · ↵ abrir · Ctrl+F favoritos · Esc voltar/fechar"
            color: root.foreground
            opacity: 0.35
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            visible: contextMenu.newCount > 0
            text: contextMenu.newCount + " novos"
            color: root.accent
            opacity: 0.8
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ------------------------------------------------------------ tile

        Component {
          id: tileComponent

          Item {
            id: tile
            required property var modelData
            required property int index

            readonly property string section: GridView.view ? GridView.view.section : "all"
            readonly property bool selected: root.selectedSection === tile.section && root.selectedIndex === tile.index

            width: root.cellWidth
            height: root.cellHeight

            Rectangle {
              anchors.fill: parent
              anchors.margins: Style.spacing.xs
              radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(6)
              color: tile.selected ? Style.selectedFill : (hover.hovered ? Style.hoverFill : "transparent")
              border.width: tile.selected ? Math.max(1, Style.selectedBorderWidth) : 0
              border.color: Style.selectedBorderColor
            }

            Column {
              anchors.centerIn: parent
              spacing: Style.spacing.sm

              Item {
                width: root.iconSize
                height: root.iconSize
                anchors.horizontalCenter: parent.horizontalCenter

                Image {
                  anchors.fill: parent
                  visible: !monogram.visible
                  source: tile.modelData.iconUrl
                    ? tile.modelData.iconUrl
                    : (root.appLibrary ? root.appLibrary.iconSource(tile.modelData.icon) : "")
                  sourceSize.width: root.iconSize * 2
                  sourceSize.height: root.iconSize * 2
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  smooth: true
                  mipmap: true
                }

                // Agents without a shipped mark get a monogram rather than yet
                // another generic terminal icon.
                Rectangle {
                  id: monogram
                  visible: String(tile.modelData.monogram || "").length > 0
                  anchors.centerIn: parent
                  width: Math.round(root.iconSize * 0.82)
                  height: width
                  radius: Math.max(Style.space(6), width * 0.22)
                  color: Style.normalFill
                  border.width: Math.max(1, Style.normalBorderWidth)
                  border.color: Style.normalBorderColor

                  Text {
                    anchors.centerIn: parent
                    text: tile.modelData.monogram
                    color: root.foreground
                    opacity: 0.9
                    font.family: root.fontFamily
                    font.pixelSize: Math.round(monogram.width * 0.42)
                  }
                }

                // "Just added": this .desktop file appeared since the last
                // time the grid was closed.
                Rectangle {
                  visible: tile.modelData.isNew === true
                  anchors { right: parent.right; top: parent.top }
                  anchors.rightMargin: -Style.space(2)
                  anchors.topMargin: -Style.space(2)
                  width: Style.space(9)
                  height: width
                  radius: width / 2
                  color: root.accent
                  border.width: Math.max(1, Style.space(1))
                  border.color: root.background
                }
              }

              Text {
                width: root.cellWidth - Style.spacing.md * 2
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                text: tile.modelData.name
                color: root.foreground
                opacity: tile.selected ? 1 : 0.85
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
              }
            }

            HoverHandler {
              id: hover
              onHoveredChanged: {
                if (!hovered || contextMenu.visible) return
                root.interacted = true
                root.select(tile.section, tile.index)
              }
            }

            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: function(mouse) {
                root.select(tile.section, tile.index)
                if (mouse.button === Qt.RightButton) {
                  var point = tile.mapToItem(content, mouse.x, mouse.y)
                  contextMenu.showAt(point.x, point.y)
                } else {
                  root.launch(tile.modelData)
                }
              }
            }
          }
        }

        // ---------------------------------------------------- context menu

        MouseArea {
          anchors.fill: parent
          visible: contextMenu.visible
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: contextMenu.hide()
        }

        Rectangle {
          id: contextMenu
          visible: false
          z: 10

          property var row: null
          property var items: []
          readonly property int newCount: {
            var n = 0
            for (var id in root.newIds) n++
            return n
          }

          function hide() {
            contextMenu.visible = false
            contextMenu.row = null
            contextMenu.items = []
          }

          function showForSelection() {
            var target = root.selectedRow()
            if (!target) return
            contextMenu.buildFor(target)
            contextMenu.x = (content.width - contextMenu.width) / 2
            contextMenu.y = (content.height - contextMenu.height) / 2
            contextMenu.visible = true
          }

          function showAt(px, py) {
            var target = root.selectedRow()
            if (!target) return
            contextMenu.buildFor(target)
            contextMenu.x = Math.max(0, Math.min(px, content.width - contextMenu.width))
            contextMenu.y = Math.max(0, Math.min(py, content.height - contextMenu.height))
            contextMenu.visible = true
          }

          function buildFor(target) {
            contextMenu.row = target
            var entries = [{ label: "Abrir " + target.name, kind: "launch", action: null }]
            if (target.kind === "setting") { contextMenu.items = entries; return }

            entries.push({ label: root.favorites[target.id] ? "Remover dos favoritos (Ctrl+F)" : "Adicionar aos favoritos (Ctrl+F)", kind: "favorite", action: null })

            // An agent has no desktop entry: no .desktop actions to offer, and
            // nothing for omarchy-remove-launcher-entry to remove.
            if (target.kind === "agent") {
              if (root.defaultAgent !== target.agentId)
                entries.push({ label: "Definir como agente padrão", kind: "default-agent", action: null })
              contextMenu.items = entries
              return
            }

            var actions = root.actionsFor(target)
            for (var i = 0; i < actions.length; i++)
              entries.push({ label: String(actions[i].name || "Ação"), kind: "action", action: actions[i] })
            entries.push({ label: "Remover do launcher…", kind: "remove", action: null })
            contextMenu.items = entries
          }

          function run(item) {
            var target = contextMenu.row
            contextMenu.hide()
            if (!target || !item) return
            if (item.kind === "launch") root.launch(target)
            else if (item.kind === "action") root.launchAction(target, item.action)
            else if (item.kind === "default-agent") root.setDefaultAgent(target)
            else if (item.kind === "favorite") root.toggleFavorite(target)
            else if (item.kind === "remove") root.removeEntry(target)
          }

          width: Math.min(Style.space(280), content.width)
          height: menuColumn.height + Style.spacing.sm * 2
          radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(6)
          color: root.background
          border.width: Math.max(1, Style.normalBorderWidth)
          border.color: root.border

          MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

          Column {
            id: menuColumn
            y: Style.spacing.sm
            width: parent.width

            Repeater {
              model: contextMenu.items

              delegate: Rectangle {
                required property var modelData
                width: menuColumn.width
                height: Style.spacing.popupRowHeight
                color: itemHover.hovered ? Style.hoverFill : "transparent"

                Text {
                  anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: Style.spacing.rowPaddingX
                    rightMargin: Style.spacing.rowPaddingX
                  }
                  text: modelData.label
                  color: modelData.kind === "remove" ? Color.urgent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                HoverHandler { id: itemHover }
                MouseArea {
                  anchors.fill: parent
                  onClicked: contextMenu.run(modelData)
                }
              }
            }
          }
        }
      }
    }
  }

  onFavoriteRowsChanged: if (!root.interacted) root.resetSelection()

  // Keep the keyboard selection inside the visible rows of the all-apps grid.
  onSelectedIndexChanged: (root.selectedSection === "all" ? allGrid : favoritesGrid).positionViewAtIndex(root.selectedIndex, GridView.Contain)
  onSelectedSectionChanged: (root.selectedSection === "all" ? allGrid : favoritesGrid).positionViewAtIndex(root.selectedIndex, GridView.Contain)
}
