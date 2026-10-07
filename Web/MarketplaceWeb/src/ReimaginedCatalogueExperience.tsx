import type { ComponentProps, ReactNode } from "react";
import type { DastakV1Auth } from "./dastakV1";
import { ReimaginedShell } from "./ReimaginedShell";
import { ReimaginedGrocery, ReimaginedGrocerySuggestions } from "./ReimaginedGrocery";
import { reimaginedDirectory } from "./reimaginedDirectory";
import { useReimaginedCatalogue } from "./useReimaginedCatalogue";

type Props = Omit<ComponentProps<typeof ReimaginedShell>, "children" | "directory" | "directoryStatus" | "onRetryDirectory" | "searchSuggestions"> & {
  auth?: DastakV1Auth;
  eligibility: ComponentProps<typeof ReimaginedGrocery>["eligibility"];
  relatedSkuIds?: ComponentProps<typeof ReimaginedGrocery>["relatedSkuIds"];
  checkoutContent: ReactNode;
  foodContent: ReactNode;
  foodSearchSuggestions?: ReactNode;
};

// Authenticated integration boundary. The current customer root will supply its
// session, authoritative eligibility, checkout and single cart state ownership.
// Preview fixtures never enter this component.
export function ReimaginedCatalogueExperience({ auth, eligibility, relatedSkuIds, checkoutContent, foodContent, foodSearchSuggestions, ...shell }: Props) {
  const accountId = shell.state.accountId;
  const resource = useReimaginedCatalogue(auth && accountId ? { ...auth, accountId } : undefined);
  return <ReimaginedShell {...shell} directory={resource.data ? reimaginedDirectory(resource.data.map) : []} directoryStatus={resource.status} onRetryDirectory={resource.retry}
    searchSuggestions={shell.state.service === "grocery" ? <ReimaginedGrocerySuggestions data={resource.data} query={shell.state.exploration.grocery.searchDraft} dispatch={shell.dispatch} /> : foodSearchSuggestions}>
    {shell.state.service === "grocery" ? <ReimaginedGrocery state={shell.state} dispatch={shell.dispatch} data={resource.data} status={resource.status} onRetry={resource.retry} supabaseUrl={auth?.supabaseUrl ?? ""} eligibility={eligibility} relatedSkuIds={relatedSkuIds} checkoutContent={checkoutContent} /> : foodContent}
  </ReimaginedShell>;
}
