from pathlib import Path
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak

ROOT=Path(__file__).resolve().parents[2]
OUTPUT=ROOT/'output'/'pdf'/'C2_Configuration_Completion_Rules.pdf'
NAVY=colors.HexColor('#10294F');PALE=colors.HexColor('#EEF3FC');LINE=colors.HexColor('#D4E0F2');TEXT=colors.HexColor('#536989')
RED=colors.HexColor('#9B2C2C');AMBER=colors.HexColor('#8A6411');GREEN=colors.HexColor('#2F6E46');GREY=colors.HexColor('#596579')
LIGHT_RED=colors.HexColor('#FCECEC');LIGHT_AMBER=colors.HexColor('#FFF5D8');LIGHT_GREEN=colors.HexColor('#E7F5EB');LIGHT_GREY=colors.HexColor('#EDF0F5')
styles=getSampleStyleSheet()
title=ParagraphStyle('Title',parent=styles['Title'],fontName='Helvetica-Bold',fontSize=21,leading=25,textColor=NAVY,alignment=TA_LEFT,spaceAfter=4)
subtitle=ParagraphStyle('Subtitle',parent=styles['Normal'],fontSize=9.5,leading=13,textColor=TEXT)
h2=ParagraphStyle('H2',parent=styles['Heading2'],fontName='Helvetica-Bold',fontSize=13,leading=16,textColor=NAVY,spaceBefore=3,spaceAfter=8)
body=ParagraphStyle('Body',parent=styles['BodyText'],fontSize=8.1,leading=10.8,textColor=NAVY)
small=ParagraphStyle('Small',parent=body,fontSize=7.2,leading=9.3)
white=ParagraphStyle('White',parent=body,fontName='Helvetica-Bold',textColor=colors.white)
status={
 'SKIPPED':ParagraphStyle('grey',parent=small,fontName='Helvetica-Bold',textColor=GREY),
 'INCOMPLETE':ParagraphStyle('red',parent=small,fontName='Helvetica-Bold',textColor=RED),
 'PARTIALLY CONFIGURED':ParagraphStyle('amber',parent=small,fontName='Helvetica-Bold',textColor=AMBER),
 'CONFIGURED':ParagraphStyle('green',parent=small,fontName='Helvetica-Bold',textColor=GREEN),
}
def P(value,style=body):return Paragraph(value,style)
def page(canvas,doc):
 canvas.saveState();w,h=landscape(A4);canvas.setFillColor(NAVY);canvas.rect(0,h-17*mm,w,17*mm,fill=1,stroke=0);canvas.setFillColor(colors.white);canvas.setFont('Helvetica-Bold',8);canvas.drawString(16*mm,h-10.5*mm,'CARRIER CONFIGURATION  /  AHM565');canvas.setFillColor(TEXT);canvas.setFont('Helvetica',7.5);canvas.drawRightString(w-16*mm,9*mm,f'C2 completion rules  |  Page {doc.page}');canvas.restoreState()
def styled(table,first=True,vpad=6):
 rules=[('BACKGROUND',(0,0),(-1,0),NAVY),('GRID',(0,0),(-1,-1),.6,LINE),('VALIGN',(0,0),(-1,-1),'TOP'),('ALIGN',(0,0),(-1,-1),'LEFT'),('LEFTPADDING',(0,0),(-1,-1),7),('RIGHTPADDING',(0,0),(-1,-1),7),('TOPPADDING',(0,0),(-1,-1),vpad),('BOTTOMPADDING',(0,0),(-1,-1),vpad)]
 if first:rules.append(('BACKGROUND',(0,1),(0,-1),PALE))
 table.setStyle(TableStyle(rules));return table

