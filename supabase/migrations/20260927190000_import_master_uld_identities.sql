begin;

insert into "Basic_Carrier_Record"."MASTER_ULD_List"
("ULD_ID","ULD_Type","ULD_TARE","ULD_Max_Gross_Weight","ULD_Base_Code","ULD_Base_Width","ULD_Base_Length","ULD_Contour_Code","Main_Deck_Only","ULD_Volume")
values
('AKE','LD3',100,1588,'K',61.5,60.4,'E',false,4.3),
('AKH','LD3-45',67,1588,'K',61.5,60.4,'E',false,3.5),
('AVE','LD3',100,1588,'K',61.5,60.4,'E',false,4.3),
('MDP','LDX',200,11300,'M',196,96,'M',true,29.6),
('P1P','LD7',110,4626,'1',125,88,null,false,11.5),
('P6P','LD7',130,6800,'6',125,96,null,false,11.5),
('PLA','LD8',95,3175,'L',125,60.4,null,false,8.6),
('PKC','LD3',100,1588,'K',61.5,60.4,'E',false,4.3),
('PAG','LD7',110,4626,'1',125,88,null,false,11.5),
('PMC','LD7',130,5669,'6',125,96,null,false,11.5)
on conflict ("ULD_ID") do update set
 "ULD_Type"=excluded."ULD_Type",
 "ULD_TARE"=excluded."ULD_TARE",
 "ULD_Max_Gross_Weight"=excluded."ULD_Max_Gross_Weight",
 "ULD_Base_Code"=excluded."ULD_Base_Code",
 "ULD_Base_Width"=excluded."ULD_Base_Width",
 "ULD_Base_Length"=excluded."ULD_Base_Length",
 "ULD_Contour_Code"=excluded."ULD_Contour_Code",
 "Main_Deck_Only"=excluded."Main_Deck_Only",
 "ULD_Volume"=excluded."ULD_Volume";

commit;
