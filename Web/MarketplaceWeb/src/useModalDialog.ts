import { useEffect, useRef, type RefObject } from "react";

type ModalDialogOptions = {
  busy?: boolean;
  onDismiss: () => void;
  initialFocus?: RefObject<HTMLElement | null>;
};

export function useModalDialog<T extends HTMLElement = HTMLElement>({ busy = false, onDismiss, initialFocus }: ModalDialogOptions) {
  const dialog = useRef<T>(null);
  const busyState = useRef(busy);
  const dismiss = useRef(onDismiss);
  busyState.current = busy;
  dismiss.current = onDismiss;

  useEffect(() => {
    const opener = document.activeElement instanceof HTMLElement ? document.activeElement : undefined;
    const originalOverflow = document.body.style.overflow;
    const isolated = isolateDialog(dialog.current);
    document.body.style.overflow = "hidden";

    const focusTarget = initialFocus?.current ?? focusableElements(dialog.current)[0] ?? dialog.current;
    focusTarget?.focus();

    const handleKey = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !busyState.current) {
        event.preventDefault();
        dismiss.current();
        return;
      }
      if (event.key !== "Tab") return;
      const elements = focusableElements(dialog.current);
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
      document.body.style.overflow = originalOverflow;
      isolated.forEach(({ element, inert, ariaHidden }) => {
        element.inert = inert;
        if (ariaHidden === null) element.removeAttribute("aria-hidden");
        else element.setAttribute("aria-hidden", ariaHidden);
      });
      opener?.focus();
    };
  }, [initialFocus]);

  return dialog;
}

function isolateDialog(dialog: HTMLElement | null) {
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
      sibling.inert = true;
      sibling.setAttribute("aria-hidden", "true");
    });
    active = parent;
  }
  return isolated;
}

function focusableElements(root: HTMLElement | null) {
  if (!root) return [];
  return Array.from(root.querySelectorAll<HTMLElement>(
    'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
  )).filter((element) => !element.hidden && element.getAttribute("aria-hidden") !== "true");
}
