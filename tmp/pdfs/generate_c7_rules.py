from pathlib import Path
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer, Table, TableStyle

ROOT=Path(__file__).resolve().parents[2]
OUTPUT=ROOT/'output'/'pdf'/'C7_Configuration_Completion_Rules.pdf'
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
status={'INCOMPLETE':ParagraphStyle('red',parent=small,fontName='Helvetica-Bold',textColor=RED),'PARTIALLY CONFIGURED':ParagraphStyle('amber',parent=small,fontName='Helvetica-Bold',textColor=AMBER),'CONFIGURED':ParagraphStyle('green',parent=small,fontName='Helvetica-Bold',textColor=GREEN),'SKIPPED':ParagraphStyle('grey',parent=small,fontName='Helvetica-Bold',textColor=GREY),'UNSUPPORTED':ParagraphStyle('unsupported',parent=small,fontName='Helvetica-Bold',textColor=GREY)}
def P(value,style=body):return Paragraph(value,style)
def page(canvas,doc):
 canvas.saveState();w,h=landscape(A4);canvas.setFillColor(colors.white);canvas.rect(0,0,w,h,fill=1,stroke=0);canvas.setFillColor(NAVY);canvas.rect(0,h-17*mm,w,17*mm,fill=1,stroke=0);canvas.setFillColor(colors.white);canvas.setFont('Helvetica-Bold',8);canvas.drawString(16*mm,h-10.5*mm,'CARRIER CONFIGURATION  /  AHM565');canvas.setFillColor(TEXT);canvas.setFont('Helvetica',7.5);canvas.drawRightString(w-16*mm,9*mm,f'C7 completion rules  |  Page {doc.page}');canvas.restoreState()
def styled(table,first=True,vpad=4):
 rules=[('BACKGROUND',(0,0),(-1,0),NAVY),('GRID',(0,0),(-1,-1),.6,LINE),('VALIGN',(0,0),(-1,-1),'TOP'),('ALIGN',(0,0),(-1,-1),'LEFT'),('LEFTPADDING',(0,0),(-1,-1),6),('RIGHTPADDING',(0,0),(-1,-1),6),('TOPPADDING',(0,0),(-1,-1),vpad),('BOTTOMPADDING',(0,0),(-1,-1),vpad)]
 if first:rules.append(('BACKGROUND',(0,1),(0,-1),PALE))
 table.setStyle(TableStyle(rules));return table

doc=BaseDocTemplate(str(OUTPUT),pagesize=landscape(A4),leftMargin=16*mm,rightMargin=16*mm,topMargin=23*mm,bottomMargin=14*mm,title='C7 Configuration Completion Rules')
doc.addPageTemplates(PageTemplate(id='main',frames=Frame(doc.leftMargin,doc.bottomMargin,doc.width,doc.height,id='normal'),onPage=page))
story=[P('C7 Configuration Completion Rules',title),P('AHM565 Sheet C7 - Ideal Trim, Tipping Limits and Lateral Imbalance',subtitle),Spacer(1,3*mm),P('Section completion rules',h2)]
sections=[
 [P('SECTION',white),P('CONDITION',white),P('STATUS',white),P('RULE',white)],
 [P('Ideal Trim'),P('Unchecked'),P('SKIPPED',status['SKIPPED']),P('The section does not apply and is excluded from the page percentage.',small)],
 [P('Ideal Trim'),P('Checked, no rows'),P('INCOMPLETE',status['INCOMPLETE']),P('No Ideal Trim data point has been saved.',small)],
 [P('Ideal Trim'),P('Checked, one valid row'),P('PARTIALLY CONFIGURED',status['PARTIALLY CONFIGURED']),P('One point cannot define a line.',small)],
 [P('Ideal Trim'),P('Checked, two or more valid rows'),P('CONFIGURED',status['CONFIGURED']),P('At least two valid, distinct and ordered points define the Ideal Trim line.',small)],
 [P('Tipping Limits'),P('Unchecked'),P('SKIPPED',status['SKIPPED']),P('The section does not apply and is excluded from the page percentage.',small)],
 [P('Tipping Limits'),P('Checked, no rows'),P('INCOMPLETE',status['INCOMPLETE']),P('No Tipping Limit has been saved.',small)],
 [P('Tipping Limits'),P('Checked, one or more valid rows'),P('CONFIGURED',status['CONFIGURED']),P('At least one valid Tipping Limit has been saved.',small)],
 [P('Lateral Imbalance'),P('Functionality is not provided'),P('UNSUPPORTED',status['UNSUPPORTED']),P('The section is neutral and excluded from completion.',small)],
]
t=styled(Table(sections,colWidths=[43*mm,57*mm,48*mm,107*mm],repeatRows=1),False,3.2)
t.setStyle(TableStyle([('BACKGROUND',(0,1),(-1,1),LIGHT_GREY),('BACKGROUND',(0,2),(-1,2),LIGHT_RED),('BACKGROUND',(0,3),(-1,3),LIGHT_AMBER),('BACKGROUND',(0,4),(-1,4),LIGHT_GREEN),('BACKGROUND',(0,5),(-1,5),LIGHT_GREY),('BACKGROUND',(0,6),(-1,6),LIGHT_RED),('BACKGROUND',(0,7),(-1,7),LIGHT_GREEN),('BACKGROUND',(0,8),(-1,8),LIGHT_GREY)]))
story += [t,Spacer(1,3*mm),P('Page aggregation',h2)]
page_rules=[
 [P('APPLICABLE SECTION RESULT',white),P('C7 PAGE STATUS',white)],
 [P('Both supported sections unchecked'),P('SKIPPED - there are no applicable supported sections.',small)],
 [P('Every applicable supported section is configured'),P('CONFIGURED',status['CONFIGURED'])],
 [P('Every applicable supported section is incomplete'),P('INCOMPLETE',status['INCOMPLETE'])],
 [P('Any other combination, including one-row Ideal Trim'),P('PARTIALLY CONFIGURED',status['PARTIALLY CONFIGURED'])],
]
story += [styled(Table(page_rules,colWidths=[100*mm,155*mm],repeatRows=1)),Spacer(1,3*mm),P('Data validation retained',h2)]
validation=[
 [P('VALUE',white),P('REQUIREMENT',white)],
 [P('Weight'),P('Positive whole number, unique within the section, ordered from lowest to highest and no greater than MRW when MRW is available.',small)],
 [P('Index / % MAC-RC'),P('Each row requires at least one of Index or % MAC/RC. % MAC/RC, when supplied, must be between 0 and 100.',small)],
 [P('Saving applicability'),P('A checked section may be saved before its first row so the INCOMPLETE state can be retained and displayed.',small)],
]
story += [styled(Table(validation,colWidths=[68*mm,187*mm],repeatRows=1))]
doc.build(story)
print(OUTPUT)
