// reset1 macOS defaults v26.10.2b — run with deno, or the page's heredoc.
/**
 * Finder, keyboard, Dock, screenshot and zoom defaults worth setting on a fresh Mac.
 *
 * Every change below is a plain `defaults write`, so every change is reversible —
 * the revert command is printed at the end. Each setting is read *before* it is
 * written and read back *after*, so the run reports what actually changed and
 * verifies the value landed rather than trusting the exit code.
 *
 * Run it read-only to just look at the machine, changing nothing:
 *
 *   deno run -A setup-defaults.ts --check
 *
 * Or watch a domain to discover which key a System Settings toggle actually
 * writes — the reliable way to find a key name on a macOS version you do not
 * already know by heart:
 *
 *   deno run -A setup-defaults.ts --watch com.apple.universalaccess
 *
 * One kind of setting cannot be applied from here and is printed for you to run
 * yourself instead: `com.apple.universalaccess` (zoom) is protected by a macOS
 * privacy control, so it only accepts writes from a process holding Full Disk
 * Access.
 *
 * Power settings live in their own script — they need sudo rather than Full
 * Disk Access, and `pmset` is not `defaults`.
 */
/* ── Output and process helpers, inlined so this runs on a Mac without the repo ── */

const BOLD = "\x1b[1m", DIM = "\x1b[2m", GREEN = "\x1b[32m", AMBER = "\x1b[33m";
const RED = "\x1b[31m", BLUE = "\x1b[34m", RESET = "\x1b[0m";

const heading = (text: string) => console.log(`\n${BOLD}${text}${RESET}`);
const ok = (text: string) => console.log(`  ${GREEN}✓${RESET} ${text}`);
const todo = (text: string) => console.log(`  ${AMBER}•${RESET} ${text}`);
const fail = (text: string) => console.log(`  ${RED}✕${RESET} ${text}`);
const info = (text: string) => console.log(`  ${DIM}${text}${RESET}`);
/** A command the person should run themselves. */
const suggest = (command: string) => console.log(`\n  ${BLUE}${command}${RESET}`);

type CellColor = "green" | "amber" | "red" | "blue" | "dim" | "bold";
type Cell = { text: string; color?: CellColor };
type Row = (string | Cell)[];
const COLORS: Record<CellColor, string> = { green: GREEN, amber: AMBER, red: RED, blue: BLUE, dim: DIM, bold: BOLD };

function table(headers: string[], rows: Row[], maxColumnWidth = 44): void {
  if (rows.length === 0) return;
  const clip = (text: string) => {
    const flat = text.replace(/\s+/g, " ").trim();
    return flat.length <= maxColumnWidth ? flat : `${flat.slice(0, maxColumnWidth - 1)}…`;
  };
  const body = rows.map((row) => row.map((value) => typeof value === "string" ? { text: value } : value).map((cell): Cell => ({ ...cell, text: clip(cell.text) })));
  const head = headers.map(clip);
  const widths = head.map((header, index) => Math.max(header.length, ...body.map((row) => row[index]?.text.length ?? 0)));
  const last = widths.length - 1;
  const pad = (cell: Cell, width: number) => {
    const padded = cell.text.padEnd(width);
    return cell.color ? `${COLORS[cell.color]}${padded}${RESET}` : padded;
  };
  const render = (cells: Cell[]) => `  ${cells.map((cell, index) => pad(cell, index === last ? 0 : widths[index]!)).join("  ").trimEnd()}`;
  console.log(render(head.map((text) => ({ text, color: "bold" }))));
  console.log(render(widths.map((width) => ({ text: "─".repeat(width), color: "dim" }))));
  for (const row of body) console.log(render(widths.map((_, index) => row[index] ?? { text: "" })));
}

function spawn(args: string[], options: { stdout?: "pipe" | "inherit"; stderr?: "ignore" | "inherit" } = {}) {
  const [command, ...rest] = args;
  const child = new Deno.Command(command!, {
    args: rest,
    stdin: "null",
    stdout: options.stdout === "pipe" ? "piped" : "inherit",
    stderr: options.stderr === "ignore" ? "null" : "inherit",
  }).spawn();
  return { stdout: child.stdout, exited: child.status.then((status) => status.code) };
}

