from pathlib import Path
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak

out=Path('output/pdf/E1_1_Dry_Operating_Weight_Completion_Rules.pdf')
out.parent.mkdir(parents=True,exist_ok=True)
navy=colors.HexColor('#132E57');blue=colors.HexColor('#3568BF');muted=colors.HexColor('#596E8F');line=colors.HexColor('#CCD9EE')
green=colors.HexColor('#2F6E46');greenbg=colors.HexColor('#E7F5EB');amber=colors.HexColor('#8A6411');amberbg=colors.HexColor('#FFF5D8');red=colors.HexColor('#9B2C2C');redbg=colors.HexColor('#FCECEC');grey=colors.HexColor('#657186');greybg=colors.HexColor('#EDF1F6')
s=getSampleStyleSheet()
s.add(ParagraphStyle(name='TitleX',parent=s['Title'],fontName='Helvetica-Bold',fontSize=19,leading=23,textColor=navy,spaceAfter=4))
s.add(ParagraphStyle(name='Sub',parent=s['Normal'],fontSize=9,leading=12,textColor=muted))
s.add(ParagraphStyle(name='H2X',parent=s['Heading2'],fontName='Helvetica-Bold',fontSize=12,leading=15,textColor=navy,spaceBefore=8,spaceAfter=5))
s.add(ParagraphStyle(name='Cell',parent=s['Normal'],fontSize=8,leading=10.5,textColor=navy))
s.add(ParagraphStyle(name='CellC',parent=s['Cell'],alignment=TA_CENTER,fontName='Helvetica-Bold'))
s.add(ParagraphStyle(name='Head',parent=s['Cell'],fontName='Helvetica-Bold',textColor=colors.white,alignment=TA_CENTER))
P=lambda x,st='Cell':Paragraph(x,s[st])
def table(data,widths,rag=False):
 t=Table(data,colWidths=widths,repeatRows=1)
 cmd=[('BACKGROUND',(0,0),(-1,0),navy),('GRID',(0,0),(-1,-1),.5,line),('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),7),('RIGHTPADDING',(0,0),(-1,-1),7),('TOPPADDING',(0,0),(-1,-1),6),('BOTTOMPADDING',(0,0),(-1,-1),6),('ROWBACKGROUNDS',(1,1),(-1,-1),[colors.white,colors.HexColor('#F7F9FC')])]
 if rag:
  cmd += [('BACKGROUND',(0,1),(0,1),greenbg),('TEXTCOLOR',(0,1),(0,1),green),('BACKGROUND',(0,2),(0,2),amberbg),('TEXTCOLOR',(0,2),(0,2),amber),('BACKGROUND',(0,3),(0,3),redbg),('TEXTCOLOR',(0,3),(0,3),red),('BACKGROUND',(0,4),(0,4),greybg),('TEXTCOLOR',(0,4),(0,4),grey)]
 t.setStyle(TableStyle(cmd));return t
def footer(canvas,doc):
 canvas.saveState();canvas.setFillColor(colors.white);canvas.rect(0,0,A4[1],A4[0],fill=1,stroke=0);canvas.setFillColor(blue);canvas.rect(0,A4[0]-10,A4[1],10,fill=1,stroke=0);canvas.setStrokeColor(line);canvas.line(15*mm,10*mm,282*mm,10*mm);canvas.setFillColor(muted);canvas.setFont('Helvetica',7);canvas.drawString(15*mm,6*mm,'Carrier Configuration - E1.1 Completion Rules');canvas.drawRightString(282*mm,6*mm,f'Page {doc.page}');canvas.restoreState()
doc=SimpleDocTemplate(str(out),pagesize=landscape(A4),rightMargin=15*mm,leftMargin=15*mm,topMargin=13*mm,bottomMargin=14*mm,title='E1.1 Dry Operating Weight Completion Rules')
story=[P('E1.1 DRY OPERATING WEIGHT','TitleX'),P('AHM565 Sheet E1.1 - Configuration Completion Rule Matrix','Sub'),Spacer(1,5*mm),P('Scope and data ownership','H2X'),P('E1.1 records the starting-weight principle for each carrier, aircraft type and series/sub-type. The selected principle is written to Basic_Aircraft_Data. Dry Operating Weight inclusions are maintained in Carrier_Dry_Operating_Weight_Inclusions. Basic Weight and Basic Index are separately provisioned on Carrier_Aircraft_Fleet for later registration-level data entry.'),Spacer(1,3*mm)]
sections=[[P('SECTION','Head'),P('APPLICABILITY','Head'),P('CONFIGURED RULE','Head'),P('OTHER STATUS','Head')],[P('1. Start Weight Principle'),P('Always assessed.'),P('Exactly one radio option is selected: Basic Weight or Dry Operating Weight.'),P('No selection: INCOMPLETE.')],[P('2. Dry Operating Weight Inclusions'),P('Assessed only when Dry Operating Weight is selected. When Basic Weight is selected, this section is SKIPPED.'),P('Basic Weight is fixed TRUE and at least one additional item is selected.'),P('Basic Weight only: PARTIALLY CONFIGURED. No valid inclusion data: INCOMPLETE.')]]
story += [table(sections,[155,185,280,165]),Spacer(1,5*mm),P('Page status matrix','H2X')]
status=[[P('STATUS','Head'),P('START WEIGHT PRINCIPLE','Head'),P('DOW INCLUSIONS','Head'),P('PAGE RESULT','Head')],[P('CONFIGURED','CellC'),P('Basic Weight selected.'),P('SKIPPED.'),P('CONFIGURED.')],[P('PARTIALLY CONFIGURED','CellC'),P('Dry Operating Weight selected.'),P('Basic Weight is selected but no additional item is selected.'),P('PARTIALLY CONFIGURED.')],[P('NOT CONFIGURED','CellC'),P('No valid principle is selected.'),P('Cannot be assessed until a principle is selected.'),P('NOT CONFIGURED.')],[P('SKIPPED','CellC'),P('Basic Weight selected.'),P('Section 2 is intentionally not applicable.'),P('Section status only; the page remains CONFIGURED.')]]
story += [table(status,[145,210,275,155],True),PageBreak(),P('E1.1 DATA AND CONTROL RULES','TitleX'),P('Field behaviour, persistence and validation','Sub'),Spacer(1,5*mm)]
rules=[[P('ITEM','Head'),P('RULE','Head'),P('STORAGE / DISPLAY','Head')],[P('Start Weight Principle'),P('Required radio selection between Basic Weight and Dry Operating Weight. The database accepts only BASIC_WEIGHT or DRY_OPERATING_WEIGHT.'),P('Basic_Aircraft_Data.Start_Weight_Principle. Displayed read-only outside EDIT mode.')],[P('Basic Weight inclusion'),P('Always TRUE. The checkbox is checked and disabled, and a database check prevents it from being saved FALSE.'),P('Carrier_Dry_Operating_Weight_Inclusions.Included.')],[P('Other DOW inclusions'),P('Each master inclusion item may be selected independently. Selected items are included in DOW; unselected items remain part of traffic load.'),P('Carrier_Dry_Operating_Weight_Inclusions, keyed by Carrier IATA and DOW Item.')],[P('Basic Weight / Basic Index'),P('Nullable positive Basic Weight and nullable finite Basic Index fields are provisioned for later fleet-registration entry.'),P('Carrier_Aircraft_Fleet.Basic_Weight and Basic_Index.')],[P('Concurrency and permissions'),P('Every save checks the current revision and aircraft-configuration edit permission. A stale page cannot overwrite newer data.'),P('Server action and SECURITY INVOKER database functions.')],[P('Global controls'),P('EDIT enters edit mode. SAVE validates and persists. CANCEL discards unsaved changes. Completion badges remain the furthest-right item.'),P('Applied independently to both E1.1 sections.')]]
story += [table(rules,[175,330,280])]
doc.build(story,onFirstPage=footer,onLaterPages=footer)
print(out)
