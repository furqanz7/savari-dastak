import { expect, it } from "vitest";
import { daylightAt, parseWeather, weatherDescription, weatherUrl } from "./reimaginedWeather";

const now = Date.parse("2026-10-03T12:00:00Z");
const response = {
  timezone: "UTC", current: { time: now / 1000, temperature_2m: 24, cloud_cover: 80, precipitation: 1, weather_code: 61, wind_speed_10m: 22, wind_gusts_10m: 35, wind_direction_10m: 180, is_day: 1 },
  daily: { sunrise: [Date.parse("2026-10-03T06:00:00Z") / 1000], sunset: [Date.parse("2026-10-03T18:00:00Z") / 1000] },
};
it("sends rounded coordinates without device precision", () => {
  const url = new URL(weatherUrl(12.9715987, 77.5945627));
  expect(url.searchParams.get("latitude")).toBe("12.97");
  expect(url.searchParams.get("longitude")).toBe("77.59");
  expect(url.searchParams.get("timezone")).toBe("auto");
});
it("parses weather and rejects missing or expired readings", () => {
  expect(parseWeather(response, now)).toMatchObject({ cloud: .8, wind: 22, precipitation: 1, observedAt: now });
  expect(() => parseWeather({ ...response, current: { ...response.current, wind_speed_10m: null } }, now)).toThrow();
  expect(() => parseWeather(response, now + 60 * 60_000)).toThrow("out of date");
});
it("tracks daytime, nighttime and twilight from returned solar times", () => {
  const weather = parseWeather(response, now);
  expect(daylightAt(now, weather)).toBe(1);
  expect(daylightAt(Date.parse("2026-10-03T23:00:00Z"), weather)).toBe(0);
  expect(daylightAt(Date.parse("2026-10-03T06:00:00Z"), weather)).toBeCloseTo(.5);
  expect(weatherDescription(75)).toBe("Snow");
  expect(weatherDescription(95)).toBe("Thunderstorm");
});
