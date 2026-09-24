from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import PageBreak, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

OUT = Path("output/pdf/E5_Fleet_Aircraft_Weights_Completion_Rules.pdf")
OUT.parent.mkdir(parents=True, exist_ok=True)

NAVY = colors.HexColor("#132E57")
BLUE = colors.HexColor("#3568BF")
MUTED = colors.HexColor("#596E8F")
PALE = colors.HexColor("#F4F7FC")
LINE = colors.HexColor("#CCD9EE")
GREEN = colors.HexColor("#2F6E46")
GREEN_BG = colors.HexColor("#E7F5EB")
AMBER = colors.HexColor("#8A6411")
AMBER_BG = colors.HexColor("#FFF5D8")
RED = colors.HexColor("#9B2C2C")
RED_BG = colors.HexColor("#FCECEC")

styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name="TitleX", parent=styles["Title"], fontName="Helvetica-Bold", fontSize=21, leading=25, textColor=NAVY))
styles.add(ParagraphStyle(name="SubX", parent=styles["Normal"], fontSize=10, leading=14, textColor=MUTED))
styles.add(ParagraphStyle(name="HeadX", parent=styles["Heading2"], fontName="Helvetica-Bold", fontSize=14, leading=17, textColor=NAVY, spaceBefore=5, spaceAfter=6))
styles.add(ParagraphStyle(name="CellX", parent=styles["Normal"], fontSize=7.7, leading=9.5, textColor=NAVY))
styles.add(ParagraphStyle(name="CellBoldX", parent=styles["CellX"], fontName="Helvetica-Bold"))
styles.add(ParagraphStyle(name="SmallX", parent=styles["Normal"], fontSize=7.5, leading=9.4, textColor=MUTED))


def p(value, style="CellX"):
    return Paragraph(value, styles[style])


def matrix(rows, widths, aligns=None):
    table = Table(rows, colWidths=widths, repeatRows=1)
    rules = [
        ("BACKGROUND", (0, 0), (-1, 0), PALE),
        ("GRID", (0, 0), (-1, -1), 0.45, LINE),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 3.5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5),
    ]
    for col, align in (aligns or {}).items():
        rules.append(("ALIGN", (col, 0), (col, -1), align))
    table.setStyle(TableStyle(rules))
    return table


def page_header(canvas, doc):
    width, height = landscape(A4)
    canvas.saveState()
    canvas.setFillColor(NAVY)
    canvas.rect(0, height - 12 * mm, width, 12 * mm, fill=1, stroke=0)
    canvas.setFillColor(colors.white)
    canvas.setFont("Helvetica-Bold", 8)
    canvas.drawString(14 * mm, height - 7.5 * mm, "CARRIER CONFIGURATION  •  AHM565 E5")
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica", 8)
    canvas.drawRightString(width - 14 * mm, 8 * mm, f"E5 Fleet/Aircraft Weights  •  {doc.page}")
    canvas.restoreState()


doc = SimpleDocTemplate(
    str(OUT),
    pagesize=landscape(A4),
    leftMargin=12 * mm,
    rightMargin=12 * mm,
    topMargin=18 * mm,
    bottomMargin=14 * mm,
)