/** Waits for Return. Reads the terminal itself: when pasted as a heredoc, stdin is this script. */
async function waitForEnter(): Promise<void> {
  try {
    using tty = await Deno.open("/dev/tty", { read: true });
    await tty.read(new Uint8Array(1024));
  } catch {
    // No terminal to read from: carry on rather than block.
  }
}

/** One line typed at the terminal, or null when there is no terminal to ask. */
async function ask(question: string): Promise<string | null> {
  try {
    using tty = await Deno.open("/dev/tty", { read: true, write: true });
    await tty.write(new TextEncoder().encode(question));
    const buffer = new Uint8Array(1024);
    const count = await tty.read(buffer);
    return new TextDecoder().decode(buffer.subarray(0, count ?? 0)).trim();
  } catch {
    return null;
  }
}

const CHECK_ONLY = Deno.args.includes("--check") || Deno.args.includes("--dry-run");

type SettingType = "bool" | "int" | "float" | "string" | "intDict";

interface Setting {
  group: string;
  domain: string;
  key: string;
  type: SettingType;
  value: string;
  description: string;
  /** Per-host settings live outside the shared domain and need `-currentHost`. */
  currentHost?: boolean;
}

/**
 * Domains macOS guards with a privacy control. A write succeeds only if the
 * process running this script — the console server, or the terminal that
 * launched it — has Full Disk Access. Probed once, up front.
 */
const PROTECTED_DOMAINS = ["com.apple.universalaccess"];

const SCREENSHOT_DIR = `${Deno.env.get("HOME")}/Desktop/screenshots`;

