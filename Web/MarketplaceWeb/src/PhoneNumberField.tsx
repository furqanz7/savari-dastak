import { useId, useState } from "react";
import {
  getCountries,
  getCountryCallingCode,
  type CountryCode,
} from "libphonenumber-js/min";
import { canonicalPhoneNumber, splitPhoneNumber } from "./phoneNumber";

const countries = getCountries();
const countryNames = new Intl.DisplayNames(
  [typeof navigator === "undefined" ? "en" : navigator.language, "en"],
  { type: "region" },
);

export function PhoneNumberField({
  value,
  onChange,
  id,
  describedBy,
  invalid = false,
  required = false,
  disabled = false,
  onBlur,
}: {
  value: string;
  onChange: (value: string) => void;
  id?: string;
  describedBy?: string;
  invalid?: boolean;
  required?: boolean;
  disabled?: boolean;
  onBlur?: () => void;
}) {
  const generatedId = useId();
  const inputId = id ?? generatedId;
  const [initial] = useState(() => splitPhoneNumber(value));
  const [country, setCountry] = useState<CountryCode>(initial.country);
  const [nationalNumber, setNationalNumber] = useState(initial.nationalNumber);

  const updateCountry = (nextCountry: CountryCode) => {
    setCountry(nextCountry);
    onChange(canonicalPhoneNumber(nextCountry, nationalNumber));
  };

  const updateNumber = (nextValue: string) => {
    const digits = nextValue.replace(/\D/g, "");
    const callingCode = getCountryCallingCode(country);
    const trimmed = digits.slice(0, Math.max(0, 15 - callingCode.length));
    setNationalNumber(trimmed);
    onChange(canonicalPhoneNumber(country, trimmed));
  };

  return <div className="phone-number-field">
    <select
      aria-label="Country or region"
      value={country}
      disabled={disabled}
      onChange={(event) => updateCountry(event.target.value as CountryCode)}
    >
      {countries.map((code) => <option key={code} value={code}>
        {countryNames.of(code) ?? code} (+{getCountryCallingCode(code)})
      </option>)}
    </select>
    <span aria-hidden="true">+{getCountryCallingCode(country)}</span>
    <input
      id={inputId}
      type="tel"
      inputMode="numeric"
      autoComplete="tel-national"
      placeholder="Phone number"
      value={nationalNumber}
      required={required}
      disabled={disabled}
      aria-invalid={invalid || undefined}
      aria-describedby={describedBy}
      onChange={(event) => updateNumber(event.target.value)}
      onBlur={onBlur}
    />
  </div>;
}
