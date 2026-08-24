import { parsePhoneNumberFromString } from "npm:libphonenumber-js@1.13.11/min";

export function isValidDastakPhoneNumber(value: string) {
  const parsed = parsePhoneNumberFromString(value.trim());
  return parsed?.isValid() === true && parsed.number === value.trim();
}