story = [
    p("E5 Fleet/Aircraft Weights — Completion and Data Rules", "TitleX"),
    p("One E5 approach is selected and saved: Fleet Weights or Individual Aircraft Weights.", "SubX"),
    Spacer(1, 4 * mm),
    p("1. Governing choices", "HeadX"),
    matrix(
        [
            [p("Choice", "CellBoldX"), p("Source", "CellBoldX"), p("Effect", "CellBoldX")],
            [p("Starting weight principle"), p("E1.1 Dry Operating Weight"), p("Controls the labels and destination columns: Dry Operating Weight / Index, or Basic Weight / Index.")],
            [p("E5 recording approach"), p("Selected on E5"), p("Exactly one section is shown and used: <b>Fleet Weights</b> or <b>Individual Aircraft Weights</b>.")],
            [p("Fleet baseline"), p("E1.2 Registrations"), p("Standard Fleet Weight and Standard Fleet Index are read as the baseline when Fleet Weights is selected.")],
        ],
        [58 * mm, 64 * mm, 134 * mm],
    ),
    Spacer(1, 3 * mm),
    p("2. Calculation and storage", "HeadX"),
    matrix(
        [
            [p("Approach", "CellBoldX"), p("Entered on E5", "CellBoldX"), p("Calculated / stored result", "CellBoldX")],
            [p("Fleet Weights"), p("Registration, Weight adjustment and Index adjustment."), p("Actual aircraft Weight = Fleet Weight + Weight adjustment.<br/>Actual aircraft Index = Fleet Index + Index adjustment.<br/>The actual values are stored in the E1.1-selected columns.")],
            [p("Individual Aircraft Weights"), p("Registration, actual Weight and actual Index."), p("The entered actual values are stored directly in the E1.1-selected columns.")],
            [p("Canonical registration row"), p("One reference row per registration."), p("E5 updates only the registration reference row. Crew / pantry combination rows remain intact.")],
        ],
        [58 * mm, 86 * mm, 112 * mm],
    ),
    Spacer(1, 3 * mm),
    p("3. Database mapping", "HeadX"),
    matrix(
        [
            [p("Data", "CellBoldX"), p("Table and columns", "CellBoldX")],
            [p("Approach"), p("Basic_Aircraft_Data.Weight_Recording_Approach")],
            [p("Fleet baseline"), p("Basic_Aircraft_Data.Standard_Fleet_Weight; Standard_Fleet_Index")],
            [p("Registration values"), p("Carrier_Aircraft_Fleet.Dry_Operating_Weight / Dry_Operating_Index, or Basic_Weight / Basic_Index")],
            [p("Fleet adjustments and optional details"), p("Carrier_Aircraft_Fleet.Fleet_Weight_Adjustment; Fleet_Index_Adjustment; MAC_Percent; Balance_Arm; Weight_Configuration_Code; Crew_Code_ID; Pantry_Code_ID; Remarks")],
        ],
        [64 * mm, 192 * mm],
    ),
    PageBreak(),
    p("E5 Completion Matrix", "TitleX"),
    p("Status is calculated from valid saved data. The selected approach determines which rule applies.", "SubX"),
    Spacer(1, 4 * mm),
    p("4. Completion status", "HeadX"),
    matrix(
        [
            [p("Status", "CellBoldX"), p("Rule", "CellBoldX")],
            [p("INCOMPLETE", "CellBoldX"), p("No E5 approach is selected; the selected section has no complete registration row; or Fleet Weights is selected while the E1.2 fleet baseline is missing.")],
            [p("PARTIALLY CONFIGURED", "CellBoldX"), p("Relevant saved data exists, but a required value or validation rule fails in one or more saved rows.")],
            [p("CONFIGURED", "CellBoldX"), p("An approach is selected and the active section has at least one complete, valid registration row. Fleet Weights also requires a complete fleet baseline.")],
        ],
        [58 * mm, 198 * mm],
    ),
    Spacer(1, 3 * mm),
    p("5. Field matrix", "HeadX"),
    matrix(
        [
            [p("Field", "CellBoldX"), p("Fleet Weights", "CellBoldX"), p("Individual Aircraft Weights", "CellBoldX"), p("Format / alignment", "CellBoldX")],
            [p("Registration"), p("Required"), p("Required"), p("Text; left")],
            [p("Weight"), p("Required signed adjustment"), p("Required positive actual value"), p("Whole number; right; no thousands separator")],
            [p("Index"), p("Required signed adjustment"), p("Required actual value"), p("One decimal; right")],
            [p("% MAC"), p("Optional"), p("Optional"), p("Numeric; right")],
            [p("Balance Arm"), p("Optional"), p("Optional"), p("Three decimals; right")],
            [p("Weight Configuration Code"), p("Optional"), p("Optional"), p("Saved E4 value")],
            [p("Pantry Code / Crew Code"), p("Optional"), p("Not used"), p("Saved E2 values")],
            [p("Remarks"), p("Optional"), p("Optional"), p("Text; left")],
        ],
        [48 * mm, 66 * mm, 72 * mm, 70 * mm],
    ),
    Spacer(1, 5 * mm),
    p("6. Screen and consistency rules", "HeadX"),
    matrix(
        [
            [p("Rule", "CellBoldX"), p("Required behaviour", "CellBoldX")],
            [p("One active section"), p("Changing the E5 approach switches the visible section. The inactive section does not contribute to status.")],
            [p("Compact layout"), p("Required values remain in a short primary row. Optional values are contained in an expandable details area. No horizontal scrolling is permitted.")],
            [p("E1.2 consistency"), p("Changing the fleet baseline recalculates each canonical actual value from its stored adjustment. Editing a registration reference recalculates its adjustment when Fleet Weights is active.")],
            [p("Preservation"), p("E1.2 and E5 update canonical reference rows without overwriting detailed crew / pantry combination rows.")],
            [p("Concurrency and authority"), p("Stale revisions are rejected. Read and edit permissions are enforced in the application and database functions.")],
        ],
        [62 * mm, 194 * mm],
    ),
]

doc.build(story, onFirstPage=page_header, onLaterPages=page_header)
print(OUT)
