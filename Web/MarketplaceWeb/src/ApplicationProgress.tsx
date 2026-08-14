import { Check } from "lucide-react";

const steps = ["Account", "Application", "Review"] as const;

export function ApplicationProgress({ current = 2 }: { current?: 1 | 2 | 3 }) {
  return (
    <ol className="application-progress" aria-label={`Step ${current} of 3`}>
      {steps.map((step, index) => {
        const number = index + 1;
        const complete = number < current;
        const active = number === current;
        return (
          <li key={step} className={active ? "active" : complete ? "complete" : ""} aria-current={active ? "step" : undefined}>
            <span>{complete ? <Check size={14} /> : number}</span>
            <small>{step}</small>
          </li>
        );
      })}
    </ol>
  );
}
