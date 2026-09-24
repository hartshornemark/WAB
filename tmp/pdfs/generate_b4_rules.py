from pathlib import Path
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak

ROOT=Path(__file__).resolve().parents[2]
OUTPUT=ROOT/"output"/"pdf"/"B4_Configuration_Completion_Rules.pdf"
OUTPUT.parent.mkdir(parents=True,exist_ok=True)
NAVY=colors.HexColor("#10294F"); PALE=colors.HexColor("#EEF3FC"); LINE=colors.HexColor("#D4E0F2"); TEXT=colors.HexColor("#536989")
RED=colors.HexColor("#9B2C2C"); AMBER=colors.HexColor("#8A6411"); GREEN=colors.HexColor("#2F6E46"); GREY=colors.HexColor("#596579")
LIGHT_RED=colors.HexColor("#FCECEC"); LIGHT_AMBER=colors.HexColor("#FFF5D8"); LIGHT_GREEN=colors.HexColor("#E7F5EB")
styles=getSampleStyleSheet()
title=ParagraphStyle("Title",parent=styles["Title"],fontName="Helvetica-Bold",fontSize=21,leading=25,textColor=NAVY,alignment=TA_LEFT,spaceAfter=4)
subtitle=ParagraphStyle("Subtitle",parent=styles["Normal"],fontSize=9.5,leading=13,textColor=TEXT)
h2=ParagraphStyle("H2",parent=styles["Heading2"],fontName="Helvetica-Bold",fontSize=13,leading=16,textColor=NAVY,spaceBefore=3,spaceAfter=8)
body=ParagraphStyle("Body",parent=styles["BodyText"],fontSize=8.1,leading=10.8,textColor=NAVY)
small=ParagraphStyle("Small",parent=body,fontSize=7.2,leading=9.3)
white=ParagraphStyle("White",parent=body,fontName="Helvetica-Bold",textColor=colors.white)
status={"INCOMPLETE":ParagraphStyle("red",parent=small,fontName="Helvetica-Bold",textColor=RED),"PARTIALLY CONFIGURED":ParagraphStyle("amber",parent=small,fontName="Helvetica-Bold",textColor=AMBER),"CONFIGURED":ParagraphStyle("green",parent=small,fontName="Helvetica-Bold",textColor=GREEN),"SKIPPED":ParagraphStyle("grey",parent=small,fontName="Helvetica-Bold",textColor=GREY)}
def P(text,style=body): return Paragraph(text,style)
def page(canvas,doc):
 canvas.saveState();w,h=landscape(A4);canvas.setFillColor(NAVY);canvas.rect(0,h-17*mm,w,17*mm,fill=1,stroke=0);canvas.setFillColor(colors.white);canvas.setFont("Helvetica-Bold",8);canvas.drawString(16*mm,h-10.5*mm,"CARRIER CONFIGURATION  /  AHM565");canvas.setFillColor(TEXT);canvas.setFont("Helvetica",7.5);canvas.drawRightString(w-16*mm,9*mm,f"B4 completion rules  |  Page {doc.page}");canvas.restoreState()
