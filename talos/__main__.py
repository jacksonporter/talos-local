#!/usr/bin/env python3
"""
Main entry point for the Talos CLI application.
"""

from talos.app import main


def init():
    """Initialize module (runs main function when executed as script)."""
    if __name__ == "__main__":
        main()


init()
