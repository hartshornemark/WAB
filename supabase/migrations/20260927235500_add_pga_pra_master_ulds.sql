begin;

insert into "Basic_Carrier_Record"."MASTER_ULD_List"
("ULD_ID","ULD_Type","ULD_TARE","ULD_Max_Gross_Weight","ULD_Base_Code","ULD_Base_Width","ULD_Base_Length","ULD_Contour_Code","Main_Deck_Only","ULD_Volume")
values
('PGA','M-6',541,13608,'M',238.5,96,null,true,33.2),
('PRA','LDX',469,11340,'M',196,96,null,true,26.8)
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
