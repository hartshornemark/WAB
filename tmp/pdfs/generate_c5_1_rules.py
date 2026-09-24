from pathlib import Path
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer, Table, TableStyle

ROOT=Path(__file__).resolve().parents[2]
OUTPUT=ROOT/'output'/'pdf'/'C5_1_Configuration_Completion_Rules.pdf'
NAVY=colors.HexColor('#10294F');PALE=colors.HexColor('#EEF3FC');LINE=colors.HexColor('#D4E0F2');TEXT=colors.HexColor('#536989')
RED=colors.HexColor('#9B2C2C');AMBER=colors.HexColor('#8A6411');GREEN=colors.HexColor('#2F6E46')
LIGHT_RED=colors.HexColor('#FCECEC');LIGHT_AMBER=colors.HexColor('#FFF5D8');LIGHT_GREEN=colors.HexColor('#E7F5EB')
styles=getSampleStyleSheet()
title=ParagraphStyle('Title',parent=styles['Title'],fontName='Helvetica-Bold',fontSize=20,leading=23,textColor=NAVY,alignment=TA_LEFT,spaceAfter=3)
subtitle=ParagraphStyle('Subtitle',parent=styles['Normal'],fontSize=9,leading=11,textColor=TEXT)
h2=ParagraphStyle('H2',parent=styles['Heading2'],fontName='Helvetica-Bold',fontSize=12,leading=14,textColor=NAVY,spaceBefore=2,spaceAfter=6)
body=ParagraphStyle('Body',parent=styles['BodyText'],fontSize=7.4,leading=9.2,textColor=NAVY)
small=ParagraphStyle('Small',parent=body,fontSize=6.8,leading=8.4)
white=ParagraphStyle('White',parent=body,fontName='Helvetica-Bold',textColor=colors.white)
status={'INCOMPLETE':ParagraphStyle('red',parent=small,fontName='Helvetica-Bold',textColor=RED),'PARTIALLY CONFIGURED':ParagraphStyle('amber',parent=small,fontName='Helvetica-Bold',textColor=AMBER),'CONFIGURED':ParagraphStyle('green',parent=small,fontName='Helvetica-Bold',textColor=GREEN)}
def P(value,style=body):return Paragraph(value,style)
def page(canvas,doc):
 canvas.saveState();w,h=landscape(A4);canvas.setFillColor(colors.white);canvas.rect(0,0,w,h,fill=1,stroke=0);canvas.setFillColor(NAVY);canvas.rect(0,h-17*mm,w,17*mm,fill=1,stroke=0);canvas.setFillColor(colors.white);canvas.setFont('Helvetica-Bold',8);canvas.drawString(16*mm,h-10.5*mm,'CARRIER CONFIGURATION  /  AHM565');canvas.setFillColor(TEXT);canvas.setFont('Helvetica',7.5);canvas.drawRightString(w-16*mm,9*mm,f'C5.1 completion rules  |  Page {doc.page}');canvas.restoreState()
def styled(table,first=True,vpad=3.2):
 rules=[('BACKGROUND',(0,0),(-1,0),NAVY),('GRID',(0,0),(-1,-1),.6,LINE),('VALIGN',(0,0),(-1,-1),'TOP'),('ALIGN',(0,0),(-1,-1),'LEFT'),('LEFTPADDING',(0,0),(-1,-1),6),('RIGHTPADDING',(0,0),(-1,-1),6),('TOPPADDING',(0,0),(-1,-1),vpad),('BOTTOMPADDING',(0,0),(-1,-1),vpad)]
 if first:rules.append(('BACKGROUND',(0,1),(0,-1),PALE))
 table.setStyle(TableStyle(rules));return table

