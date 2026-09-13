import { useRef, useState, type ReactNode } from "react";
import { Menu, ShieldCheck, X } from "lucide-react";
import { useModalDialog } from "./useModalDialog";

export type AdminNavigationItem<T extends string> = { id: T; label: string; icon: ReactNode; badge?: number };
export type AdminNavigationGroup<T extends string> = { label: string; items: AdminNavigationItem<T>[] };

/** Navigation changes presentation only: existing workspace state remains the owner. */
export function AdminWorkspaceNavigation<T extends string>({ groups, selected, onSelect, displayName, role }: {
  groups: AdminNavigationGroup<T>[];
  selected: T;
  onSelect: (id: T) => void;
  displayName: string;
  role: string;
}) {
  const [open, setOpen] = useState(false);
  const current = groups.flatMap((group) => group.items).find((item) => item.id === selected);
  const links = (navigate: (id: T) => void) => groups.map((group) => <nav key={group.label} aria-label={group.label} className="admin-nav-group">
    <p>{group.label}</p>
    {group.items.map((item) => <button type="button" key={item.id} aria-current={selected === item.id ? "page" : undefined} onClick={() => navigate(item.id)}>
      <span aria-hidden="true">{item.icon}</span><span>{item.label}</span>{item.badge ? <b aria-label={`${item.badge} needing attention`}>{item.badge}</b> : null}
    </button>)}
  </nav>);
  const identity = <footer><ShieldCheck size={18} aria-hidden="true" /><div><strong>{displayName}</strong><small>{role}</small></div></footer>;
  return <>
    <aside className="admin-sidebar" aria-label="Admin navigation"><header><strong>Dastak<span>.</span></strong><small>OPERATIONS</small></header>{links(onSelect)}{identity}</aside>
    <div className="admin-mobile-bar"><span className="admin-mobile-brand">Dastak<span>.</span></span><button type="button" className="secondary-button" aria-haspopup="dialog" aria-expanded={open} onClick={() => setOpen(true)}><Menu size={19} />{current?.label ?? "Workspaces"}</button></div>
    {open ? <AdminNavigationDrawer onDismiss={() => setOpen(false)}>{links((id) => { onSelect(id); setOpen(false); })}{identity}</AdminNavigationDrawer> : null}
  </>;
}

function AdminNavigationDrawer({ children, onDismiss }: { children: ReactNode; onDismiss: () => void }) {
  const close = useRef<HTMLButtonElement>(null);
  const dialog = useModalDialog<HTMLElement>({ onDismiss, initialFocus: close });
  return <div className="admin-navigation-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) onDismiss(); }}>
    <section ref={dialog} className="admin-navigation-drawer" role="dialog" aria-modal="true" aria-labelledby="admin-navigation-title" tabIndex={-1}>
      <header><div><small>DASTAK OPERATIONS</small><h2 id="admin-navigation-title">Workspaces</h2></div><button ref={close} type="button" className="icon-button" onClick={onDismiss} aria-label="Close navigation"><X size={20} /></button></header>
      {children}
    </section>
  </div>;
}