const SETTINGS: Setting[] = [
  // ── Save dialogs ────────────────────────────────────────────────────────
  { group: "Dialogs", domain: "NSGlobalDomain", key: "NSNavPanelExpandedStateForSaveMode", type: "bool", value: "true", description: "Save dialogs open expanded" },
  { group: "Dialogs", domain: "NSGlobalDomain", key: "NSNavPanelExpandedStateForSaveMode2", type: "bool", value: "true", description: "Save dialogs open expanded (newer apps)" },
  { group: "Dialogs", domain: "NSGlobalDomain", key: "PMPrintingExpandedStateForPrint", type: "bool", value: "true", description: "Print dialogs open expanded" },
  { group: "Dialogs", domain: "NSGlobalDomain", key: "PMPrintingExpandedStateForPrint2", type: "bool", value: "true", description: "Print dialogs open expanded (newer apps)" },
  { group: "Dialogs", domain: "com.apple.print.PrintingPrefs", key: "Quit When Finished", type: "bool", value: "true", description: "Preview quits once printing is done" },

  // ── Scrolling ───────────────────────────────────────────────────────────
  { group: "Scrolling", domain: "NSGlobalDomain", key: "AppleShowScrollBars", type: "string", value: "WhenScrolling", description: "Show scroll bars only while scrolling" },
  { group: "Scrolling", domain: "NSGlobalDomain", key: "AppleScrollerPagingBehavior", type: "bool", value: "true", description: "Click the scroll bar to jump to that spot" },

  // ── Trackpad ────────────────────────────────────────────────────────────
  { group: "Trackpad", domain: "NSGlobalDomain", key: "com.apple.mouse.tapBehavior", type: "int", value: "0", description: "Tap to click off" },

  // ── Text ────────────────────────────────────────────────────────────────
  { group: "Text", domain: "NSGlobalDomain", key: "NSAutomaticCapitalizationEnabled", type: "bool", value: "false", description: "No automatic capitalization" },
  { group: "Text", domain: "NSGlobalDomain", key: "NSAutomaticDashSubstitutionEnabled", type: "bool", value: "false", description: "Do not replace double hyphens with em dashes" },
  { group: "Text", domain: "NSGlobalDomain", key: "NSAutomaticQuoteSubstitutionEnabled", type: "bool", value: "false", description: "Use straight quotes" },
  { group: "Text", domain: "NSGlobalDomain", key: "NSAutomaticPeriodSubstitutionEnabled", type: "bool", value: "false", description: "Do not insert a period after a double-space" },
  { group: "Text", domain: "NSGlobalDomain", key: "ApplePressAndHoldEnabled", type: "bool", value: "false", description: "Hold a key to repeat it, not to pick an accent" },

  // ── Keyboard ────────────────────────────────────────────────────────────
  { group: "Keyboard", domain: "NSGlobalDomain", key: "KeyRepeat", type: "int", value: "2", description: "Fast key repeat" },
  { group: "Keyboard", domain: "NSGlobalDomain", key: "InitialKeyRepeat", type: "int", value: "15", description: "Short delay before repeating" },
  { group: "Keyboard", domain: "NSGlobalDomain", key: "AppleKeyboardUIMode", type: "int", value: "3", description: "Tab moves between every control, not just text fields" },
  { group: "Keyboard", domain: "NSGlobalDomain", key: "com.apple.keyboard.fnState", type: "bool", value: "true", description: "F-keys are F-keys; hold fn for brightness and volume" },

  // ── Files and windows ───────────────────────────────────────────────────
  { group: "Windows", domain: "NSGlobalDomain", key: "AppleShowAllFiles", type: "bool", value: "true", description: "Show hidden files (global)" },
  { group: "Windows", domain: "NSGlobalDomain", key: "AppleShowAllExtensions", type: "bool", value: "false", description: "Hide known file extensions" },
  { group: "Windows", domain: "NSGlobalDomain", key: "AppleActionOnDoubleClick", type: "string", value: "Minimize", description: "Double-clicking a title bar minimizes the window" },
  { group: "Windows", domain: "NSGlobalDomain", key: "NSWindowResizeTime", type: "float", value: "0.001", description: "Near-instant window resize" },
  { group: "Windows", domain: "NSGlobalDomain", key: "NSAutomaticWindowAnimationsEnabled", type: "bool", value: "false", description: "No window open and close animation" },
  { group: "Windows", domain: "NSGlobalDomain", key: "NSWindowShouldDragOnGesture", type: "bool", value: "true", description: "Ctrl-Cmd-drag anywhere in a window to move it" },
  { group: "Windows", domain: "NSGlobalDomain", key: "NSQuitAlwaysKeepsWindows", type: "bool", value: "false", description: "Apps do not reopen their old windows on launch" },
  { group: "Windows", domain: "com.apple.WindowManager", key: "EnableTiledWindowMargins", type: "bool", value: "true", description: "Keep margins around tiled windows" },

  // ── Appearance ──────────────────────────────────────────────────────────
  { group: "Appearance", domain: "NSGlobalDomain", key: "AppleInterfaceStyleSwitchesAutomatically", type: "bool", value: "true", description: "Switch between light and dark appearance automatically" },

  // ── Finder ──────────────────────────────────────────────────────────────
  { group: "Finder", domain: "com.apple.finder", key: "AppleShowAllFiles", type: "bool", value: "false", description: "Hide dotfiles in Finder" },
  { group: "Finder", domain: "com.apple.finder", key: "_FXShowPosixPathInTitle", type: "bool", value: "false", description: "Plain folder name in the Finder title" },
  { group: "Finder", domain: "com.apple.finder", key: "_FXSortFoldersFirst", type: "bool", value: "true", description: "Folders sort above files" },
  { group: "Finder", domain: "com.apple.finder", key: "_FXSortFoldersFirstOnDesktop", type: "bool", value: "true", description: "Folders sort above files on the Desktop too" },
  { group: "Finder", domain: "com.apple.finder", key: "ShowStatusBar", type: "bool", value: "false", description: "No status bar" },
  { group: "Finder", domain: "com.apple.finder", key: "ShowPathbar", type: "bool", value: "false", description: "Hide the path bar" },
  { group: "Finder", domain: "com.apple.finder", key: "FXPreferredViewStyle", type: "string", value: "clmv", description: "Open folders in column view" },
  { group: "Finder", domain: "com.apple.finder", key: "NewWindowTarget", type: "string", value: "PfDe", description: "New windows open at the Desktop" },
  { group: "Finder", domain: "com.apple.finder", key: "FXDefaultSearchScope", type: "string", value: "SCcf", description: "Search the current folder first" },
  { group: "Finder", domain: "com.apple.finder", key: "FXEnableExtensionChangeWarning", type: "bool", value: "false", description: "No nag when changing a file extension" },
  { group: "Finder", domain: "com.apple.finder", key: "ShowHardDrivesOnDesktop", type: "bool", value: "false", description: "Hide internal disks on the Desktop" },
  { group: "Finder", domain: "com.apple.finder", key: "ShowExternalHardDrivesOnDesktop", type: "bool", value: "true", description: "Show external disks on the Desktop" },
  { group: "Finder", domain: "com.apple.finder", key: "ShowRemovableMediaOnDesktop", type: "bool", value: "true", description: "Show removable media on the Desktop" },
  { group: "Finder", domain: "com.apple.finder", key: "FXRemoveOldTrashItems", type: "bool", value: "false", description: "Do not remove Trash items automatically after 30 days" },
  { group: "Finder", domain: "com.apple.finder", key: "WarnOnEmptyTrash", type: "bool", value: "false", description: "Do not warn before emptying the Trash" },
  { group: "Finder", domain: "com.apple.desktopservices", key: "DSDontWriteNetworkStores", type: "bool", value: "true", description: "No .DS_Store on network volumes" },
  { group: "Finder", domain: "com.apple.desktopservices", key: "DSDontWriteUSBStores", type: "bool", value: "true", description: "No .DS_Store on USB volumes" },

  // ── Screenshots ─────────────────────────────────────────────────────────
  { group: "Screenshots", domain: "com.apple.screencapture", key: "location", type: "string", value: SCREENSHOT_DIR, description: "Save to ~/Desktop/screenshots, not loose on the Desktop" },
  { group: "Screenshots", domain: "com.apple.screencapture", key: "type", type: "string", value: "jpg", description: "Save screenshots as JPEG" },
  { group: "Screenshots", domain: "com.apple.screencapture", key: "name", type: "string", value: "screenshot", description: "Name files 'screenshot', not 'Screen Shot'" },
  { group: "Screenshots", domain: "com.apple.screencapture", key: "include-date", type: "bool", value: "true", description: "Keep the timestamp in the filename" },
  { group: "Screenshots", domain: "com.apple.screencapture", key: "disable-shadow", type: "bool", value: "true", description: "Screenshots without the window shadow" },
  { group: "Screenshots", domain: "com.apple.screencapture", key: "show-thumbnail", type: "bool", value: "true", description: "Show the floating thumbnail after capture" },

  // ── Screen saver ────────────────────────────────────────────────────────
  { group: "Screen saver", domain: "com.apple.screensaver", key: "idleTime", type: "int", value: "300", description: "Screen saver after 5 minutes idle", currentHost: true },

  // ── Dock ────────────────────────────────────────────────────────────────
  { group: "Dock", domain: "com.apple.dock", key: "autohide", type: "bool", value: "true", description: "Auto-hide the Dock" },
  { group: "Dock", domain: "com.apple.dock", key: "autohide-delay", type: "float", value: "0", description: "No delay before the Dock appears" },
  { group: "Dock", domain: "com.apple.dock", key: "autohide-time-modifier", type: "float", value: "0.15", description: "Faster Dock animation" },
  { group: "Dock", domain: "com.apple.dock", key: "orientation", type: "string", value: "left", description: "Dock appears on the left" },
  { group: "Dock", domain: "com.apple.dock", key: "tilesize", type: "int", value: "48", description: "Dock icons at 48px" },
  { group: "Dock", domain: "com.apple.dock", key: "magnification", type: "bool", value: "false", description: "Dock magnification off" },
  { group: "Dock", domain: "com.apple.dock", key: "scroll-to-open", type: "bool", value: "true", description: "Scroll up on a Dock icon to open its windows" },
  { group: "Dock", domain: "com.apple.dock", key: "show-recents", type: "bool", value: "false", description: "No recent apps in the Dock" },
  { group: "Dock", domain: "com.apple.dock", key: "no-bouncing", type: "bool", value: "true", description: "Dock icons do not bounce for attention" },
  { group: "Dock", domain: "com.apple.dock", key: "minimize-to-application", type: "bool", value: "true", description: "Minimize into the app's own Dock icon" },
  { group: "Dock", domain: "com.apple.dock", key: "mineffect", type: "string", value: "scale", description: "Scale rather than genie on minimize" },

  // ── Mission Control ─────────────────────────────────────────────────────
  { group: "Mission Control", domain: "com.apple.dock", key: "mru-spaces", type: "bool", value: "false", description: "Do not reorder Spaces by most recent use" },
  { group: "Mission Control", domain: "com.apple.dock", key: "expose-animation-duration", type: "float", value: "0.1", description: "Faster Mission Control animation" },
  { group: "Mission Control", domain: "com.apple.dock", key: "expose-group-apps", type: "bool", value: "true", description: "Group windows by app in Mission Control" },

  // ── Hot corners ─────────────────────────────────────────────────────────
  // 0 is "no action" — the value System Settings writes for "–". (1 also reads
  // as disabled, but it is the older spelling and not what the picker sets.)
  { group: "Hot corners", domain: "com.apple.dock", key: "wvous-br-corner", type: "int", value: "0", description: "Bottom-right corner does nothing" },
  { group: "Hot corners", domain: "com.apple.dock", key: "wvous-br-modifier", type: "int", value: "0", description: "Bottom-right corner has no modifier key" },

  // ── Dwell control (Full Disk Access required) ──────────────────────────
  //
  // These two only describe *how* Dwell behaves; they do not switch it on, and
  // both already hold these values on a stock system — which is why the run
  // reports "already set" and nothing changes. Dwell itself is turned on in
  // System Settings → Accessibility → Pointer Control → Alternate Control
  // Methods, and it does nothing until a head or eye tracking source is active.
  //
  // If you want the master switch in here too, find its key rather than guess:
  //   deno run -A setup-defaults.ts --watch com.apple.universalaccess
  { group: "Dwell", domain: "com.apple.universalaccess", key: "dwellTimeDefaultAction", type: "float", value: "0.25", description: "Perform the default dwell action after 0.25 seconds" },
  { group: "Dwell", domain: "com.apple.universalaccess", key: "virtualKeyboardCornerActionType", type: "intDict", value: "{\"0\":0,\"1\":1,\"2\":0,\"3\":0}", description: "Only the bottom-right dwell corner hides or shows the Home Panel" },

  // ── System maintenance ──────────────────────────────────────────────────
  { group: "System maintenance", domain: "com.apple.SoftwareUpdate", key: "AutomaticCheckEnabled", type: "bool", value: "true", description: "Check for software updates automatically" },
  { group: "System maintenance", domain: "com.apple.SoftwareUpdate", key: "AutomaticDownload", type: "bool", value: "true", description: "Download available updates automatically" },
  { group: "System maintenance", domain: "com.apple.SoftwareUpdate", key: "AutomaticallyInstallMacOSUpdates", type: "bool", value: "true", description: "Install macOS updates automatically" },
  { group: "System maintenance", domain: "com.apple.SoftwareUpdate", key: "CriticalUpdateInstall", type: "bool", value: "true", description: "Install security and system data updates automatically" },
  { group: "System maintenance", domain: "com.apple.SoftwareUpdate", key: "ConfigDataInstall", type: "bool", value: "true", description: "Install system data files automatically" },

  // ── Crash reporting ─────────────────────────────────────────────────────
  { group: "Crash reports", domain: "com.apple.CrashReporter", key: "DialogType", type: "string", value: "none", description: "No crash reporter dialog when an app quits" },

  // ── Zoom (Full Disk Access required) ────────────────────────────────────
  { group: "Zoom", domain: "com.apple.universalaccess", key: "closeViewHotkeysEnabled", type: "bool", value: "true", description: "Zoom keyboard shortcuts on" },
  { group: "Zoom", domain: "com.apple.universalaccess", key: "closeViewScrollWheelToggle", type: "bool", value: "true", description: "Scroll with a modifier key to zoom" },
  { group: "Zoom", domain: "com.apple.universalaccess", key: "closeViewZoomMode", type: "int", value: "3", description: "Zoom follows the pointer in a picture-in-picture window" },
  { group: "Zoom", domain: "com.apple.universalaccess", key: "closeViewScrollWheelModifiersInt", type: "int", value: "4", description: "Control is the zoom modifier" },
];

