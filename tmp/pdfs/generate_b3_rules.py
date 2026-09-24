from pathlib import Path
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "output" / "pdf" / "B3_Configuration_Completion_Rules.pdf"
OUTPUT.parent.mkdir(parents=True, exist_ok=True)

NAVY = colors.HexColor("#10294F")
BLUE = colors.HexColor("#376BC4")
PALE = colors.HexColor("#EEF3FC")
LINE = colors.HexColor("#D4E0F2")
TEXT = colors.HexColor("#536989")
RED = colors.HexColor("#9B2C2C")
AMBER = colors.HexColor("#8A6411")
GREEN = colors.HexColor("#2F6E46")
LIGHT_RED = colors.HexColor("#FCECEC")
LIGHT_AMBER = colors.HexColor("#FFF5D8")
LIGHT_GREEN = colors.HexColor("#E7F5EB")

styles = getSampleStyleSheet()
title = ParagraphStyle("Title", parent=styles["Title"], fontName="Helvetica-Bold", fontSize=21, leading=25, textColor=NAVY, alignment=TA_LEFT, spaceAfter=4)
subtitle = ParagraphStyle("Subtitle", parent=styles["Normal"], fontName="Helvetica", fontSize=9.5, leading=13, textColor=TEXT)
h2 = ParagraphStyle("H2", parent=styles["Heading2"], fontName="Helvetica-Bold", fontSize=13, leading=16, textColor=NAVY, spaceBefore=3, spaceAfter=8)
body = ParagraphStyle("Body", parent=styles["BodyText"], fontName="Helvetica", fontSize=8.2, leading=11, textColor=NAVY)
small = ParagraphStyle("Small", parent=body, fontSize=7.3, leading=9.5)
white = ParagraphStyle("White", parent=body, fontName="Helvetica-Bold", textColor=colors.white)
status_styles = {
    "INCOMPLETE": ParagraphStyle("Red", parent=small, fontName="Helvetica-Bold", textColor=RED),
    "PARTIALLY CONFIGURED": ParagraphStyle("Amber", parent=small, fontName="Helvetica-Bold", textColor=AMBER),
    "CONFIGURED": ParagraphStyle("Green", parent=small, fontName="Helvetica-Bold", textColor=GREEN),
    "SKIPPED": ParagraphStyle("Grey", parent=small, fontName="Helvetica-Bold", textColor=colors.HexColor("#596579")),
}

def P(text, style=body):
    return Paragraph(text, style)

def page(canvas, doc):
    canvas.saveState()
    width, height = landscape(A4)
    canvas.setFillColor(NAVY)
    canvas.rect(0, height - 17 * mm, width, 17 * mm, fill=1, stroke=0)
    canvas.setFillColor(colors.white)
    canvas.setFont("Helvetica-Bold", 8)
    canvas.drawString(16 * mm, height - 10.5 * mm, "CARRIER CONFIGURATION  /  AHM565")
    canvas.setFillColor(TEXT)
    canvas.setFont("Helvetica", 7.5)
    canvas.drawRightString(width - 16 * mm, 9 * mm, f"B3 completion rules  |  Page {doc.page}")
    canvas.restoreState()

doc = BaseDocTemplate(str(OUTPUT), pagesize=landscape(A4), leftMargin=16*mm, rightMargin=16*mm, topMargin=24*mm, bottomMargin=15*mm, title="B3 Configuration Completion Rules")
frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="normal")
doc.addPageTemplates(PageTemplate(id="main", frames=frame, onPage=page))

story = [
    P("B3 Configuration Completion Rules", title),
    P("AHM565 Sheet B3 — Passenger and Hand Baggage Weights", subtitle),
    Spacer(1, 6*mm),
    P("Section status rules", h2),
]

rows = [
    [P("SECTION", white), P("INCOMPLETE", white), P("PARTIALLY CONFIGURED", white), P("CONFIGURED", white)],
    [P("Standard / Default Passenger Weights", body),
     P("B1 Weight Unit is missing, or the All Flights Standard/Default record has not been saved.", small),
     P("A record exists, but a required passenger weight or conditional Hand Baggage weight is invalid.", small),
     P("Male, Female and Child are positive whole numbers; Infant is a whole number of zero or more; Adult is optional; Hand Baggage is included or has a valid separate whole-number weight.", small)],
    [P("Carrier Flight Variations", body),
     P("No variation is saved and the empty section has not been deliberately reviewed and saved.", small),
     P("One or more rows has an invalid or duplicate Code or Description.", small),
     P("The section was reviewed and saved empty, or every row has a unique three-character alphanumeric Code and a unique Description of 1–64 characters.", small)],
    [P("Passenger / Hand Baggage Weights by Class", body),
     P("Standard/Default Passenger Weights exclude Hand Baggage and no class-specific weight set has been saved.", small),
     P("A row has an unavailable Class or Variation, invalid weights, or duplicates another Class/Variation pair.", small),
     P("When active, every row uses a saved B1 Class and Standard/Default or an adopted Flight Variation, with valid Passenger and separate Hand Baggage weights. When Standard/Default includes Hand Baggage, this section is disabled and shown as SKIPPED.", small)],
]
table = Table(rows, colWidths=[42*mm, 61*mm, 61*mm, 91*mm], repeatRows=1)
table.setStyle(TableStyle([
    ("BACKGROUND", (0,0), (-1,0), NAVY), ("VALIGN", (0,0), (-1,-1), "TOP"),
    ("GRID", (0,0), (-1,-1), 0.6, LINE), ("BACKGROUND", (0,1), (0,-1), PALE),
    ("BACKGROUND", (1,1), (1,-1), LIGHT_RED), ("BACKGROUND", (2,1), (2,-1), LIGHT_AMBER), ("BACKGROUND", (3,1), (3,-1), LIGHT_GREEN),
    ("LEFTPADDING", (0,0), (-1,-1), 7), ("RIGHTPADDING", (0,0), (-1,-1), 7),
    ("TOPPADDING", (0,0), (-1,-1), 7), ("BOTTOMPADDING", (0,0), (-1,-1), 7),
]))
story += [table, Spacer(1, 6*mm), P("Key interpretation", h2)]
key_rows = [
    [P("INCOMPLETE", status_styles["INCOMPLETE"]), P("The section is missing a blocking prerequisite, required record, or deliberate review.", body)],
    [P("PARTIALLY CONFIGURED", status_styles["PARTIALLY CONFIGURED"]), P("Configuration exists, but one or more saved values or relationships does not meet the rule.", body)],
    [P("CONFIGURED", status_styles["CONFIGURED"]), P("The section meets every applicable rule. Flight Variations may be deliberately reviewed and saved empty.", body)],
    [P("SKIPPED", status_styles["SKIPPED"]), P("The section is disabled because Standard/Default Passenger Weights already include Hand Baggage. It does not reduce the page status.", body)],
]
key = Table(key_rows, colWidths=[53*mm, 202*mm])
key.setStyle(TableStyle([("GRID",(0,0),(-1,-1),0.5,LINE),("VALIGN",(0,0),(-1,-1),"MIDDLE"),("LEFTPADDING",(0,0),(-1,-1),7),("RIGHTPADDING",(0,0),(-1,-1),7),("TOPPADDING",(0,0),(-1,-1),6),("BOTTOMPADDING",(0,0),(-1,-1),6)]))
story += [key, PageBreak(), P("B3 Page Status and Operational Rules", title), P("How section results combine and how review is recorded", subtitle), Spacer(1,6*mm), P("Page status", h2)]

