import {
  getCountries,
  getCountryCallingCode,
  parsePhoneNumberFromString,
  type CountryCode,
} from "libphonenumber-js/min";

type PhoneParts = {
  country: CountryCode;
  nationalNumber: string;
};

const countries = getCountries();

export function splitPhoneNumber(value: string, preferredCountry: CountryCode = "IN"): PhoneParts {
  const compact = `+${value.replace(/\D/g, "")}`;
  const parsed = parsePhoneNumberFromString(compact);
  if (parsed?.country) {
    return { country: parsed.country, nationalNumber: parsed.nationalNumber };
  }

  const matches = countries
    .map((country) => ({ country, code: getCountryCallingCode(country) }))
    .filter(({ code }) => compact.startsWith(`+${code}`))
    .sort((left, right) => right.code.length - left.code.length);
  const longest = matches[0]?.code;
  const selected = matches.find(({ country, code }) => code === longest && country === preferredCountry)
    ?? matches.find(({ code }) => code === longest)
    ?? { country: preferredCountry, code: getCountryCallingCode(preferredCountry) };
  return {
    country: selected.country,
    nationalNumber: compact.startsWith(`+${selected.code}`)
      ? compact.slice(selected.code.length + 1)
      : compact.slice(1),
  };
}

export function canonicalPhoneNumber(country: CountryCode, nationalNumber: string) {
  const parsed = parsePhoneNumberFromString(nationalNumber, country);
  if (parsed) return parsed.number;
  const callingCode = getCountryCallingCode(country);
  const maximumLength = Math.max(0, 15 - callingCode.length);
  return `+${callingCode}${nationalNumber.replace(/\D/g, "").slice(0, maximumLength)}`;
}