function defaultsArgs(setting: Setting, verb: "read" | "write"): string[] {
  const scope = setting.currentHost ? ["-currentHost"] : [];
  const value = verb === "write"
    ? setting.type === "intDict"
      ? [
          "-dict",
          ...Object.entries(JSON.parse(setting.value) as Record<string, number>)
            .flatMap(([key, entry]) => [key, "-int", String(entry)]),
        ]
      : [`-${setting.type}`, setting.value]
    : [];
  return ["defaults", ...scope, verb, setting.domain, setting.key, ...value];
}

async function run(args: string[]): Promise<{ code: number; out: string }> {
  const proc = spawn(args, { stdout: "pipe", stderr: "ignore" });
  const out = await new Response(proc.stdout).text();
  return { code: await proc.exited, out: out.trim() };
}

/** The current value, or null when the key has never been set. */
async function readDefault(setting: Setting): Promise<string | null> {
  const { code, out } = await run(defaultsArgs(setting, "read"));
  return code === 0 ? out : null;
}

async function writeDefault(setting: Setting): Promise<boolean> {
  return (await run(defaultsArgs(setting, "write"))).code === 0;
}

/**
 * `defaults read` speaks its own dialect: booleans come back as 1/0, numbers
 * may gain or lose trailing zeroes. Normalise both sides before comparing.
 */