page_rows = [
    [P("CONDITION", white), P("PAGE RESULT", white), P("REASON", white)],
    [P("B1 Weight Unit missing or Standard/Default record absent", small), P("INCOMPLETE", status_styles["INCOMPLETE"]), P("Standard Passenger Weights are mandatory and block B3 completion.", small)],
    [P("Standard section exists but contains an invalid value", small), P("PARTIALLY CONFIGURED", status_styles["PARTIALLY CONFIGURED"]), P("A saved mandatory record exists, but it still needs correction.", small)],
    [P("Standard configured; any applicable section incomplete or partial", small), P("PARTIALLY CONFIGURED", status_styles["PARTIALLY CONFIGURED"]), P("The mandatory basis is usable, but B3 has outstanding review or correction work.", small)],
    [P("All applicable sections configured", small), P("CONFIGURED", status_styles["CONFIGURED"]), P("Every applicable rule passes. Class-Specific Weights are excluded from the page calculation while Hand Baggage is included in Standard/Default Passenger Weights.", small)],
]
page_table = Table(page_rows, colWidths=[98*mm, 48*mm, 109*mm], repeatRows=1)
page_table.setStyle(TableStyle([("BACKGROUND",(0,0),(-1,0),NAVY),("GRID",(0,0),(-1,-1),0.6,LINE),("VALIGN",(0,0),(-1,-1),"TOP"),("LEFTPADDING",(0,0),(-1,-1),7),("RIGHTPADDING",(0,0),(-1,-1),7),("TOPPADDING",(0,0),(-1,-1),7),("BOTTOMPADDING",(0,0),(-1,-1),7),("BACKGROUND",(0,1),(-1,-1),colors.white)]))
story += [page_table, Spacer(1,6*mm), P("Review, validation and data protection", h2)]

ops_rows = [
    [P("RULE", white), P("IMPLEMENTED BEHAVIOUR", white)],
    [P("Flight Variations", body), P("Saving an empty Carrier Flight Variations section records a deliberate review. An untouched empty section remains INCOMPLETE.", small)],
    [P("Class-Specific applicability", body), P("When Standard/Default Passenger Weights include Hand Baggage, the Class-Specific section is disabled and shown as SKIPPED. When Hand Baggage is separate, the section becomes active and requires at least one valid weight set.", small)],
    [P("Populated optional sections", body), P("Valid saved rows count as CONFIGURED. A successful save also records review metadata for future empty-state decisions.", small)],
    [P("Dependencies", body), P("Class-specific rows must use a Class saved on B1 and either Standard/Default or a Flight Variation saved on B3.", small)],
    [P("Concurrency", body), P("Review metadata participates in the B3 revision. A stale save is rejected if passenger settings, classes, the B1 weight unit, or B3 review state changed.", small)],
    [P("Data preservation", body), P("The completion migration does not modify existing Standard/Default weights, Flight Variations, or class-specific weight sets. It adds review-state reporting to the existing read/save workflow.", small)],
    [P("Current ZZ example", body), P("Standard/Default: CONFIGURED and includes Hand Baggage; Carrier Flight Variations: CONFIGURED (CTR — Charter); Class-Specific Weights: SKIPPED and disabled. Page: CONFIGURED.", small)],
]
ops = Table(ops_rows, colWidths=[60*mm,195*mm], repeatRows=1)
ops.setStyle(TableStyle([("BACKGROUND",(0,0),(-1,0),NAVY),("BACKGROUND",(0,1),(0,-1),PALE),("GRID",(0,0),(-1,-1),0.6,LINE),("VALIGN",(0,0),(-1,-1),"TOP"),("LEFTPADDING",(0,0),(-1,-1),7),("RIGHTPADDING",(0,0),(-1,-1),7),("TOPPADDING",(0,0),(-1,-1),6),("BOTTOMPADDING",(0,0),(-1,-1),6)]))
story += [ops]

doc.build(story)
print(OUTPUT)
