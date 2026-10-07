export type OutdoorWeather = {
  observedAt: number; fetchedAt: number; temperature: number; cloud: number;
  precipitation: number; code: number; wind: number; gust: number; direction: number;
  isDay: boolean; sunrise: number[]; sunset: number[]; timezone: string;
};
export const WEATHER_MAX_AGE = 45 * 60_000;
export function weatherUrl(latitude: number, longitude: number) {
  // Nearby-area weather only. Never persist or transmit device-precision coordinates.
  const params = new URLSearchParams({ latitude: latitude.toFixed(2), longitude: longitude.toFixed(2),
    current: "temperature_2m,cloud_cover,precipitation,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,is_day",
    daily: "sunrise,sunset", timezone: "auto", timeformat: "unixtime", forecast_days: "2" });
  return `https://api.open-meteo.com/v1/forecast?${params}`;
}
export function parseWeather(raw: unknown, now = Date.now()): OutdoorWeather {
  const data = raw as { current?: Record<string, unknown>; daily?: Record<string, unknown>; timezone?: unknown };
  const c = data?.current;
  const numeric = (name: string) => {
    const value = c?.[name];
    if (typeof value !== "number" || !Number.isFinite(value)) throw new Error("Incomplete weather response");
    return value;
  };
  const dates = (name: string): number[] => {
    const values = data.daily?.[name];
    if (!Array.isArray(values) || !values.length || values.some(v => typeof v !== "number" || !Number.isFinite(v))) throw new Error("Missing solar times");
    return values.map(v => v * 1000);
  };
  const observedAt = numeric("time") * 1000;
  if (Math.abs(now - observedAt) > WEATHER_MAX_AGE) throw new Error("Weather data is out of date");
  if (typeof data.timezone !== "string") throw new Error("Missing timezone");
  return { observedAt, fetchedAt: now, temperature: numeric("temperature_2m"), cloud: Math.max(0, Math.min(1, numeric("cloud_cover") / 100)),
    precipitation: Math.max(0, numeric("precipitation")), code: numeric("weather_code"), wind: Math.max(0, numeric("wind_speed_10m")),
    gust: Math.max(0, numeric("wind_gusts_10m")), direction: numeric("wind_direction_10m"), isDay: numeric("is_day") === 1,
    sunrise: dates("sunrise"), sunset: dates("sunset"), timezone: data.timezone };
}
export function daylightAt(now: number, weather: OutdoorWeather | null) {
  const smooth = (v: number) => { const x = Math.max(0, Math.min(1, v)); return x * x * (3 - 2 * x); };
  if (weather) {
    // Actual sunrise/sunset, including a 40-minute twilight transition.
    return Math.max(...weather.sunrise.map((rise, i) => smooth((now - rise + 20 * 60_000) / (40 * 60_000)) * (1 - smooth((now - weather.sunset[i] + 20 * 60_000) / (40 * 60_000)))));
  }
  // Explicitly labelled time-only approximation until location is granted.
  const date = new Date(now); const hour = date.getHours() + date.getMinutes() / 60;
  return smooth((hour - 5.5) / 1.25) * (1 - smooth((hour - 17.5) / 1.25));
}
export function weatherDescription(code: number) {
  if (code === 0) return "Clear";
  if (code <= 3) return "Cloudy";
  if (code <= 48) return "Fog";
  if ([71, 73, 75, 77, 85, 86].includes(code)) return "Snow";
  if (code >= 95) return "Thunderstorm";
  return "Rain";
}
