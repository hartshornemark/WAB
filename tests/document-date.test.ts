import test from "node:test";
import assert from "node:assert/strict";
import { formatDocumentDate, formatLoadsheetDateParts } from "../src/domain/document-date";

test("printed operational documents use a long English date", () => {
  assert.equal(formatDocumentDate("2026-10-10"), "10 October 2026");
});

test("the loadsheet uses the IATA AHM DDMMMYY date", () => {
  assert.equal(formatLoadsheetDateParts(2026, 9, 10), "10OCT26");
});
