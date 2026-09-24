from pathlib import Path
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, KeepTogether

OUT=Path(__file__).resolve().parents[3]/"output/pdf/E3_Configuration_Completion_Rules.pdf"
OUT.parent.mkdir(parents=True,exist_ok=True)
NAVY=colors.HexColor("#192C4D"); BLUE=colors.HexColor("#356AC3"); MUTED=colors.HexColor("#5B6F91")
PALE=colors.HexColor("#EDF2FC"); GREEN=colors.HexColor("#25633B"); GREENBG=colors.HexColor("#E7F5EC")
AMBER=colors.HexColor("#8B6400"); AMBERBG=colors.HexColor("#FFF4D6"); RED=colors.HexColor("#A12C2C"); REDBG=colors.HexColor("#FDEBEC")
styles=getSampleStyleSheet()
styles.add(ParagraphStyle(name="Title2",parent=styles["Title"],fontName="Helvetica-Bold",fontSize=22,leading=25,textColor=NAVY,spaceAfter=5))
styles.add(ParagraphStyle(name="Sub",parent=styles["Normal"],fontName="Helvetica",fontSize=10,leading=14,textColor=MUTED,spaceAfter=10))
styles.add(ParagraphStyle(name="H2x",parent=styles["Heading2"],fontName="Helvetica-Bold",fontSize=14,leading=17,textColor=NAVY,spaceBefore=4,spaceAfter=8))
styles.add(ParagraphStyle(name="Bodyx",parent=styles["BodyText"],fontName="Helvetica",fontSize=9,leading=13,textColor=NAVY,spaceAfter=5))
styles.add(ParagraphStyle(name="Smallx",parent=styles["BodyText"],fontName="Helvetica",fontSize=8,leading=11,textColor=NAVY))
styles.add(ParagraphStyle(name="Cell",parent=styles["BodyText"],fontName="Helvetica",fontSize=7.5,leading=10,textColor=NAVY))
styles.add(ParagraphStyle(name="CellB",parent=styles["BodyText"],fontName="Helvetica-Bold",fontSize=7.5,leading=10,textColor=NAVY))
styles.add(ParagraphStyle(name="CellH",parent=styles["BodyText"],fontName="Helvetica-Bold",fontSize=7.5,leading=10,textColor=colors.white))

def P(s,style="Cell"): return Paragraph(s,styles[style])
def H(s): return P(s,"CellH")
def table(data,widths,header=1):
    t=Table(data,colWidths=widths,repeatRows=header,hAlign="LEFT")
    t.setStyle(TableStyle([
        ("BACKGROUND",(0,0),(-1,header-1),NAVY),("TEXTCOLOR",(0,0),(-1,header-1),colors.white),
        ("FONTNAME",(0,0),(-1,header-1),"Helvetica-Bold"),("VALIGN",(0,0),(-1,-1),"TOP"),
        ("GRID",(0,0),(-1,-1),.45,colors.HexColor("#C8D5E8")),("LEFTPADDING",(0,0),(-1,-1),6),
        ("RIGHTPADDING",(0,0),(-1,-1),6),("TOPPADDING",(0,0),(-1,-1),4),("BOTTOMPADDING",(0,0),(-1,-1),4),
        ("ROWBACKGROUNDS",(0,header),(-1,-1),[colors.white,PALE])
    ])); return t

def footer(canvas,doc):
    canvas.saveState(); canvas.setStrokeColor(colors.HexColor("#C8D5E8")); canvas.line(18*mm,12*mm,279*mm,12*mm)
    canvas.setFillColor(MUTED); canvas.setFont("Helvetica",7); canvas.drawString(18*mm,7.5*mm,"AHM565 E3 · Configuration completion matrix")
    canvas.drawRightString(279*mm,7.5*mm,f"Page {doc.page}"); canvas.restoreState()

