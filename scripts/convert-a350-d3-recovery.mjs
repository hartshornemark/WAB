import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

const source = process.argv[2];
const destination = process.argv[3];

if (!source || !destination) {
  throw new Error("Usage: node convert-a350-d3-recovery.mjs SOURCE.csv DESTINATION.csv");
}

await mkdir(dirname(destination), { recursive: true });

function parseCsv(text) {
  const rows = [];
  let row = [], cell = "", quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (quoted) {
      if (character === '"' && text[index + 1] === '"') { cell += '"'; index += 1; }
      else if (character === '"') quoted = false;
      else cell += character;
    } else if (character === '"') quoted = true;
    else if (character === ",") { row.push(cell); cell = ""; }
    else if (character === "\n") { row.push(cell); rows.push(row); row = []; cell = ""; }
    else if (character !== "\r") cell += character;
  }
  row.push(cell);
  if (row.some(value => value.trim())) rows.push(row);
  return rows;
}

const escapeCsv = value => {
  const text = String(value ?? "");
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
};

const columns = [
    "Aircraft Type IATA",
    "Series/Sub-Type",
    "Deck ID",
    "Hold ID",
    "Hold Sub Code",
    "Compartment ID",
    "Bay ID",
    "ULD ID / Config",
    "Max Weight",
    "Centroid",
    "FWD",
    "AFT",
    "Index per wt unit",
    "Fore-Aft Dimension (in)",
];
const records = parseCsv((await readFile(source, "utf8")).replace(/^\uFEFF/, ""));
const sourceHeaders = records.shift() ?? [];
const sourceColumn = name => sourceHeaders.indexOf(name);
const outputRows = [columns];

for (const row of records) {
  if (!row.some(value => value.trim())) continue;
  const sourceValue = name => row[sourceColumn(name)] ?? "";
  const position = sourceValue("Position Name").trim().toUpperCase();
  const firstDigit = position.match(/\d/)?.[0];
  const hold = firstDigit === "1" || firstDigit === "2" ? "FWD" : firstDigit === "3" || firstDigit === "4" ? "AFT" : null;
  if (!hold || !firstDigit) throw new Error(`Cannot route position ${position || "(blank)"}.`);
  const converted = {
    "Aircraft Type IATA": "359",
    "Series/Sub-Type": "900",
    "Deck ID": "LOWER",
    "Hold ID": hold,
    "Hold Sub Code": "",
    "Compartment ID": firstDigit,
    "Bay ID": position,
    "ULD ID / Config": sourceValue("Group ID / Config").replace(/\*+$/, ""),
    "Max Weight": sourceValue("Max Weight"),
    Centroid: sourceValue("Centroid"),
    FWD: sourceValue("FWD"),
    AFT: sourceValue("AFT"),
    "Index per wt unit": sourceValue("Index per wt unit"),
    "Fore-Aft Dimension (in)": "",
  };
  outputRows.push(columns.map(column => converted[column]));
}

await writeFile(destination, `${outputRows.map(row => row.map(escapeCsv).join(",")).join("\r\n")}\r\n`);