function matches(actual: string | null, setting: Setting): boolean {
  if (actual === null) return false;

  if (setting.type === "intDict") {
    const expected = JSON.parse(setting.value) as Record<string, number>;
    const entries = [...actual.matchAll(/^\s*"?([^"=\s]+)"?\s*=\s*(-?\d+);$/gm)]
      .map(([, key, value]) => [key, Number(value)] as const);
    const found = Object.fromEntries(entries);
    return Object.keys(found).length === Object.keys(expected).length &&
      Object.entries(expected).every(([key, value]) => found[key] === value);
  }

  if (setting.type === "bool") {
    const truthy = (v: string) => ["true", "1", "yes"].includes(v.toLowerCase());
    return truthy(setting.value) === truthy(actual);
  }

  if (setting.type === "int" || setting.type === "float") {
    return Number(actual) === Number(setting.value);
  }

  return actual === setting.value;
}

/** How a value should read in a table cell. */
function show(value: string | null): string {
  return value === null ? "unset" : value;
}

function wanted(setting: Setting): string {
  if (setting.type !== "intDict") return setting.value;
  return Object.entries(JSON.parse(setting.value) as Record<string, number>)
    .map(([key, value]) => `${key}=${value}`)
    .join(", ");
}

function label(setting: Setting): string {
  return `${setting.currentHost ? "-currentHost " : ""}${setting.domain} ${setting.key}`;
}

