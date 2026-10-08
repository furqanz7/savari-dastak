// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useReimaginedGrocerySearch } from "./useReimaginedGrocerySearch";
import { groceryFixture } from "./reimaginedCatalogue.testFixtures";
import type { getV1Catalogue, V1CatalogueSnapshot } from "./dastakV1";
Object.assign(globalThis,{IS_REACT_ACT_ENVIRONMENT:true});
type Loader=typeof getV1Catalogue;
const auth={accountId:"a",accessToken:"a",supabaseUrl:"https://example.invalid",publishableKey:"public"};
let root:Root;let host:HTMLDivElement;
function Harness({loader,draft="alias",submitted="",open=true,online=true,token="a"}:{loader:Loader;draft?:string;submitted?:string;open?:boolean;online?:boolean;token?:string}){
 const data=useReimaginedGrocerySearch({...auth,accessToken:token},draft,submitted,open,true,online,loader);
 return <output>{JSON.stringify({suggestions:data.suggestions?.map(s=>s.id),results:data.results?.map(s=>s.id),error:Boolean(data.error),resultsError:Boolean(data.resultsError)})}</output>;
}
function mount(loader:Loader){host=document.createElement("div");document.body.append(host);root=createRoot(host);act(()=>root.render(<Harness loader={loader}/>));}
beforeEach(()=>vi.useFakeTimers());afterEach(()=>{if(root)act(()=>root.unmount());host?.remove();vi.useRealTimers();});
describe("canonical Grocery search",()=>{
 it("debounces alias search, pages all results, and does not replace submitted results while typing",async()=>{
  const first={...groceryFixture.catalogue,skus:[groceryFixture.catalogue.skus[0]],nextCursor:{name:"Next",skuId:groceryFixture.catalogue.skus[0].id}};
  const next={...groceryFixture.catalogue,skus:[groceryFixture.catalogue.skus[1]],nextCursor:undefined};
  const loader=vi.fn<Loader>().mockResolvedValueOnce(first).mockResolvedValueOnce(next).mockRejectedValue(new Error("offline"));
  mount(loader);await act(async()=>vi.advanceTimersByTimeAsync(299));expect(loader).not.toHaveBeenCalled();
  await act(async()=>vi.advanceTimersByTimeAsync(1));expect(loader).toHaveBeenCalledTimes(2);expect(host.textContent).not.toContain('"results":');
  expect(loader.mock.calls[0][0].query).toBe("alias");
  act(()=>root.render(<Harness loader={loader} submitted="alias" open={false}/>));expect(host.textContent).toContain('"results":[');
  await act(async()=>{root.render(<Harness loader={loader} draft="other" submitted="alias"/>);vi.advanceTimersByTime(300);});
  await act(async()=>vi.advanceTimersByTimeAsync(300));expect(host.textContent).toContain('"error":true');expect(host.textContent).toContain('"resultsError":false');expect(host.textContent).toContain(first.skus[0].id);
 });
 it("ignores late token replies and does not fetch while offline",async()=>{
  let resolve!:(value:V1CatalogueSnapshot)=>void;
  const loader=vi.fn<Loader>().mockReturnValueOnce(new Promise(yes=>{resolve=yes;})).mockReturnValue(new Promise(()=>{}));
  mount(loader);await act(async()=>vi.advanceTimersByTimeAsync(300));
  act(()=>root.render(<Harness loader={loader} token="b" online={false}/>));expect(loader.mock.calls[0][0].signal?.aborted).toBe(true);
  await act(async()=>resolve(groceryFixture.catalogue));expect(host.textContent).not.toContain(groceryFixture.catalogue.skus[0].id);expect(loader).toHaveBeenCalledOnce();
 });
});