doc=BaseDocTemplate(str(OUTPUT),pagesize=landscape(A4),leftMargin=16*mm,rightMargin=16*mm,topMargin=23*mm,bottomMargin=14*mm,title='C5.1 Configuration Completion Rules')
doc.addPageTemplates(PageTemplate(id='main',frames=Frame(doc.leftMargin,doc.bottomMargin,doc.width,doc.height,id='normal'),onPage=page))
story=[P('C5.1 Configuration Completion Rules',title),P('AHM565 Sheet C5.1 - Balance Envelope',subtitle),Spacer(1,2.5*mm),P('Page status rules',h2)]
rules=[
 [P('DATA CONDITION',white),P('STATUS',white),P('RULE',white)],
 [P('No meaningful C5.1 data'),P('INCOMPLETE',status['INCOMPLETE']),P('Curtailment status, structural maximum weights and all six envelope limits remain unconfigured.',small)],
 [P('Some data entered or any rule fails'),P('PARTIALLY CONFIGURED',status['PARTIALLY CONFIGURED']),P('At least one value exists, but a required maximum, hierarchy, envelope, first-row, final-row, Weight or Index rule is incomplete or invalid.',small)],
 [P('Every required rule passes'),P('CONFIGURED',status['CONFIGURED']),P('Curtailment status is selected; MZFW, MLW/MLAW, MTOW and MRW are valid; and all six envelope limits satisfy every completion rule.',small)],
]
t=styled(Table(rules,colWidths=[67*mm,54*mm,134*mm],repeatRows=1),False)
t.setStyle(TableStyle([('BACKGROUND',(0,1),(-1,1),LIGHT_RED),('BACKGROUND',(0,2),(-1,2),LIGHT_AMBER),('BACKGROUND',(0,3),(-1,3),LIGHT_GREEN)]))
story += [t,Spacer(1,3*mm),P('Required maximum weights and hierarchy',h2)]
weights=[
 [P('REQUIREMENT',white),P('COMPLETION RULE',white)],
 [P('Structural maximums'),P('MZFW, MLW/MLAW, MTOW and MRW are all mandatory positive whole-number weights.',small)],
 [P('Weight hierarchy'),P('MZFW <= MLW/MLAW <= MTOW <= MRW.',small)],
 [P('MRW'),P('MRW has no separate envelope. It remains mandatory and must be equal to or greater than MTOW.',small)],
]
story += [styled(Table(weights,colWidths=[67*mm,188*mm],repeatRows=1)),Spacer(1,3*mm),P('Six required envelope limits',h2)]
envelopes=[
 [P('ENVELOPE',white),P('REQUIRED LIMITS',white),P('FINAL ROW',white)],
 [P('Zero Fuel Weight'),P('FWD and AFT',small),P('Both final rows equal MZFW.',small)],
 [P('Take-Off Weight'),P('FWD and AFT',small),P('Both final rows equal MTOW.',small)],
 [P('Landing Weight'),P('FWD and AFT',small),P('Both final rows equal MLW/MLAW.',small)],
]
story += [styled(Table(envelopes,colWidths=[67*mm,63*mm,125*mm],repeatRows=1)),Spacer(1,3*mm),P('Envelope row and boundary rules',h2)]
rows=[
 [P('RULE',white),P('REQUIREMENT',white)],
 [P('First-row lower bound'),P('For every FWD and AFT limit, the first Weight is less than or equal to the smallest applicable fleet DOW. If no fleet DOW exists, Standard Fleet Weight is used.',small)],
 [P('Weight'),P('Mandatory, positive whole number, unique within its limit, in ascending order and no greater than the applicable structural maximum.',small)],
 [P('Index Value'),P('Mandatory finite numeric value for every envelope row.',small)],
 [P('% MAC'),P('Optional and nullable. When supplied, it must be a finite value between 0 and 100.',small)],
 [P('C5.2'),P('Pictorial only; excluded from configuration completion.',small)],
]
story += [styled(Table(rows,colWidths=[67*mm,188*mm],repeatRows=1))]
doc.build(story)
print(OUTPUT)
