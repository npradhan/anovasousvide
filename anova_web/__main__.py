"""Command-line entry point: ``python -m anova_web``."""

from __future__ import annotations

import argparse
import asyncio
import logging
import os


def main() -> None:
    parser = argparse.ArgumentParser(description="Web UI for an Anova Precision Cooker (Bluetooth)")
    parser.add_argument("--host", default="0.0.0.0", help="interface to listen on (default: all, so the LAN can reach it)")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--address", help="Bluetooth address of the cooker (default: first device named 'Anova')")
    parser.add_argument("--mock", action="store_true", help="use a simulated cooker instead of real hardware")
    parser.add_argument("--scan", action="store_true", help="list nearby Anova cookers and exit")
    parser.add_argument("--verbose", "-v", action="store_true", help="log Bluetooth traffic")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    if not args.verbose:
        logging.getLogger("bleak").setLevel(logging.WARNING)

    if args.scan:
        from .cooker import scan

        devices = asyncio.run(scan())
        if not devices:
            print("No Anova cookers found. Is it plugged in and not connected to another device?")
        for d in devices:
            print(f"{d['address']}  {d['name']}")
        return

    if args.mock:
        os.environ["ANOVA_MOCK"] = "1"
    if args.address:
        os.environ["ANOVA_ADDRESS"] = args.address

    import uvicorn

    from .app import create_app

    uvicorn.run(create_app(), host=args.host, port=args.port)


if __name__ == "__main__":
    main()
