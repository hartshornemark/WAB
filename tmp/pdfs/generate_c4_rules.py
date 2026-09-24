from pathlib import Path
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer, Table, TableStyle

ROOT=Path(__file__).resolve().parents[2];OUTPUT=ROOT/'output'/'pdf'/'C4_Configuration_Completion_Rules.pdf'
NAVY=colors.HexColor('#10294F');PALE=colors.HexColor('#EEF3FC');LINE=colors.HexColor('#D4E0F2');TEXT=colors.HexColor('#536989')
RED=colors.HexColor('#9B2C2C');AMBER=colors.HexColor('#8A6411');GREEN=colors.HexColor('#2F6E46')
LIGHT_RED=colors.HexColor('#FCECEC');LIGHT_AMBER=colors.HexColor('#FFF5D8');LIGHT_GREEN=colors.HexColor('#E7F5EB')
styles=getSampleStyleSheet();title=ParagraphStyle('Title',parent=styles['Title'],fontName='Helvetica-Bold',fontSize=21,leading=25,textColor=NAVY,alignment=TA_LEFT,spaceAfter=4);subtitle=ParagraphStyle('Subtitle',parent=styles['Normal'],fontSize=9.5,leading=13,textColor=TEXT);h2=ParagraphStyle('H2',parent=styles['Heading2'],fontName='Helvetica-Bold',fontSize=13,leading=16,textColor=NAVY,spaceBefore=3,spaceAfter=8);body=ParagraphStyle('Body',parent=styles['BodyText'],fontSize=8.1,leading=10.8,textColor=NAVY);small=ParagraphStyle('Small',parent=body,fontSize=7.2,leading=9.3);white=ParagraphStyle('White',parent=body,fontName='Helvetica-Bold',textColor=colors.white)
status={'INCOMPLETE':ParagraphStyle('red',parent=small,fontName='Helvetica-Bold',textColor=RED),'PARTIALLY CONFIGURED':ParagraphStyle('amber',parent=small,fontName='Helvetica-Bold',textColor=AMBER),'CONFIGURED':ParagraphStyle('green',parent=small,fontName='Helvetica-Bold',textColor=GREEN)}
def P(value,style=body):return Paragraph(value,style)
def page(canvas,doc):
 canvas.saveState();w,h=landscape(A4);canvas.setFillColor(NAVY);canvas.rect(0,h-17*mm,w,17*mm,fill=1,stroke=0);canvas.setFillColor(colors.white);canvas.setFont('Helvetica-Bold',8);canvas.drawString(16*mm,h-10.5*mm,'CARRIER CONFIGURATION  /  AHM565');canvas.setFillColor(TEXT);canvas.setFont('Helvetica',7.5);canvas.drawRightString(w-16*mm,9*mm,f'C4 completion rules  |  Page {doc.page}');canvas.restoreState()
def styled(table,first=True,vpad=4):
 rules=[('BACKGROUND',(0,0),(-1,0),NAVY),('GRID',(0,0),(-1,-1),.6,LINE),('VALIGN',(0,0),(-1,-1),'TOP'),('ALIGN',(0,0),(-1,-1),'LEFT'),('LEFTPADDING',(0,0),(-1,-1),7),('RIGHTPADDING',(0,0),(-1,-1),7),('TOPPADDING',(0,0),(-1,-1),vpad),('BOTTOMPADDING',(0,0),(-1,-1),vpad)]
 if first:rules.append(('BACKGROUND',(0,1),(0,-1),PALE))
 table.setStyle(TableStyle(rules));return table
doc=BaseDocTemplate(str(OUTPUT),pagesize=landscape(A4),leftMargin=16*mm,rightMargin=16*mm,topMargin=24*mm,bottomMargin=15*mm,title='C4 Configuration Completion Rules');doc.addPageTemplates(PageTemplate(id='main',frames=Frame(doc.leftMargin,doc.bottomMargin,doc.width,doc.height,id='normal'),onPage=page))
story=[P('C4 Configuration Completion Rules',title),P('AHM565 Sheet C4 - Basic Index and MAC Formula',subtitle),Spacer(1,3*mm),P('Section and page status rules',h2)]
rows=[
 [P('DATA CONDITION',white),P('STATUS',white),P('RULE',white)],
 [P('No data entered'),P('INCOMPLETE',status['INCOMPLETE']),P('No C4 record has been saved, or a legacy record contains no entered formula values.',small)],
 [P('Some data entered'),P('PARTIALLY CONFIGURED',status['PARTIALLY CONFIGURED']),P('At least one formula value is present, but the complete five-value formula does not pass validation.',small)],
 [P('All data entered'),P('CONFIGURED',status['CONFIGURED']),P('Reference Arm, K Constant, C Constant, Length of MAC/RC and LEMAC/LERC are all present and valid.',small)],
]
table=styled(Table(rows,colWidths=[70*mm,55*mm,130*mm],repeatRows=1),False)
table.setStyle(TableStyle([('BACKGROUND',(0,1),(-1,1),LIGHT_RED),('BACKGROUND',(0,2),(-1,2),LIGHT_AMBER),('BACKGROUND',(0,3),(-1,3),LIGHT_GREEN)]))
story += [table,Spacer(1,3*mm),P('Required values',h2)]
required=[
 [P('FIELD',white),P('VALID VALUE',white),P('REQUIRED',white)],
 [P('Reference Arm'),P('A finite number, expressed in the C1 Length unit.',small),P('Yes',small)],
 [P('K Constant'),P('A finite whole number.',small),P('Yes',small)],
 [P('C Constant'),P('A positive whole number.',small),P('Yes',small)],
 [P('Length of MAC/RC'),P('A positive finite number, expressed in the C1 Length unit.',small),P('Yes',small)],
 [P('LEMAC/LERC'),P('A finite number, expressed in the C1 Length unit.',small),P('Yes',small)],
]
story += [styled(Table(required,colWidths=[62*mm,158*mm,35*mm],repeatRows=1)),Spacer(1,3*mm),P('Controls and protection',h2)]
controls=[
 [P('CONTROL',white),P('IMPLEMENTED BEHAVIOUR',white)],
 [P('Condition badges'),P('The page header and editable formula section display the same saved-data status. The badge remains at the furthest-right position.',small)],
 [P('EDIT / SAVE'),P('EDIT opens direct numeric entry. A successful save validates all five values before the status becomes CONFIGURED.',small)],
 [P('C1 prerequisite'),P('Length values use the Length unit selected on C1.',small)],
 [P('Stale edit protection'),P('A save is rejected when the C4 record changed after the page was loaded.',small)],
 [P('Authorisation'),P('Authorised users may view C4. Only authorised administrators may save changes.',small)],
]
story += [styled(Table(controls,colWidths=[62*mm,193*mm],repeatRows=1),True,5)]
doc.build(story);print(OUTPUT)
