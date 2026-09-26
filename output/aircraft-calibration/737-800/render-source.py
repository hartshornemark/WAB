"""Render the supplied Boeing 737-800 DXF for source-view inspection."""
from pathlib import Path

import ezdxf
from ezdxf.addons.drawing import Frontend, RenderContext, layout
from ezdxf.addons.drawing.config import Configuration
from ezdxf.addons.drawing.svg import SVGBackend

SOURCE = Path("/Users/mahartshorne/Downloads/737-800.dxf")
OUTPUT = Path(__file__).with_name("737-800-source.svg")

document = ezdxf.readfile(SOURCE)
backend = SVGBackend()
Frontend(RenderContext(document), backend, Configuration()).draw_layout(document.modelspace())
OUTPUT.write_text(backend.get_string(layout.Page(0, 0)), encoding="utf-8")
print(OUTPUT)
