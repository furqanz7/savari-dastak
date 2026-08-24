import { useEffect } from "react";
import { ArrowLeft, ArrowUpRight, FileText, LifeBuoy, ShieldCheck } from "lucide-react";
import {
  publicInformationPages,
  type PublicInformationKind,
} from "./publicInformation";

export function PublicInformationPage({ kind }: { kind: PublicInformationKind }) {
  const page = publicInformationPages[kind];

  useEffect(() => {
    document.title = `${page.title} — Dastak`;
    document.querySelector('meta[name="description"]')?.setAttribute("content", page.summary);
  }, [page]);

  return (
    <div className="public-information-page">
      <header className="public-information-header">
        <a className="public-information-brand" href="/" aria-label="Dastak home">
          <span>Dastak <b lang="ur">دستک</b></span>
        </a>
        <nav aria-label="Public information">
          <a aria-current={kind === "privacy" ? "page" : undefined} href="/privacy">Privacy</a>
          <a aria-current={kind === "terms" ? "page" : undefined} href="/terms">Terms</a>
          <a aria-current={kind === "support" ? "page" : undefined} href="/support">Support</a>
        </nav>
      </header>

      <main className="public-information-main">
        <a className="public-information-back" href="/"><ArrowLeft size={17} /> Back to Dastak</a>
        <section className="public-information-hero">
          <div className="public-information-icon" aria-hidden="true">
            {kind === "privacy" ? <ShieldCheck /> : kind === "terms" ? <FileText /> : <LifeBuoy />}
          </div>
          <p className="eyebrow">{page.eyebrow}</p>
          <h1>{page.title}</h1>
          <p>{page.summary}</p>
          <small>Effective {page.updated}</small>
        </section>

        {page.actions && (
          <nav className="public-information-actions" aria-label="Support actions">
            {page.actions.map((action) => (
              <a key={action.title} href={action.href}>
                <span><strong>{action.title}</strong><small>{action.detail}</small></span>
                <ArrowUpRight aria-hidden="true" />
              </a>
            ))}
          </nav>
        )}

        <article className="public-information-document">
          {page.sections.map((section) => (
            <section key={section.title}>
              <h2>{section.title}</h2>
              {section.paragraphs?.map((paragraph) => <p key={paragraph}>{paragraph}</p>)}
              {section.bullets && <ul>{section.bullets.map((bullet) => <li key={bullet}>{bullet}</li>)}</ul>}
            </section>
          ))}
        </article>
      </main>

      <footer className="public-information-footer">
        <span>Dastak · Vaniyambadi, Tamil Nadu</span>
        <nav aria-label="Footer">
          <a href="/privacy">Privacy</a>
          <a href="/terms">Terms</a>
          <a href="/support">Support</a>
        </nav>
      </footer>
    </div>
  );
}
