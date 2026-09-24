from pathlib import Path
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak

ROOT=Path(__file__).resolve().parents[2]
OUTPUT=ROOT/'output'/'pdf'/'D3_Configuration_Completion_Rules.pdf'
NAVY=colors.HexColor('#10294F');PALE=colors.HexColor('#EEF3FC');LINE=colors.HexColor('#D4E0F2');TEXT=colors.HexColor('#536989')
RED=colors.HexColor('#9B2C2C');AMBER=colors.HexColor('#8A6411');GREEN=colors.HexColor('#2F6E46');GREY=colors.HexColor('#596579')
LIGHT_RED=colors.HexColor('#FCECEC');LIGHT_AMBER=colors.HexColor('#FFF5D8');LIGHT_GREEN=colors.HexColor('#E7F5EB');LIGHT_GREY=colors.HexColor('#EDF0F5')
styles=getSampleStyleSheet()
title=ParagraphStyle('Title',parent=styles['Title'],fontName='Helvetica-Bold',fontSize=20,leading=23,textColor=NAVY,alignment=TA_LEFT,spaceAfter=3)
subtitle=ParagraphStyle('Subtitle',parent=styles['Normal'],fontSize=9,leading=11,textColor=TEXT)
h2=ParagraphStyle('H2',parent=styles['Heading2'],fontName='Helvetica-Bold',fontSize=12,leading=14,textColor=NAVY,spaceBefore=2,spaceAfter=6)
body=ParagraphStyle('Body',parent=styles['BodyText'],fontSize=7.4,leading=9.2,textColor=NAVY)
small=ParagraphStyle('Small',parent=body,fontSize=6.8,leading=8.4)
white=ParagraphStyle('White',parent=body,fontName='Helvetica-Bold',textColor=colors.white)
status={'INCOMPLETE':ParagraphStyle('red',parent=small,fontName='Helvetica-Bold',textColor=RED),'PARTIALLY CONFIGURED':ParagraphStyle('amber',parent=small,fontName='Helvetica-Bold',textColor=AMBER),'CONFIGURED':ParagraphStyle('green',parent=small,fontName='Helvetica-Bold',textColor=GREEN),'SKIPPED':ParagraphStyle('grey',parent=small,fontName='Helvetica-Bold',textColor=GREY)}
def P(value,style=body):return Paragraph(value,style)
def page(canvas,doc):
 canvas.saveState();w,h=landscape(A4);canvas.setFillColor(colors.white);canvas.rect(0,0,w,h,fill=1,stroke=0);canvas.setFillColor(NAVY);canvas.rect(0,h-17*mm,w,17*mm,fill=1,stroke=0);canvas.setFillColor(colors.white);canvas.setFont('Helvetica-Bold',8);canvas.drawString(16*mm,h-10.5*mm,'CARRIER CONFIGURATION  /  AHM565');canvas.setFillColor(TEXT);canvas.setFont('Helvetica',7.5);canvas.drawRightString(w-16*mm,9*mm,f'D3 completion rules  |  Page {doc.page}');canvas.restoreState()
def styled(table,vpad=4):
 table.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),NAVY),('GRID',(0,0),(-1,-1),.6,LINE),('VALIGN',(0,0),(-1,-1),'TOP'),('ALIGN',(0,0),(-1,-1),'LEFT'),('LEFTPADDING',(0,0),(-1,-1),6),('RIGHTPADDING',(0,0),(-1,-1),6),('TOPPADDING',(0,0),(-1,-1),vpad),('BOTTOMPADDING',(0,0),(-1,-1),vpad)]));return table

