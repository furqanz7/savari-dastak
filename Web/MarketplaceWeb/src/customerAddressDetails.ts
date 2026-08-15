export function combineDoorstepDetails(building: string, landmark: string) {
  return [building.trim(), landmark.trim()].filter(Boolean).join(" • ");
}

export function splitDoorstepDetails(details?: string) {
  const [building = "", ...landmark] = (details ?? "").split(" • ");
  return { building, landmark: landmark.join(" • ") };
}
