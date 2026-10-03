#!/usr/bin/env python3
"""Where each developer tool lives and which version it is, as one table."""
from __future__ import annotations

import os
import re
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

# @include lib/style.py

HOME = Path.home()


@dataclass
class Tool:
    group: str
    name: str
    version: list[str]
    note: str = ""


TOOLS = [
    Tool("Apple", "xcode", ["xcodebuild", "-version"], "active developer folder"),
    Tool("Apple", "clt", [], "Command Line Tools"),
    Tool("Apple", "clang", ["clang", "--version"]),
    Tool("Apple", "git", ["git", "--version"]),
    Tool("Apple", "swift", ["swift", "--version"]),
    Tool("Apple", "swiftc", ["swiftc", "--version"]),
    Tool("Apple", "perl", ["perl", "-e", "print $^V"]),
    Tool("Package managers", "brew", ["brew", "--version"]),
    Tool("Package managers", "uv", ["uv", "--version"]),
    Tool("Runtimes", "deno", ["deno", "--version"]),
    Tool("Runtimes", "bun", ["bun", "--version"]),
    Tool("Runtimes", "nvm", [], "a shell function"),
    Tool("Runtimes", "node", ["node", "--version"]),
    Tool("Runtimes", "npm", ["npm", "--version"]),
    Tool("Shell", "bash", ["bash", "--version"]),
    Tool("Shell", "zsh", ["zsh", "--version"]),
    Tool("Shell", "atuin", ["atuin", "--version"]),
    Tool("Agents", "claude", ["claude", "--version"]),
    Tool("Agents", "codex", ["codex", "--version"]),
    Tool("Agents", "opencode", ["opencode", "--version"]),
]

# Installers put these on PATH through the shell profile, which a pasted heredoc may not have loaded.
EXTRA_PATH = [HOME / ".deno/bin", HOME / ".bun/bin", HOME / ".atuin/bin", HOME / ".opencode/bin", HOME / ".local/bin", Path("/opt/homebrew/bin")]
os.environ["PATH"] = os.pathsep.join([os.environ.get("PATH", ""), *map(str, EXTRA_PATH)])


def run(args: list[str]) -> str:
    try:
        done = subprocess.run(args, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return (done.stdout or done.stderr).strip() if done.returncode == 0 else ""


def version_of(text: str) -> str:
    match = re.search(r"\d+(\.\d+)+", text)
    return match.group(0) if match else text.splitlines()[0] if text else ""


def nvm() -> tuple[str, str]:
    script = HOME / ".nvm/nvm.sh"
    if not script.exists():
        return "", ""
    return str(script), version_of(run(["bash", "-c", f'. "{script}" && nvm --version']))


def node_path() -> None:
    # nvm's node is only on PATH once nvm.sh has run; fall back to its default alias.
    if shutil.which("node"):
        return
    versions = sorted((HOME / ".nvm/versions/node").glob("v*/bin"), key=lambda p: [int(n) for n in re.findall(r"\d+", p.parent.name)])
    if versions:
        os.environ["PATH"] += os.pathsep + str(versions[-1])


def check(tool: Tool) -> tuple[Tool, str, str]:
    if tool.name == "nvm":
        return (tool, *nvm())
    if tool.name == "xcode":
        path = run(["xcode-select", "-p"])
        full = run(tool.version) if path.startswith("/Applications/") else ""
        return tool, path, version_of(full) if full else ("CLT only" if path else "")
    if tool.name == "clt":
        info = run(["/usr/sbin/pkgutil", "--pkg-info=com.apple.pkg.CLTools_Executables"])
        folder = "/Library/Developer/CommandLineTools"
        version = ".".join(version_of(info.split("version:", 1)[-1]).split(".")[:3]) if info else ""
        return tool, folder if Path(folder).exists() else "", version
    path = shutil.which(tool.name) or ""
    return tool, path, version_of(run(tool.version)) if path else ""


def short(path: str) -> str:
    return path.replace(str(HOME), "~", 1)


node_path()
with console.status("Checking tools…"):
    with ThreadPoolExecutor() as pool:
        results = list(pool.map(check, TOOLS))

table = make_table(title="Developer tools", title_justify="left")
table.add_column("Group", style="dim")
table.add_column("Tool", style="bold")
table.add_column("Version", style="green")
table.add_column("Path", overflow="fold")

missing = []
last_group = ""
for tool, path, version in results:
    group = tool.group if tool.group != last_group else ""
    last_group = tool.group
    name = f"{tool.name}\n[dim]{tool.note}[/]" if tool.note else tool.name
    if path:
        table.add_row(group, name, version or "[yellow]?[/]", short(path))
    else:
        missing.append(tool.name)
        table.add_row(group, name, "", "[red]not found[/]")

console.print(table)
if missing:
    console.print()
    todo(f"Not found: {', '.join(missing)}")
else:
    console.print()
    ok(f"All {len(TOOLS)} tools found")
