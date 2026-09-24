from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak
from pathlib import Path

OUT=Path(__file__).resolve().parents[3]/"output/pdf/E2_Configuration_Completion_Rules.pdf"
OUT.parent.mkdir(parents=True,exist_ok=True)
navy=colors.HexColor("#17345f"); blue=colors.HexColor("#3267b8"); pale=colors.HexColor("#edf2fc"); line=colors.HexColor("#cbd8ec")
green=colors.HexColor("#25633b"); greenbg=colors.HexColor("#e7f5ec"); amber=colors.HexColor("#745514"); amberbg=colors.HexColor("#fff4dc"); red=colors.HexColor("#a12c2c"); redbg=colors.HexColor("#fdebec"); muted=colors.HexColor("#5d718f")
styles=getSampleStyleSheet()
styles.add(ParagraphStyle(name="Title2",parent=styles["Title"],fontName="Helvetica-Bold",fontSize=20,leading=24,textColor=navy,spaceAfter=5))
styles.add(ParagraphStyle(name="Sub",parent=styles["Normal"],fontSize=10,leading=14,textColor=muted,spaceAfter=10))
styles.add(ParagraphStyle(name="H2x",parent=styles["Heading2"],fontName="Helvetica-Bold",fontSize=13,leading=16,textColor=navy,spaceBefore=8,spaceAfter=7))
styles.add(ParagraphStyle(name="Bodyx",parent=styles["BodyText"],fontSize=9,leading=13,textColor=navy,spaceAfter=6))
styles.add(ParagraphStyle(name="Smallx",parent=styles["BodyText"],fontSize=8,leading=11,textColor=navy))
styles.add(ParagraphStyle(name="Centerx",parent=styles["Smallx"],alignment=TA_CENTER))
styles.add(ParagraphStyle(name="Headx",parent=styles["Smallx"],fontName="Helvetica-Bold",textColor=colors.white))

HEADERS={"Section","INCOMPLETE","PARTIALLY CONFIGURED","CONFIGURED","Field","Rule","Display","Status","Meaning"}
def p(text,style="Smallx"): return Paragraph(text,styles["Headx" if style=="Smallx" and text in HEADERS else style])
def footer(canvas,doc):
    canvas.saveState(); canvas.setStrokeColor(line); canvas.line(18*mm,14*mm,192*mm,14*mm)
    canvas.setFont("Helvetica",7.5); canvas.setFillColor(muted); canvas.drawString(18*mm,9*mm,"AHM565 E2 · Configuration Completion Rule Matrix")
    canvas.drawRightString(192*mm,9*mm,f"Page {doc.page}"); canvas.restoreState()
def table(data,widths,header=True):
    t=Table(data,colWidths=widths,repeatRows=1 if header else 0,hAlign="LEFT")
    cmd=[("VALIGN",(0,0),(-1,-1),"TOP"),("GRID",(0,0),(-1,-1),.45,line),("LEFTPADDING",(0,0),(-1,-1),6),("RIGHTPADDING",(0,0),(-1,-1),6),("TOPPADDING",(0,0),(-1,-1),6),("BOTTOMPADDING",(0,0),(-1,-1),6),("FONTNAME",(0,0),(-1,-1),"Helvetica")]
    if header: cmd += [("BACKGROUND",(0,0),(-1,0),navy),("TEXTCOLOR",(0,0),(-1,0),colors.white),("FONTNAME",(0,0),(-1,0),"Helvetica-Bold"),("ROWBACKGROUNDS",(0,1),(-1,-1),[colors.white,pale])]
    t.setStyle(TableStyle(cmd)); return t

story=[p("E2. CREW & PANTRY CODES","Title2"),p("AHM565 Sheet E2 · Screen, validation and completion rules","Sub"),
 p("Purpose","H2x"),p("E2 records operational crew complements and pantry loading codes for one Carrier, Aircraft Type and Series/Sub-Type. The screen uses <b>Aircraft_Crew_Codes</b> and <b>Aircraft_Pantry_Codes</b>.","Bodyx"),
 p("Page completion","H2x")]
