# Shared output style for reset1's Python scripts, run with `uv run --with rich`.
# A script pulls it in with an @include line naming lib/style.py, after its own imports; ArfanReset1 pastes
# this file in its place, so a copied script still runs on its own. Same words as lib/style.sh.
from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

console = Console()
BORDER = {"info": "blue", "warn": "yellow", "fail": "red"}


def heading(title: str) -> None:
    """A section title drawn as a rule across the terminal."""
    console.rule(f"[bold]{title}")


def ok(text: str) -> None:
    """Done, or already right."""
    console.print(f"[green]✓[/] {text}")


def todo(text: str) -> None:
    """About to change, or still to do."""
    console.print(f"[yellow]•[/] {text}")


def fail(text: str) -> None:
    """Did not work."""
    console.print(f"[red]✕[/] {text}")


def info(text: str) -> None:
    """A quiet detail."""
    console.print(f"[dim]{text}[/]")


def suggest(text: str) -> None:
    """A command to try next."""
    console.print(f"\n  [blue]{text}[/]")


def make_table(*columns: str, **options) -> Table:
    """A table with the shared header style; keyword options pass through to Rich."""
    return Table(*columns, **{"header_style": "bold", "pad_edge": False, **options})


def panel(text: str, title: str, kind: str = "info") -> None:
    """A boxed message; kind is info, warn or fail. Text is shown as written, never as markup."""
    console.print(Panel(Text(text), title=title, border_style=BORDER[kind]))
