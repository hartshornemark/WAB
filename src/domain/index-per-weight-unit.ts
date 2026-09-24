export type IndexPerWeightUnitFormula={referenceArm:number;constantC:number};

export function validIndexPerWeightUnitFormula(value:IndexPerWeightUnitFormula|null|undefined):value is IndexPerWeightUnitFormula{return !!value&&Number.isFinite(value.referenceArm)&&Number.isFinite(value.constantC)&&value.constantC>0}

export function balanceArmFromIndexPerWeightUnit(indexPerWeightUnit:number,formula:IndexPerWeightUnitFormula){return Math.round((formula.referenceArm+formula.constantC*indexPerWeightUnit)*1_000_000)/1_000_000}

export function indexPerWeightUnitFromBalanceArm(balanceArm:number,formula:IndexPerWeightUnitFormula){return Math.round(((balanceArm-formula.referenceArm)/formula.constantC)*100_000)/100_000}


export function balanceArmCentroidInput(centroid:unknown,indexPerWeightUnit:number|null,formula:IndexPerWeightUnitFormula|null|undefined){return indexPerWeightUnit!==null&&validIndexPerWeightUnitFormula(formula)?balanceArmFromIndexPerWeightUnit(indexPerWeightUnit,formula):centroid}
