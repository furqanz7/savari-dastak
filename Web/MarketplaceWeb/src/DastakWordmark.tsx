import "./design/brand.css";

// Restore the existing brand, with Urdu isolated from surrounding English UI.
export function DastakWordmark() {
  return <span className="dastak-wordmark"><span>Dastak</span><bdi lang="ur" dir="rtl">دستک</bdi></span>;
}