matrix=[
 [p("Section"),p("INCOMPLETE"),p("PARTIALLY CONFIGURED"),p("CONFIGURED")],
 [p("<b>Crew Codes</b>"),p("No saved row."),p("One or more rows exist, but a saved row fails a mandatory code, location, total or uniqueness rule."),p("At least one complete row exists and every saved row is valid.")],
 [p("<b>Pantry Codes</b>"),p("No saved row."),p("One or more rows exist, but a saved row fails a mandatory code, location, weight, arm, index or uniqueness rule."),p("At least one complete row exists and every saved row is valid.")],
 [p("<b>E2 page</b>"),p("Both sections are incomplete."),p("Every other mixture of section results."),p("Crew Codes and Pantry Codes are both configured.")]
]
completion=table(matrix,[28*mm,43*mm,61*mm,54*mm])
completion.setStyle(TableStyle([("BACKGROUND",(1,1),(1,-1),redbg),("BACKGROUND",(2,1),(2,-1),amberbg),("BACKGROUND",(3,1),(3,-1),greenbg)]))
story += [completion,Spacer(1,6*mm),p("Crew Codes — saved-row rules","H2x")]
crew=[
 [p("Field"),p("Rule")],
 [p("Crew Code"),p("Required and unique for each Flight Deck/Cabin Crew location combination. Stored table length restrictions remain authoritative.")],
 [p("Flight Deck Location"),p("Required. Must reference an E2-selectable location already defined on D5 for the same aircraft.")],
 [p("Flight Deck Total"),p("Required whole number of zero or more.")],
 [p("Cabin Crew Location"),p("Required. Must reference a location already defined on D5 for the same aircraft.")],
 [p("Cabin Crew Total"),p("Required whole number of zero or more.")],
 [p("Flight Deck Baggage Location"),p("<b>Optional.</b> Blank means no Flight Deck crew hold baggage. If supplied, it must reference an Aircraft Hold defined on D2 for the same aircraft.")],
 [p("Cabin Crew Baggage Location"),p("<b>Optional.</b> Blank means no Cabin Crew hold baggage. If supplied, it must reference an Aircraft Hold defined on D2 for the same aircraft.")]
]
story += [table(crew,[52*mm,134*mm]),PageBreak(),p("Pantry Codes — saved-row rules","H2x")]
pantry=[
 [p("Field"),p("Rule"),p("Display")],
 [p("Pantry Code"),p("Required and unique for the aircraft."),p("Text")],
 [p("Galley Locations"),p("Required non-blank description, maximum 64 stored characters."),p("Left aligned")],
 [p("Total Weight"),p("Required whole number of zero or more. Zero is valid for an empty pantry code."),p("Whole number; no thousands separator")],
 [p("Balance Arm"),p("Required finite number within the supported numeric range."),p("Three decimal places")],
 [p("Index"),p("Required finite number. Zero is valid."),p("One decimal place")]
]
story += [table(pantry,[40*mm,91*mm,55*mm]),Spacer(1,7*mm),p("Database integrity","H2x"),
 p("The two baggage-location columns are nullable composite foreign keys to <b>Aircraft_Holds</b> using Carrier IATA, Aircraft Type IATA, Hold Name ID and Aircraft Series/Sub-Type. A populated location cannot point to another aircraft or to a hold that has been deleted. Crew locations retain their existing D5 foreign-key relationships. Seat totals must be non-negative. Pantry weight, balance arm, index and non-blank galley-location checks are enforced in the database.","Bodyx"),
 p("Status presentation","H2x")]
rag=[[p("Status"),p("Meaning")],[p("<font color='#a12c2c'><b>INCOMPLETE</b></font>"),p("No relevant saved rows.")],[p("<font color='#745514'><b>PARTIALLY CONFIGURED</b></font>"),p("Some saved data exists but at least one active rule fails.")],[p("<font color='#25633b'><b>CONFIGURED</b></font>"),p("All applicable rules pass for both sections.")]]
t=table(rag,[50*mm,136*mm]);t.setStyle(TableStyle([("BACKGROUND",(0,1),(0,1),redbg),("BACKGROUND",(0,2),(0,2),amberbg),("BACKGROUND",(0,3),(0,3),greenbg)]));story += [t,Spacer(1,7*mm),p("Global presentation rules","H2x"),
 p("Use standard font colours and shaded table headers. Numeric columns align to their values. Index is shown to one decimal place. Balance Arm is shown to three decimal places. Whole-number weights use no digit grouping. The two-row Crew Codes heading groups Location, Total and Baggage Location beneath Flight Deck and repeats the same three columns beneath Cabin Crew.","Bodyx"),
 p("Revision note","H2x"),p("This rule set deliberately treats baggage locations as optional. When present, they are hold references rather than free text; this preserves the operational requirement that crew baggage must be loaded in a valid aircraft hold.","Bodyx")]
doc=SimpleDocTemplate(str(OUT),pagesize=A4,rightMargin=18*mm,leftMargin=18*mm,topMargin=18*mm,bottomMargin=20*mm,title="E2 Crew & Pantry Codes — Configuration Completion Rules",author="Carrier Configuration")
doc.build(story,onFirstPage=footer,onLaterPages=footer)
print(OUT)