/**
 * Write a throwaway key to a guarded domain and read it back. This is the only
 * honest test — the permission belongs to whichever process is running us, and
 * `defaults` reports nothing useful about it otherwise.
 */
async function isWritable(domain: string): Promise<boolean> {
  const probe: Setting = {
    group: "probe",
    domain,
    key: "__setupDefaultsProbe",
    type: "bool",
    value: "true",
    description: "probe",
  };

  const wrote = await writeDefault(probe);
  if (wrote) await run(["defaults", "delete", domain, probe.key]);
  return wrote;
}

/* ── Watch: find the key behind a System Settings toggle ───────────────── */

/**
 * Flatten a plist into "a.b.c" → value, so two snapshots can be compared key by
 * key rather than as a wall of text.
 */
function flatten(value: unknown, prefix = ""): Map<string, string> {
  const flat = new Map<string, string>();

  if (value !== null && typeof value === "object" && !Array.isArray(value)) {
    for (const [key, child] of Object.entries(value)) {
      const path = prefix ? `${prefix}.${key}` : key;
      for (const [k, v] of flatten(child, path)) flat.set(k, v);
    }
  } else {
    flat.set(prefix, JSON.stringify(value));
  }

  return flat;
}

/** The whole domain as a flat map, via plist → JSON so nesting survives. */
async function snapshot(domain: string): Promise<Map<string, string>> {
  const tmp = `/tmp/setup-defaults-${domain}-${Date.now()}.plist`;
  if ((await run(["defaults", "export", domain, tmp])).code !== 0) return new Map();

  const { code, out } = await run(["plutil", "-convert", "json", "-o", "-", tmp]);
  await run(["rm", "-f", tmp]);
  if (code !== 0) return new Map();

  try {
    return flatten(JSON.parse(out));
  } catch {
    return new Map();
  }
}