doc=BaseDocTemplate(str(OUTPUT),pagesize=landscape(A4),leftMargin=16*mm,rightMargin=16*mm,topMargin=24*mm,bottomMargin=15*mm,title="B4 Configuration Completion Rules")
doc.addPageTemplates(PageTemplate(id="main",frames=Frame(doc.leftMargin,doc.bottomMargin,doc.width,doc.height,id="normal"),onPage=page))
story=[P("B4 Configuration Completion Rules",title),P("AHM565 Sheet B4 — Standard Baggage Weights and Planning",subtitle),Spacer(1,6*mm),P("Section status rules",h2)]
rows=[
 [P("SECTION",white),P("INCOMPLETE",white),P("PARTIALLY CONFIGURED",white),P("CONFIGURED / SKIPPED",white)],
 [P("Default Baggage Weights per Piece",body),P("Selected, but the B1 Weight Unit or default All Flights record is missing.",small),P("Selected and saved, but the method or a required Male, Female or Child piece weight is invalid.",small),P("CONFIGURED when selected with a valid Standard or Actual method, valid required whole-number values, and valid optional All-Passengers or seasonal values. SKIPPED when not selected.",small)],
 [P("Baggage Weights per Passenger and Variations",body),P("Selected, but the fixed All Flights / All Classes / All Passengers baseline is missing or its Weight per Passenger remains Unset.",small),P("A baseline or additional row has invalid or duplicate scope, an unavailable Class/Variation, or an active Standard method without a value.",small),P("CONFIGURED when selected and the fixed baseline plus every additional row has valid unique scope, methods and active values. SKIPPED while Default Weight per Piece is selected.",small)],
 [P("Baggage Planning Assumptions",body),P("No saved planning row exists. The screen presents a suggested default row for review and saving.",small),P("A saved row has invalid/duplicate scope or numeric values; or Volume is blank and B1 Checked Baggage Density is unavailable.",small),P("At least one saved row exists; every row has unique valid scope, valid Bags and Weight averages, and either Average Bag Volume or the B1 density fallback.",small)],
]
t=Table(rows,colWidths=[43*mm,61*mm,67*mm,84*mm],repeatRows=1)
t.setStyle(TableStyle([("BACKGROUND",(0,0),(-1,0),NAVY),("BACKGROUND",(0,1),(0,-1),PALE),("BACKGROUND",(1,1),(1,-1),LIGHT_RED),("BACKGROUND",(2,1),(2,-1),LIGHT_AMBER),("BACKGROUND",(3,1),(3,-1),LIGHT_GREEN),("GRID",(0,0),(-1,-1),.6,LINE),("VALIGN",(0,0),(-1,-1),"TOP"),("LEFTPADDING",(0,0),(-1,-1),7),("RIGHTPADDING",(0,0),(-1,-1),7),("TOPPADDING",(0,0),(-1,-1),7),("BOTTOMPADDING",(0,0),(-1,-1),7)]))
story += [t,Spacer(1,5*mm),P("Selection and default rules",h2)]
selection=[
 [P("RULE",white),P("BEHAVIOUR",white)],
 [P("Mutually exclusive weight methods",body),P("All Flights Weight per Piece is selected by default. While checked, the Per-Passenger/Variation checkbox is disabled and that section is SKIPPED. Unchecking the default activates and requires the Per-Passenger/Variation section.",small)],
 [P("Planning suggestion",body),P("When no Planning Assumptions are saved, the screen shows All Flights / All Classes with 1 Bag per Passenger, Weight equal to the Standard All-Passengers piece weight above, and blank Average Bag Volume. It remains INCOMPLETE until saved.",small)],
 [P("Density fallback",body),P("If Average Bag Volume is blank, the Bag Density provided in 1. STANDARD UNITS AND CODES is utilised. If both are blank, Planning Assumptions are PARTIALLY CONFIGURED.",small)],
]
st=Table(selection,colWidths=[62*mm,193*mm],repeatRows=1);st.setStyle(TableStyle([("BACKGROUND",(0,0),(-1,0),NAVY),("BACKGROUND",(0,1),(0,-1),PALE),("GRID",(0,0),(-1,-1),.6,LINE),("VALIGN",(0,0),(-1,-1),"TOP"),("LEFTPADDING",(0,0),(-1,-1),7),("RIGHTPADDING",(0,0),(-1,-1),7),("TOPPADDING",(0,0),(-1,-1),6),("BOTTOMPADDING",(0,0),(-1,-1),6)]))
story += [st,PageBreak(),P("B4 Page Status and Operational Rules",title),P("How the selected weight method and Planning Assumptions combine",subtitle),Spacer(1,6*mm),P("Page status",h2)]
page_rows=[
 [P("CONDITION",white),P("PAGE RESULT",white),P("REASON",white)],
 [P("B1 Weight Unit missing",small),P("INCOMPLETE",status["INCOMPLETE"]),P("The selected Baggage Weight method cannot be validated without its Weight Unit.",small)],
 [P("Selected weight method incomplete; Planning any state",small),P("INCOMPLETE",status["INCOMPLETE"]),P("The selected operational method is blocking.",small)],
 [P("Selected weight method configured; Planning incomplete or partial",small),P("PARTIALLY CONFIGURED",status["PARTIALLY CONFIGURED"]),P("The Baggage Weight basis is usable, but mandatory Planning Assumptions still need saving or correction.",small)],
 [P("Selected weight method and Planning configured",small),P("CONFIGURED",status["CONFIGURED"]),P("Every applicable B4 rule passes; the unselected weight method remains SKIPPED.",small)],
]
pt=Table(page_rows,colWidths=[98*mm,48*mm,109*mm],repeatRows=1);pt.setStyle(TableStyle([("BACKGROUND",(0,0),(-1,0),NAVY),("GRID",(0,0),(-1,-1),.6,LINE),("VALIGN",(0,0),(-1,-1),"TOP"),("LEFTPADDING",(0,0),(-1,-1),7),("RIGHTPADDING",(0,0),(-1,-1),7),("TOPPADDING",(0,0),(-1,-1),7),("BOTTOMPADDING",(0,0),(-1,-1),7)]))
story += [pt,Spacer(1,6*mm),P("Validation and data protection",h2)]
ops=[
 [P("RULE",white),P("IMPLEMENTED BEHAVIOUR",white)],
 [P("Existing carrier compatibility",body),P("If no B4 applicability record exists, All Flights Weight per Piece is treated as selected. Existing Baggage Weight and Planning records are preserved.",small)],
 [P("Applicability metadata",body),P("Only the method selection is stored in shared review/applicability metadata: APPLIES for Per-Passenger/Variation, NOT_APPLICABLE for the default Per-Piece method. Operational values remain in their existing B4 tables.",small)],
 [P("Fixed baseline",body),P("When Per-Passenger/Variation is active, the All Flights / All Classes / All Passengers identity cannot be renamed or removed. Its Weight per Piece inherits the default record.",small)],
 [P("Planning validation",body),P("Bags, Weight and optional Volume accept non-negative values with up to four decimal places. Class/Variation scope must be unique and reference saved B1/B3 values.",small)],
 [P("Concurrency",body),P("Operational records, selected method, B1 units, classes, variations and checked-baggage density participate in the revision. Stale saves are rejected.",small)],
 [P("Current ZZ example",body),P("Default Weight per Piece: CONFIGURED and selected. Per-Passenger/Variation: SKIPPED. Planning: INCOMPLETE, with suggested defaults of 1 bag, 15 KG and blank Volume. Page: PARTIALLY CONFIGURED until the planning row is saved.",small)],
]
ot=Table(ops,colWidths=[62*mm,193*mm],repeatRows=1);ot.setStyle(TableStyle([("BACKGROUND",(0,0),(-1,0),NAVY),("BACKGROUND",(0,1),(0,-1),PALE),("GRID",(0,0),(-1,-1),.6,LINE),("VALIGN",(0,0),(-1,-1),"TOP"),("LEFTPADDING",(0,0),(-1,-1),7),("RIGHTPADDING",(0,0),(-1,-1),7),("TOPPADDING",(0,0),(-1,-1),6),("BOTTOMPADDING",(0,0),(-1,-1),6)]))
story += [ot]
doc.build(story);print(OUTPUT)
