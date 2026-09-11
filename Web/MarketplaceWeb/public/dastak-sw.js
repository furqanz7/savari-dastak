self.addEventListener("push", (event) => {
  let message = {};
  try { message = event.data ? event.data.json() : {}; } catch { message = {}; }
  const title = typeof message.title === "string" ? message.title : "Dastak update";
  const body = typeof message.body === "string" ? message.body : "Your order has an update.";
  const payload = message.payload && typeof message.payload === "object" ? message.payload : {};
  event.waitUntil(self.registration.showNotification(title, {
    body,
    icon: "/favicon.svg",
    badge: "/favicon.svg",
    tag: typeof payload.eventId === "string" ? payload.eventId : undefined,
    data: payload,
  }));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  const entityId = typeof data.entityId === "string"
    ? data.entityId
    : typeof data.orderId === "string" ? data.orderId
    : typeof data.parcelId === "string" ? data.parcelId
    : undefined;
  const riderNotification = typeof data.notificationType === "string" && data.notificationType.startsWith("rider.");
  const riderRoute = riderNotification && data.eventType === "RIDER_POOL_OPENED"
    ? "offer"
    : riderNotification && data.eventType === "RETURN_RIDER_ASSIGNED" ? "return"
    : riderNotification && ["RIDER_ASSIGNED", "FULFILMENT_READY"].includes(data.eventType) ? "mission"
    : undefined;
  const riderEntityId = riderRoute === "return" && typeof data.returnMissionId === "string"
    ? data.returnMissionId
    : riderRoute && typeof data.missionId === "string" ? data.missionId
    : undefined;
  const route = data.entityType === "parcel" ? "parcel"
    : data.entityType === "merchantOrder" ? "orders"
    : "v1-orders";
  const destination = riderRoute
    ? `/#/deliveries/${riderRoute}${riderEntityId ? `/${encodeURIComponent(riderEntityId)}` : ""}`
    : entityId ? `/#/${route}/${encodeURIComponent(entityId)}` : "/#/orders";
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    const existing = windows.find((client) => new URL(client.url).origin === self.location.origin);
    if (existing) {
      await existing.navigate(destination);
      return existing.focus();
    }
    return self.clients.openWindow(destination);
  })());
});