const watchIndex = Deno.args.indexOf("--watch");

if (watchIndex !== -1) {
  const domain = Deno.args[watchIndex + 1];

  if (!domain) {
    fail("--watch needs a domain, e.g. --watch com.apple.universalaccess");
    Deno.exit(1);
  }

  heading(`Watching ${domain}`);

  const first = await snapshot(domain);
  info(`${first.size} keys right now.`);
  info("Go and change the setting in System Settings, then come back here.");
  info("Press return when you have changed it.");

  await waitForEnter();

  const second = await snapshot(domain);
  const keys = [...new Set([...first.keys(), ...second.keys()])].sort();
  const rows: Row[] = [];

  for (const key of keys) {
    const was = first.get(key);
    const now = second.get(key);
    if (was === now) continue;

    rows.push([
      key,
      { text: was ?? "unset", color: "dim" },
      now ?? "unset",
      was === undefined
        ? { text: "added", color: "green" }
        : now === undefined
          ? { text: "removed", color: "red" }
          : { text: "changed", color: "amber" },
    ]);
  }

  heading("What moved");

  if (rows.length === 0) {
    todo("Nothing changed in this domain.");
    info("The toggle may live in another domain, or be stored outside defaults.");
  } else {
    table(["Key", "Was", "Now", ""], rows);
    info("Add the interesting one to SETTINGS above.");
  }

  Deno.exit(0);
}

/* ── System ────────────────────────────────────────────────────────────── */

heading("This Mac");

const [product, build, model, arch, host] = await Promise.all([
  run(["sw_vers", "-productVersion"]),
  run(["sw_vers", "-buildVersion"]),
  run(["sysctl", "-n", "hw.model"]),
  run(["uname", "-m"]),
  run(["scutil", "--get", "ComputerName"]),
]);

table(
  ["", ""],
  [
    ["macOS", `${product.out} (${build.out})`],
    ["Model", model.out],
    ["Architecture", arch.out],
    ["Computer name", host.out],
    ["Mode", CHECK_ONLY ? "--check — reading only, nothing will be written" : "apply"],
  ],
);

/* ── Permissions ───────────────────────────────────────────────────────── */

const blockedDomains = new Set<string>();
if (!CHECK_ONLY) {
  for (const domain of PROTECTED_DOMAINS) {
    if (!(await isWritable(domain))) blockedDomains.add(domain);
  }
}

const blocked = (setting: Setting) => blockedDomains.has(setting.domain);
const protectedInCheck = (setting: Setting) =>
  CHECK_ONLY && PROTECTED_DOMAINS.includes(setting.domain);

/* ── Read ──────────────────────────────────────────────────────────────── */

heading("Current values");

const before = new Map<Setting, string | null>();
const currentRows: Row[] = [];

for (const setting of SETTINGS) {
  const current = await readDefault(setting);
  before.set(setting, current);

  const status: Row[number] = protectedInCheck(setting)
    ? { text: "permission checked on apply", color: "amber" }
    : blocked(setting)
    ? { text: "⚠ not permitted", color: "amber" }
    : matches(current, setting)
      ? { text: "already set", color: "green" }
      : { text: "will change", color: "amber" };

  currentRows.push([
    setting.group,
    setting.description,
    { text: show(current), color: current === null ? "dim" : undefined },
    wanted(setting),
    status,
  ]);
}

table(["Group", "What it does", "Current", "Wanted", ""], currentRows);

if (CHECK_ONLY) {
  const pending = SETTINGS.filter(s => !blocked(s) && !matches(before.get(s) ?? null, s));
  heading("Summary");
  info(`${pending.length} of ${SETTINGS.length} settings differ from what this script would apply.`);
  info("Protected-domain write permission will be checked only in apply mode.");
  suggest("deno run -A setup-defaults.ts   # to apply");
  Deno.exit(0);
}

/* ── Apply ─────────────────────────────────────────────────────────────── */

heading("Applying defaults");