doc=BaseDocTemplate(str(OUTPUT),pagesize=landscape(A4),leftMargin=16*mm,rightMargin=16*mm,topMargin=24*mm,bottomMargin=15*mm,title='C2 Configuration Completion Rules')
doc.addPageTemplates(PageTemplate(id='main',frames=Frame(doc.leftMargin,doc.bottomMargin,doc.width,doc.height,id='normal'),onPage=page))
story=[P('C2 Configuration Completion Rules',title),P('AHM565 Sheet C2 - Balance and Special Information - Output on Loadsheet',subtitle),Spacer(1,6*mm),P('Section status rules',h2)]
section_rows=[
 [P('SECTION',white),P('SKIPPED',white),P('INCOMPLETE',white),P('CONFIGURED',white)],
 [P('Loadsheet Documents'),P('No Loadsheet Document option is selected.',small),P('Not used for this section.',small),P('At least one Loadsheet Document option is selected.',small)],
 [P('Balance Output'),P('No Loadsheet Document option is selected; there are no active document columns.',small),P('Document options are active, but no valid Balance Output item is selected in any active column.',small),P('At least one valid Balance Output item is selected in at least one active document column.',small)],
 [P('Passenger Trim Output'),P('No Loadsheet Document option is selected.',small),P('Document options are active, but no valid Passenger Trim option is selected.',small),P('At least one Passenger Trim option is selected with a valid, unique priority.',small)],
]
section=styled(Table(section_rows,colWidths=[48*mm,66*mm,70*mm,71*mm],repeatRows=1))
section.setStyle(TableStyle([('BACKGROUND',(1,1),(1,-1),LIGHT_GREY),('BACKGROUND',(2,1),(2,-1),LIGHT_RED),('BACKGROUND',(3,1),(3,-1),LIGHT_GREEN)]))
story += [section,Spacer(1,6*mm),P('C2 page status',h2)]
page_rows=[
 [P('CONDITION',white),P('PAGE RESULT',white),P('REASON',white)],
 [P('No Loadsheet Document option is selected.',small),P('SKIPPED',status['SKIPPED']),P('The form has no active document columns, so Balance Output and Passenger Trim Output are also skipped.',small)],
 [P('Documents are active, but neither Balance Output nor Passenger Trim Output is configured.',small),P('INCOMPLETE',status['INCOMPLETE']),P('Both required output sections still need attention.',small)],
 [P('Documents are active and exactly one of Balance Output or Passenger Trim Output is configured.',small),P('PARTIALLY CONFIGURED',status['PARTIALLY CONFIGURED']),P('Useful configuration exists, but one required output section remains incomplete.',small)],
 [P('Documents are active and both Balance Output and Passenger Trim Output are configured.',small),P('CONFIGURED',status['CONFIGURED']),P('All C2 completion requirements are satisfied.',small)],
]
story += [styled(Table(page_rows,colWidths=[105*mm,48*mm,102*mm],repeatRows=1),False),Spacer(1,6*mm),P('Scope boundary',h2)]
scope=[[P('ITEM',white),P('C2 COMPLETION TREATMENT',white)],[P('Lower Loadsheet Information'),P('Not included in the C2 completion result. Its completion rule will be handled separately with the applicable later-sheet work.',small)]]
story += [styled(Table(scope,colWidths=[62*mm,193*mm],repeatRows=1)),PageBreak(),P('C2 Validation and Operational Rules',title),P('Selection, priority and save behaviour',subtitle),Spacer(1,6*mm),P('Detailed rules',h2)]
rules=[
 [P('RULE',white),P('IMPLEMENTED BEHAVIOUR',white)],
 [P('Active document columns'),P('Only saved Loadsheet Document options selected by the carrier create active Balance Output columns. Master Required values remain suggestions.',small)],
 [P('Balance Output counting'),P('A checked item counts only when its document column is active and that item is permitted for the document format.',small)],
 [P('Passenger Trim selection'),P('At least one Passenger Trim option must be checked when document options are active.',small)],
 [P('Passenger Trim priority'),P('Every selected option requires a whole-number priority from 1 to 3, and selected options must use different priorities.',small)],
 [P('Skipped form'),P('When every Loadsheet Document option is cleared, Balance Output and Passenger Trim Output are skipped and an empty Passenger Trim selection may be saved.',small)],
 [P('New document protection'),P('A newly selected document is not saved if its new column contains no selected Balance Output item. The column is removed and the user receives the existing error message.',small)],
 [P('Remarks'),P('Alternative Loadsheet Terminology or Remarks remains standalone and does not count as a Passenger Trim selection. Output Remarks and Print RC do not independently configure Balance Output.',small)],
 [P('EDIT / SAVE'),P('Each screen section retains its independent EDIT controls. Status badges show saved data and update after a successful save.',small)],
 [P('Stale edit protection'),P('A save is rejected when the C2 record changed after the page was loaded.',small)],
 [P('Authorisation'),P('Authorised users may view C2. Only authorised administrators may save changes.',small)],
]
story += [styled(Table(rules,colWidths=[62*mm,193*mm],repeatRows=1),True,5)]
doc.build(story)
print(OUTPUT)
