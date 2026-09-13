import { useEffect, useRef, type RefObject } from "react";

// Opt-in record/confirmation layers can leave together during session recovery.
// Restore shared page state only after the last owning layer releases it.
let layeredScrollLocks = 0;
let layeredOriginalOverflow = "";
const layeredIsolation = new Map<HTMLElement, { count: number; inert: boolean; ariaHidden: string | null }>();

type ModalDialogOptions = {
  busy?: boolean;
  onDismiss: () => void;
  initialFocus?: RefObject<HTMLElement | null>;
  /** Admin record editors may open a separate governed confirmation above them. */
  layered?: boolean;
};

export function useModalDialog<T extends HTMLElement = HTMLElement>({ busy = false, onDismiss, initialFocus, layered = false }: ModalDialogOptions) {
  const dialog = useRef<T>(null);
  const busyState = useRef(busy);
  const dismiss = useRef(onDismiss);
  busyState.current = busy;
  dismiss.current = onDismiss;

  useEffect(() => {
    const opener = document.activeElement instanceof HTMLElement ? document.activeElement : undefined;
    const originalOverflow = document.body.style.overflow;
    const isolated = isolateDialog(dialog.current, layered);
    if (layered) {
      if (layeredScrollLocks === 0) layeredOriginalOverflow = originalOverflow;
      layeredScrollLocks += 1;
    }
    document.body.style.overflow = "hidden";

    const focusTarget = initialFocus?.current ?? focusableElements(dialog.current, layered)[0] ?? dialog.current;
    focusTarget?.focus();

    const handleKey = (event: KeyboardEvent) => {
      if (layered) {
        const layers = document.querySelectorAll<HTMLElement>('[aria-modal="true"]');
        if (layers[layers.length - 1] !== dialog.current) return;
      }
      if (event.key === "Escape" && !busyState.current) {
        event.preventDefault();
        dismiss.current();
        return;
      }
      if (event.key !== "Tab") return;
      const elements = focusableElements(dialog.current, layered);
      if (elements.length === 0) {
        event.preventDefault();
        dialog.current?.focus();
        return;
      }
      const first = elements[0];
      const last = elements[elements.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };

    document.addEventListener("keydown", handleKey);
    return () => {
      document.removeEventListener("keydown", handleKey);
      if (layered) {
        layeredScrollLocks -= 1;
        if (layeredScrollLocks === 0) document.body.style.overflow = layeredOriginalOverflow;
      } else document.body.style.overflow = originalOverflow;
      isolated.forEach(({ element, inert: previousInert, ariaHidden: previousAriaHidden }) => {
        let inert = previousInert;
        let ariaHidden = previousAriaHidden;
        if (layered) {
          const owner = layeredIsolation.get(element);
          if (owner && --owner.count > 0) return;
          if (owner) { inert = owner.inert; ariaHidden = owner.ariaHidden; }
          layeredIsolation.delete(element);
        }
        element.inert = inert;
        if (ariaHidden === null) element.removeAttribute("aria-hidden");
        else element.setAttribute("aria-hidden", ariaHidden);
      });
      opener?.focus();
    };
  }, [initialFocus, layered]);

  return dialog;
}

function isolateDialog(dialog: HTMLElement | null, layered = false) {
  const isolated: Array<{ element: HTMLElement; inert: boolean; ariaHidden: string | null }> = [];
  let active: HTMLElement | null = dialog;
  while (active?.parentElement && active.parentElement !== document.body) {
    const parent: HTMLElement = active.parentElement;
    Array.from(parent.children).forEach((sibling) => {
      if (!(sibling instanceof HTMLElement) || sibling === active || sibling.contains(active)) return;
      isolated.push({
        element: sibling,
        inert: sibling.inert,
        ariaHidden: sibling.getAttribute("aria-hidden"),
      });
      if (layered) {
        const owner = layeredIsolation.get(sibling);
        if (owner) owner.count += 1;
        else layeredIsolation.set(sibling, { count: 1, inert: sibling.inert, ariaHidden: sibling.getAttribute("aria-hidden") });
      }
      sibling.inert = true;
      sibling.setAttribute("aria-hidden", "true");
    });
    active = parent;
  }
  return isolated;
}

function focusableElements(root: HTMLElement | null, layered = false) {
  if (!root) return [];
  return Array.from(root.querySelectorAll<HTMLElement>(
    'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), ' + (layered ? 'summary, ' : '') + '[tabindex]:not([tabindex="-1"])',
  )).filter((element) => {
    if (element.hidden || element.getAttribute("aria-hidden") === "true") return false;
    if (!layered) return true;
    if (element.closest('[inert], [hidden], [aria-hidden="true"]')) return false;
    let ancestor = element.parentElement;
    while (ancestor && ancestor !== root) {
      if (ancestor instanceof HTMLDetailsElement && !ancestor.open && !ancestor.querySelector(":scope > summary")?.contains(element)) return false;
      ancestor = ancestor.parentElement;
    }
    return true;
  });
}
