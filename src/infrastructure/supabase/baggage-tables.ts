type Table<R> = {Row:R;Insert:Partial<R>&{Carrier_IATA:string};Update:Partial<R>;Relationships:[]};
export type BaggageTables = {
 Carrier_Baggage_Weights_ALLFLIGHTS:Table<{Carrier_IATA:string;Bag_Adult_Male:number;Bag_Adult_Female:number;Bag_Adult_Child:number;Bag_Standard_All:number|null;Bag_Standard_Summer:number|null;Bag_Standard_Winter:number|null;Per_Piece_Method:string;Remarks:string|null}>;
 Carrier_Baggage_Weights_BYCLASS:Table<{Carrier_IATA:string;Baggage_Weight_Set_ID:string;Class_Code:string|null;Flight_Type_Variation:string|null;Passenger_Category:string;Per_Piece_Method:string;Per_Passenger_Method:string;Baggage_Weight_Per_Piece:number|null;Baggage_Weight_Per_Passenger:number|null;Remarks:string|null;Is_Baseline:boolean;Flight_Scope_Label:string;Class_Scope_Label:string}>;
 Carrier_Planning_Assumptions:Table<{Carrier_IATA:string;Planning_Assumption_UUID:string;Class_Code:string|null;Flight_Type_Variation:string|null;Average_Bags_Per_Passenger:number;Average_Bag_Weight_Per_Passenger:number;Average_Bag_Volume:number|null;Remarks:string|null}>;
};
