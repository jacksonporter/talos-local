#!/usr/bin/env python3
"""
Main application entry point.
"""

from talos.cli_group import main_cli


def main() -> None:
    """Main entry point for the talos-local CLI application."""
    main_cli()


def init() -> None:
    """Initialize module (runs main function when executed as script)."""
    if __name__ == "__main__":
        main()


init()