doc=BaseDocTemplate(str(OUTPUT),pagesize=landscape(A4),leftMargin=16*mm,rightMargin=16*mm,topMargin=23*mm,bottomMargin=14*mm,title='D3 Configuration Completion Rules')
doc.addPageTemplates(PageTemplate(id='main',frames=Frame(doc.leftMargin,doc.bottomMargin,doc.width,doc.height,id='normal'),onPage=page))
story=[P('D3 Configuration Completion Rules',title),P('AHM565 Sheet D3 - ULD Configurations and Positions',subtitle),Spacer(1,3*mm),P('Applicability and page status',h2)]
rules=[
 [P('CONDITION',white),P('STATUS',white),P('COMPLETION RULE',white)],
 [P('D2 contains no applicable ULD Holds.'),P('SKIPPED',status['SKIPPED']),P('D3 is neutral and excluded from assessed completion. No D3 data entry is available.',small)],
 [P('D2 contains at least one ULD Hold, but D3 has no saved configuration.'),P('INCOMPLETE',status['INCOMPLETE']),P('At least one configuration must be created for every applicable ULD Hold.',small)],
 [P('Some D2 ULD Holds have configurations, but one or more holds have none.'),P('PARTIALLY CONFIGURED',status['PARTIALLY CONFIGURED']),P('Every applicable ULD Hold must be represented.',small)],
 [P('Every D2 ULD Hold has a configuration, but a configuration is incomplete.'),P('PARTIALLY CONFIGURED',status['PARTIALLY CONFIGURED']),P('The declared physical-position count, saved physical rows or row validation is incomplete.',small)],
 [P('Every D2 ULD Hold has at least one complete configuration.'),P('CONFIGURED',status['CONFIGURED']),P('Every saved configuration contains exactly its declared number of valid PHYSICAL POSITION rows. Valid GROUP LIMIT rows are allowed but do not count as physical positions.',small)],
]
t=styled(Table(rules,colWidths=[82*mm,48*mm,125*mm],repeatRows=1),3.6)
t.setStyle(TableStyle([('BACKGROUND',(0,1),(-1,1),LIGHT_GREY),('BACKGROUND',(0,2),(-1,2),LIGHT_RED),('BACKGROUND',(0,3),(-1,4),LIGHT_AMBER),('BACKGROUND',(0,5),(-1,5),LIGHT_GREEN)]))
story += [t,Spacer(1,3*mm),P('Configuration controls',h2)]
controls=[
 [P('CONTROL',white),P('RULE',white)],
 [P('ULD Hold'),P('Only ULD Holds configured on D2 are available. Configurations are owned by one hold.',small)],
 [P('Configuration selector'),P('Each Configuration Code has an independent selector. Selecting it opens its table; selecting it again collapses it. Only one configuration is open or editable at a time.',small)],
 [P('Expected Physical Positions'),P('Required whole number from 1 to 999. Completion requires exactly this number of PHYSICAL POSITION rows.',small)],
 [P('DELETE CONFIGURATION'),P('Requires a warning and deletes the configuration together with all of its position and group-limit rows.',small)],
]
story += [styled(Table(controls,colWidths=[64*mm,191*mm],repeatRows=1),3.5),PageBreak(),P('Row validation',h2)]
validation=[
 [P('VALUE',white),P('REQUIREMENT',white)],
 [P('Row Type'),P('PHYSICAL POSITION or GROUP LIMIT. GROUP LIMIT rows do not count toward Expected Physical Positions.',small)],
 [P('Position ID'),P('Required; 1-3 uppercase letters or numbers. Unique within the aircraft, hold and Configuration Code.',small)],
 [P('Group ID'),P('Optional; up to 20 letters, numbers, hyphens or underscores.',small)],
 [P('Maximum Weight'),P('Required and greater than zero.',small)],
 [P('Volume'),P('Optional; when supplied it must be greater than zero.',small)],
 [P('Balance Arm'),P('Centroid is required. From and To are optional as a pair; when supplied they must satisfy From &lt;= Centroid &lt;= To.',small)],
 [P('Lateral Arm'),P('Optional. If used, From, Centroid and To must all be supplied and satisfy From &lt;= Centroid &lt;= To.',small)],
 [P('Index per Weight Unit'),P('Optional finite numeric value within the supported database range.',small)],
 [P('Colour checkbox'),P('Unchecked stores no colour. Checked requires a valid seven-character HEX value in #RRGGBB form.',small)],
]
story += [styled(Table(validation,colWidths=[68*mm,187*mm],repeatRows=1),3.6),Spacer(1,3*mm),P('Data relationships and protection',h2)]
protection=[
 [P('RELATIONSHIP',white),P('PROTECTION',white)],
 [P('Aircraft and Hold'),P('Every configuration and position is tied to Carrier IATA, Aircraft Type IATA, Series/Subtype and a valid D2 ULD Hold.',small)],
 [P('Configuration parent'),P('Each position references one configuration parent. Renaming a Configuration Code updates its rows; deleting a configuration deletes only its own rows.',small)],
 [P('D2 changes'),P('Deleting a D2 ULD Hold removes its dependent D3 configurations and rows after the D2 warning is accepted.',small)],
 [P('Concurrent editing'),P('A revision check rejects stale saves. Database keys and checks reject duplicates, orphaned rows and invalid numeric or identifier values.',small)],
]
story += [styled(Table(protection,colWidths=[68*mm,187*mm],repeatRows=1),3.7)]
doc.build(story)
print(OUTPUT)
