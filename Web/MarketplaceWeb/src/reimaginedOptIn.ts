// A query parameter alone must never activate unfinished UI on a hosted build.
export function reimaginedLocalOptIn(development: boolean, location?: Pick<Location, "hostname" | "search">) {
  return development && Boolean(location && ["localhost", "127.0.0.1", "[::1]", "::1"].includes(location.hostname)
    && new URLSearchParams(location.search).get("reimagined") === "1");
}

// Explicitly approved hosted browsing trial; authentication remains owned by App.
// This is not an authorization mechanism. Checkout remains independently disabled.
export function reimaginedHostedOptIn(location?: Pick<Location, "hostname" | "search">) {
  return Boolean(location && ["dastak-customer.vercel.app", "dastak-liquiflows-projects.vercel.app"].includes(location.hostname)
    && new URLSearchParams(location.search).get("reimagined") === "1");
}

export function existingCustomerUrl(section: "home" | "orders" | "account", href: string) {
  const url = new URL(href);
  url.searchParams.delete("reimagined");
  url.hash = section;
  return url.href;
}