// The screenshot folder has to exist or macOS quietly falls back to the Desktop.
if ((await run(["mkdir", "-p", SCREENSHOT_DIR])).code === 0) ok(`Screenshot folder ready at ${SCREENSHOT_DIR}`);
else fail(`Could not create ${SCREENSHOT_DIR}`);

const changed = new Set<Setting>();
const unchanged: Setting[] = [];
const skipped: Setting[] = [];
const failed: Setting[] = [];

for (const setting of SETTINGS) {
  if (blocked(setting)) {
    skipped.push(setting);
    continue;
  }

  if (matches(before.get(setting) ?? null, setting)) {
    unchanged.push(setting);
    continue;
  }

  if (await writeDefault(setting)) changed.add(setting);
  else {
    failed.push(setting);
    fail(`${setting.description}  (${label(setting)})`);
  }
}

info(
  `${changed.size} changed, ${unchanged.length} already set` +
    (skipped.length > 0 ? `, ${skipped.length} not permitted` : "") +
    (failed.length > 0 ? `, ${failed.length} failed to write` : ""),
);

/* ── Verify ────────────────────────────────────────────────────────────── */

heading("Verifying");

const wrong: Setting[] = [];
const verifyRows: Row[] = [];

for (const setting of SETTINGS) {
  const previous = before.get(setting) ?? null;
  const actual = await readDefault(setting);
  const good = matches(actual, setting);
  if (!good && !blocked(setting)) wrong.push(setting);

  const status: Row[number] = blocked(setting)
    ? { text: "⚠ needs Full Disk Access", color: "amber" }
    : good
      ? { text: changed.has(setting) ? "✓ changed" : "✓ ok", color: "green" }
      : { text: `✕ wanted ${wanted(setting)}`, color: "red" };

  verifyRows.push([
    setting.group,
    label(setting),
    { text: show(previous), color: "dim" },
    show(actual),
    status,
  ]);
}

table(["Group", "Setting", "Was", "Now", ""], verifyRows);

if (wrong.length === 0 && skipped.length === 0) {
  ok(`All ${SETTINGS.length} settings read back correctly`);
}

/* ── Restart ───────────────────────────────────────────────────────────── */

heading("Restarting Finder, the Dock and SystemUIServer");

for (const app of ["Finder", "Dock", "SystemUIServer"]) {
  const { code } = await run(["killall", app]);
  if (code === 0) ok(`${app} restarted`);
  else info(`${app} was not running`);
}

info("Keyboard and zoom settings take full effect at the next login.");

/* ── Things you have to do yourself ────────────────────────────────────── */

if (blockedDomains.size > 0) {
  heading("Needs Full Disk Access");

  todo(`macOS refused writes to: ${[...blockedDomains].join(", ")}`);
  info("These domains are privacy-protected. The permission belongs to whichever");
  info("process runs this script, so grant it to that app — the terminal you ran");
  info("this from, or the console app — then quit and reopen it and run again:");
  info("System Settings → Privacy & Security → Full Disk Access");
  info("");
  info("Or set them by hand from a terminal that already has access:");

  for (const setting of SETTINGS.filter(blocked)) {
    suggest(defaultsArgs(setting, "write").join(" "));
  }
}

heading("Undo");

info("Any single setting goes back to the system default with:");
suggest("defaults delete <domain> <key>");
info("For example: defaults delete com.apple.finder ShowStatusBar");

if (wrong.length > 0) todo(`${wrong.length} setting(s) did not stick — see above`);

/* ── Log out ───────────────────────────────────────────────────────────── */

// Keyboard, trackpad and zoom settings are read at login, so offer to log out now.
if (changed.size > 0) {
  heading("Log out");
  info("Keyboard and zoom changes need a new login. Save your work in other apps first.");
  const answer = await ask(`\n  Log out now? ${BOLD}[Y/n]${RESET} `);
  if (answer !== null && ["", "y", "yes"].includes(answer.toLowerCase())) {
    ok("Logging out…");
    // loginwindow's own log-out event: no confirmation dialog, but apps can still ask to save.
    await run(["osascript", "-e", 'tell application "loginwindow" to «event aevtrlgo»']);
  } else {
    info("Not logging out. The changes apply at your next login.");
  }
}

if (wrong.length > 0) Deno.exit(1);
