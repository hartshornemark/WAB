import{readFileSync,readdirSync,statSync}from"node:fs";
import{join,relative}from"node:path";

const roots=["src/components"];
const retired=["Index Value","Index per Unit Weight","Index / Wt Unit","BA Centroid","Index per Weight Unit","Maximum Weight (Kg)","Maximum Weight (KG)","KG/m²"];
const failures=[];

function visit(path){
  for(const name of readdirSync(path)){
    const file=join(path,name),stat=statSync(file);
    if(stat.isDirectory()){visit(file);continue;}
    if(!name.endsWith(".tsx")&&!name.endsWith(".py"))continue;
    const source=readFileSync(file,"utf8");
    for(const label of retired)if(source.includes(label))failures.push(`${relative(process.cwd(),file)}: retired label “${label}”`);
    const approvedHArmFiles=[join("src","components","aircraft-c8.tsx"),join("src","components","csv-import-help.tsx")];
    if(source.includes("H-Arm")&&!approvedHArmFiles.some(approved=>file.endsWith(approved)))failures.push(`${relative(process.cwd(),file)}: H-Arm is reserved for C8 Fuel Standard`);
  }
}

for(const root of roots)visit(root);
if(failures.length){console.error(failures.join("\n"));process.exit(1)}
console.log("Global column heading audit passed.");
