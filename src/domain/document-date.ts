const documentMonths = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
] as const;

const formatDocumentDateParts = (year: number, monthIndex: number, day: number) => {
  const month = documentMonths[monthIndex];
  return month ? `${String(day).padStart(2, "0")} ${month} ${year}` : "";
};

export const formatLoadsheetDateParts = (year: number, monthIndex: number, day: number) =>
  `${String(day).padStart(2, "0")}${documentMonths[monthIndex]?.slice(0, 3).toUpperCase() ?? ""}${String(year).slice(-2)}`;

export const formatDocumentDate = (value: string) => {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return value;
  return formatDocumentDateParts(Number(match[1]), Number(match[2]) - 1, Number(match[3])) || value;
};