doc=SimpleDocTemplate(str(OUT),pagesize=landscape(A4),rightMargin=18*mm,leftMargin=18*mm,topMargin=16*mm,bottomMargin=16*mm,title="E3 Configuration Completion Rules",author="Carrier Configuration")
story=[P("E3 · Service Weight Adjustments","Title2"),P("Configuration completion matrix · AHM565 Sheet E3","Sub")]
story += [P("Page completion rule","H2x"),P("The user must save the section applicability first. Each checked section must contain at least one complete row, and every saved row in that section must be valid. An unchecked section is <b>SKIPPED</b> and does not block the page. If both sections are unchecked after review, E3 is <b>CONFIGURED</b> because the aircraft has explicitly declared that neither section applies.","Bodyx")]
completion=table([
    [H("Applicability saved"),H("Potable Water"),H("Service Weight Adjustment Codes"),H("E3 page status")],
    [P("No"),P("Any"),P("Any"),P("<font color='#A12C2C'><b>INCOMPLETE</b></font>")],
    [P("Yes"),P("Unchecked / SKIPPED"),P("Unchecked / SKIPPED"),P("<font color='#25633B'><b>CONFIGURED</b></font>")],
    [P("Yes"),P("Checked and complete"),P("Unchecked / SKIPPED"),P("<font color='#25633B'><b>CONFIGURED</b></font>")],
    [P("Yes"),P("Unchecked / SKIPPED"),P("Checked and complete"),P("<font color='#25633B'><b>CONFIGURED</b></font>")],
    [P("Yes"),P("Checked and complete"),P("Checked and complete"),P("<font color='#25633B'><b>CONFIGURED</b></font>")],
    [P("Yes"),P("Checked but empty/invalid"),P("Any"),P("<font color='#8B6400'><b>INCOMPLETE or PARTIALLY CONFIGURED</b></font>")],
    [P("Yes"),P("Any"),P("Checked but empty/invalid"),P("<font color='#8B6400'><b>INCOMPLETE or PARTIALLY CONFIGURED</b></font>")],
], [31*mm,56*mm,70*mm,58*mm])
completion.setStyle(TableStyle([
    ("BACKGROUND",(3,1),(3,1),REDBG),("BACKGROUND",(3,2),(3,5),GREENBG),
    ("BACKGROUND",(3,6),(3,7),AMBERBG),("TEXTCOLOR",(3,1),(3,1),RED),
    ("TEXTCOLOR",(3,2),(3,5),GREEN),("TEXTCOLOR",(3,6),(3,7),AMBER)
]))
story += [completion,Spacer(1,7*mm),P("Section status rules","H2x")]
section_status=table([
    [H("Section state"),H("Status"),H("Meaning")],
    [P("Unchecked after applicability is saved"),P("<b>SKIPPED</b>"),P("The section is declared not applicable. Existing rows are retained and are not counted toward completion.")],
    [P("Checked, with no saved row"),P("<font color='#A12C2C'><b>INCOMPLETE</b></font>"),P("At least one complete row is required.")],
    [P("Checked, with rows but one or more incomplete/invalid"),P("<font color='#8B6400'><b>PARTIALLY CONFIGURED</b></font>"),P("Progress exists, but every saved row must meet the row rules.")],
    [P("Checked, with at least one row and every row valid"),P("<font color='#25633B'><b>CONFIGURED</b></font>"),P("The active section meets its completion rule.")],
], [70*mm,43*mm,102*mm])
section_status.setStyle(TableStyle([
    ("BACKGROUND",(1,1),(1,1),colors.HexColor("#EEF1F5")),
    ("BACKGROUND",(1,2),(1,2),REDBG),("BACKGROUND",(1,3),(1,3),AMBERBG),("BACKGROUND",(1,4),(1,4),GREENBG)
]))
story += [section_status]
story.append(PageBreak())
story += [P("Row validation and stored data","Title2"),P("The screen follows the global numeric, heading, alignment and edit-control standards.","Sub")]
story += [P("1. Potable Water","H2x"),table([
    [H("Field"),H("Rule"),H("Display / relationship")],
    [P("Potable Water Code"),P("Required; 1–3 uppercase letters or numbers. Code and tank combination must be unique."),P("Stored in Aircraft_Potable_Water_Code_Definitions and Aircraft_Potable_Water_Codes.")],
    [P("Tank Name"),P("Required; must select a potable-water tank already defined for this aircraft on D6."),P("Foreign-key relationship through PW_Tank_Short_Form to Aircraft_Potable_Water_Locations.")],
    [P("Weight (Kg)"),P("Required; whole number, zero or greater; no thousands separator."),P("Right aligned.")],
    [P("Index"),P("Calculated from Weight × the selected D6 tank's Index Per Weight Unit."),P("Read only and displayed to one decimal place.")],
    [P("Remarks"),P("Optional; maximum 500 characters."),P("Left aligned.")],
], [42*mm,86*mm,87*mm])]
story += [Spacer(1,6*mm),P("2. Service Weight Adjustment Codes","H2x"),table([
    [H("Field"),H("Rule"),H("Display")],
    [P("Adjustment Code"),P("Required; unique; 1–3 uppercase letters or numbers."),P("Left aligned.")],
    [P("Description"),P("Required; 1–64 characters."),P("Left aligned.")],
    [P("Weight (Kg)"),P("Required signed whole number; must not be zero; no thousands separator."),P("Right aligned.")],
    [P("Balance Arm"),P("Required numeric value."),P("Right aligned; three decimal places.")],
    [P("Index"),P("Required direct Index value; this is not Index Per Weight Unit."),P("Right aligned; one decimal place.")],
    [P("Remarks"),P("Optional; maximum 500 characters."),P("Left aligned.")],
], [42*mm,86*mm,87*mm])]
story += [Spacer(1,6*mm),P("Database implementation","H2x"),P("Section activation is stored per Carrier / Aircraft Type / Series-Subtype. Potable Water rows use the three existing potable-water tables and preserve the D6 tank relationship. Service adjustment rows use Aircraft_Service_Weight_Adjustment_Codes. Save operations are atomic, permission checked and protected against stale revisions.","Bodyx")]
doc.build(story,onFirstPage=footer,onLaterPages=footer)
print(OUT)
